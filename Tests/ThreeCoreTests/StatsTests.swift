import Foundation
import GRDB
import Testing
@testable import ThreeCore

private func statsStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-stats-\(UUID().uuidString)/db.sqlite"))
}

private func statsCalendar(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func statsDate(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

private func statsTask(_ store: Store, day: String, title: String = "Build", category: String = "Coding",
                       minutes: Int = 30, tags: [String] = []) throws -> FocusTask {
    try store.addTask(NewTask(title: title, category: category, blockMinutes: minutes, tags: tags),
                      day: DayKey(day)!, source: .cli)
}

@discardableResult private func statsSession(_ store: Store, task: FocusTask?, id: String = UUID().uuidString,
                                            at: String, seconds: Int, planned: Int = 1800, paused: Int = 0,
                                            rating: FocusRating? = nil, kind: SessionKind = .focus) throws -> String {
    let start = statsDate(at)
    try store.db.write { db in
        try Session(id: id, taskId: task?.id, kind: kind, plannedSeconds: planned, startedAt: start,
                    pausedAt: nil, pausedSeconds: paused, endedAt: start.addingTimeInterval(Double(seconds + paused)),
                    endReason: .stopped, outcome: nil, focusRating: rating, note: nil, updatedAt: start).insert(db)
    }
    return id
}

private func statsDone(_ store: Store, _ task: FocusTask, at: String) throws {
    try store.db.write { db in
        try db.execute(sql: "UPDATE task SET status = 'done', doneAt = ? WHERE id = ?", arguments: [statsDate(at), task.id])
    }
}

private func statsEvent(_ store: Store, rule: String, session: String?, at: String, hit: Bool = true) throws {
    try store.db.write { db in
        try db.execute(sql: "INSERT INTO blockEvent (id, at, ruleId, sessionId, action) VALUES (?, ?, ?, ?, ?)",
                       arguments: [UUID().uuidString, statsDate(at), rule, session, hit ? "blocked" : "unblocked"])
    }
}

@Test func statsFiveMetricsHaveIndependentExpectedValuesAndTagOverlapCountsGloballyOnce() throws {
    let store = try statsStore()
    let a = try statsTask(store, day: "2026-11-02", tags: ["Three", "Client"])
    let b = try statsTask(store, day: "2026-11-02", title: "Write", category: "Writing", minutes: 60, tags: ["Client"])
    let draft = try statsTask(store, day: "2026-11-03", title: "Draft", minutes: 30)
    try statsDone(store, a, at: "2026-11-02T11:00:00Z")
    try statsDone(store, draft, at: "2026-11-03T11:00:00Z")
    try store.commit(day: DayKey("2026-11-02")!)
    let s1 = try statsSession(store, task: a, at: "2026-11-02T09:00:00Z", seconds: 1800, paused: 7200, rating: .focused)
    try statsSession(store, task: b, at: "2026-11-02T12:00:00Z", seconds: 900, rating: .scattered)
    try statsSession(store, task: b, at: "2026-11-02T13:00:00Z", seconds: 900)
    try statsSession(store, task: nil, at: "2026-11-02T14:00:00Z", seconds: 600, kind: .break)
    let rule = try store.addBlockRule(.domain(BlockDomain(parsing: "example.com")))
    for second in ["01", "02", "03"] {
        try statsEvent(store, rule: rule.id, session: s1, at: "2026-11-02T09:00:\(second)Z")
    }
    try statsEvent(store, rule: rule.id, session: s1, at: "2026-11-02T09:01:00Z", hit: false)
    try statsEvent(store, rule: rule.id, session: nil, at: "2026-11-03T09:01:00Z")
    let report = try store.stats(from: DayKey("2026-10-28")!, through: DayKey("2026-11-03")!,
                                 now: statsDate("2026-11-03T16:00:00Z"), calendar: statsCalendar())
    #expect(report.metrics.focusSeconds == 3600)
    #expect(report.metrics.focusMinutes == 60)
    #expect(report.days.last?.sevenDayAverageMinutes == 60.0 / 7)
    #expect(report.days.first?.sevenDayAverageMinutes == nil)
    #expect(report.metrics.derivedPlannedSeconds == 7200)
    #expect(report.metrics.actualToPlanned.value == 2.0 / 3)
    #expect(report.metrics.completion.numerator == 1)
    #expect(report.metrics.completion.denominator == 2)
    #expect(report.metrics.completion.value == 0.5)
    #expect(report.metrics.committedPlanCount == 1)
    #expect(report.metrics.quality.focusSessionCount == 3)
    #expect(report.metrics.quality.focusedShare.value == 0.5)
    #expect(report.metrics.quality.missingRatingCount == 1)
    #expect(report.metrics.categoryQuality.first { $0.category?.name == "Coding" }?.quality.focusedShare.value == 1)
    #expect(report.metrics.categoryQuality.first { $0.category?.name == "Writing" }?.quality.focusedShare.value == 0)
    #expect(report.metrics.blocks.hitsPerFocusHour.value == 3)
    #expect(report.metrics.blocks.unblocksPerFocusHour.value == 1)
    #expect(report.metrics.blocks.unassociatedHits == 1)
    #expect(report.metrics.blocks.topTargets.first?.associatedHits == 3)
    #expect(report.metrics.blocks.topTargets.first?.hitCount == 4)
    #expect(report.tags.first { $0.tag.name == "Three" }?.metrics.focusSeconds == 1800)
    #expect(report.tags.first { $0.tag.name == "Three" }?.metrics.completion.value == 1)
    #expect(report.tags.first { $0.tag.name == "Client" }?.metrics.completion.value == 0.5)
    #expect(report.tags.first { $0.tag.name == "Three" }?.metrics.blocks.hitsPerFocusHour.value == 6)
    #expect(report.tags.first { $0.tag.name == "Client" }?.metrics.focusSeconds == 3600)
    #expect(report.tags.first { $0.tag.name == "Client" }?.metrics.blocks.unassociatedHits == 0)
    #expect(report.tags.first { $0.tag.name == "Client" }?.days.last?.sevenDayAverageMinutes == 60.0 / 7)
    #expect(report.weeks.map(\.includedDayCount) == [5, 2])
    #expect(report.weeks.allSatisfy { $0.isPartial })
    #expect(report.weeks.last?.metrics.completion.value == 0.5)
    #expect(report.days.last?.isPartial == true)
    #expect(report.isPartial)
    #expect(report.streak.days == 1)
    #expect(report.streak.currentIncompleteDayPreservesPrevious)
    #expect(!report.streak.isLowerBound)
    #expect(!report.missingData.commitmentSnapshotsUnavailable)
    #expect(report.missingData.blockerCoverageUnknown)
    #expect(report.missingData.missingRatingCount == 1)
    let encoded = try JSONEncoder().encode(report)
    #expect(try JSONDecoder().decode(StatsReport.self, from: encoded) == report)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let metrics = try #require(json["metrics"] as? [String: Any])
    #expect((metrics["actualToPlanned"] as? [String: Double])?["value"] == 2.0 / 3)
}

@Test func statsZeroActivityAndUnavailableDenominatorsRemainDistinct() throws {
    let store = try statsStore()
    let now = statsDate("2026-11-03T12:00:00Z")
    let empty = try store.stats(now: now, calendar: statsCalendar())
    #expect(empty.from == DayKey("2026-10-07")!)
    #expect(empty.days.count == 28)
    #expect(empty.metrics.focusSeconds == 0)
    #expect(empty.days.last?.sevenDayAverageMinutes == 0)
    #expect(empty.metrics.completion.value == nil)
    #expect(empty.metrics.actualToPlanned.value == nil)
    #expect(empty.metrics.quality.focusedShare.value == nil)
    #expect(empty.metrics.blocks.hitsPerFocusHour.value == nil)
    #expect(empty.metrics.blocks.associatedHits == 0)
    #expect(empty.missingData.historicalCoverageUnknown)
    let task = try statsTask(store, day: "2026-11-02")
    try store.commit(day: DayKey("2026-11-02")!)
    try statsSession(store, task: task, at: "2026-11-02T09:00:00Z", seconds: 1800)
    let recorded = try store.stats(now: now, calendar: statsCalendar())
    #expect(recorded.metrics.completion.value == 0)
    #expect(recorded.metrics.blocks.hitsPerFocusHour.value == 0)
    #expect(recorded.metrics.quality.focusedShare.value == nil)
    #expect(recorded.metrics.quality.missingRatingCount == 1)
}

@Test func statsCarryDeletedAndMissingReferencesPreserveActualsWithoutInventingPlans() throws {
    let store = try statsStore()
    let source = try statsTask(store, day: "2026-11-01", tags: ["Three"])
    try statsSession(store, task: source, at: "2026-11-01T09:00:00Z", seconds: 600, rating: .okay)
    let copy = try store.carryTask(source.id, to: DayKey("2026-11-02")!)
    try statsSession(store, task: copy, at: "2026-11-02T09:00:00Z", seconds: 1200)
    try store.commit(day: DayKey("2026-11-02")!)
    try store.db.write { db in
        try db.execute(sql: "UPDATE category SET deletedAt = ?, archived = 1 WHERE id = ?", arguments: [Date(), source.categoryId])
        try db.execute(sql: "UPDATE task SET deletedAt = ? WHERE id = ?", arguments: [Date(), copy.id])
    }
    let report = try store.stats(from: DayKey("2026-11-01")!, through: DayKey("2026-11-02")!, calendar: statsCalendar())
    #expect(report.metrics.focusSeconds == 1800)
    #expect(report.metrics.derivedPlannedSeconds == 0)
    #expect(report.metrics.completion.value == 0)
    #expect(report.metrics.committedPlannedSeconds == 1800)
    #expect(report.metrics.accuracyFocusSeconds == 1200)
    #expect(report.metrics.actualToPlanned.value == 2.0 / 3)
    #expect(report.tags.first?.metrics.focusSeconds == 1800)
    #expect(report.metrics.categoryQuality.first?.category?.archived == true)
    var config = Configuration()
    config.foreignKeysEnabled = false
    let legacy = try DatabaseQueue(path: store.db.path, configuration: config)
    try legacy.write { db in
        try db.execute(sql: "DELETE FROM category WHERE id = ?", arguments: [source.categoryId])
        try db.execute(sql: "DELETE FROM task WHERE id = ?", arguments: [source.id])
    }
    let missing = try store.stats(from: DayKey("2026-11-01")!, through: DayKey("2026-11-02")!, calendar: statsCalendar())
    #expect(missing.metrics.focusSeconds == 1800)
    #expect(missing.missingData.missingTaskReferenceCount == 1)
    #expect(missing.missingData.missingCategoryReferenceCount == 2)
}

@Test func statsBlocksFollowFocusStartDayAndAmbientEventsNeverEnterTheRate() throws {
    let store = try statsStore()
    let task = try statsTask(store, day: "2026-11-01", tags: ["Three"])
    let session = try statsSession(store, task: task, at: "2026-11-01T23:30:00Z", seconds: 3600)
    let rest = try statsSession(store, task: nil, at: "2026-11-02T01:00:00Z", seconds: 300, kind: .break)
    let rule = try store.addBlockRule(.domain(BlockDomain(parsing: "example.com")))
    try statsEvent(store, rule: rule.id, session: session, at: "2026-11-02T00:01:00Z")
    try statsEvent(store, rule: rule.id, session: nil, at: "2026-11-01T09:00:00Z", hit: false)
    try statsEvent(store, rule: rule.id, session: rest, at: "2026-11-02T01:01:00Z")
    let first = try store.stats(from: DayKey("2026-11-01")!, through: DayKey("2026-11-01")!, calendar: statsCalendar())
    let second = try store.stats(from: DayKey("2026-11-02")!, through: DayKey("2026-11-02")!, calendar: statsCalendar())
    #expect(first.metrics.blocks.associatedHits == 1)
    #expect(first.metrics.blocks.hitsPerFocusHour.value == 1)
    #expect(first.metrics.blocks.unassociatedUnblocks == 1)
    #expect(second.metrics.blocks.associatedHits == 0)
    #expect(second.metrics.blocks.unassociatedHits == 1)
    #expect(second.metrics.blocks.hitsPerFocusHour.value == nil)
    #expect(second.tags.isEmpty)
    var config = Configuration()
    config.foreignKeysEnabled = false
    let legacy = try DatabaseQueue(path: store.db.path, configuration: config)
    try legacy.write { db in
        try db.execute(sql: "UPDATE blockEvent SET sessionId = 'missing' WHERE sessionId = ?", arguments: [rest])
        try db.execute(sql: "DELETE FROM blockRule WHERE id = ?", arguments: [rule.id])
    }
    let missing = try store.stats(from: DayKey("2026-11-02")!, through: DayKey("2026-11-02")!, calendar: statsCalendar())
    #expect(missing.metrics.blocks.unassociatedHits == 1)
    #expect(missing.metrics.blocks.unresolvedSessionEventCount == 1)
    #expect(missing.metrics.blocks.topTargets.first?.target == nil)
    #expect(missing.metrics.blocks.topTargets.first?.ruleId == rule.id)
}

@Test func statsTopTargetsAreBoundedAndDeterministic() throws {
    let store = try statsStore()
    for count in 1...4 {
        let rule = try store.addBlockRule(.domain(BlockDomain(parsing: "site\(count).com")))
        for _ in 0..<count { try statsEvent(store, rule: rule.id, session: nil, at: "2026-11-02T09:00:00Z") }
    }
    let report = try store.stats(from: DayKey("2026-11-02")!, through: DayKey("2026-11-02")!, calendar: statsCalendar())
    #expect(report.metrics.blocks.unassociatedHits == 10)
    #expect(report.metrics.blocks.topTargets.map(\.target) == ["site4.com", "site3.com", "site2.com"])
    #expect(report.metrics.blocks.topTargets.map(\.hitCount) == [4, 3, 2])
}

@Test func statsStreakUsesDoneAtOnThePlanDateAndKeepsYesterdayWhileTodayIsIncomplete() throws {
    let store = try statsStore()
    let a = try statsTask(store, day: "2026-11-01")
    let b = try statsTask(store, day: "2026-11-02")
    let c = try statsTask(store, day: "2026-11-03")
    for day in ["2026-11-01", "2026-11-02", "2026-11-03"] { try store.commit(day: DayKey(day)!) }
    try statsDone(store, a, at: "2026-11-01T10:00:00Z")
    try statsDone(store, b, at: "2026-11-02T10:00:00Z")
    let now = statsDate("2026-11-03T16:00:00Z")
    let read = { try store.stats(from: DayKey("2026-11-01")!, through: DayKey("2026-11-03")!, now: now, calendar: statsCalendar()) }
    let incomplete = try read()
    #expect(incomplete.streak.days == 2)
    #expect(incomplete.streak.isLowerBound)
    #expect(incomplete.streak.endingOn == DayKey("2026-11-02")!)
    try statsDone(store, c, at: "2026-11-03T10:00:00Z")
    #expect(try read().streak.days == 3)
    #expect(try read().streak.currentIncompleteDayPreservesPrevious == false)
    try store.db.write { db in
        try db.execute(sql: "UPDATE task SET doneAt = ? WHERE id = ?", arguments: [statsDate("2026-11-03T10:00:00Z"), b.id])
    }
    #expect(try read().streak.days == 1)
    #expect(try read().streak.isLowerBound == false)
    #expect(try read().metrics.completion.value == 1)
    try store.db.write { db in try db.execute(sql: "UPDATE task SET status = 'todo' WHERE id = ?", arguments: [c.id]) }
    #expect(try read().streak.days == 0)
}

@Test func statsClosedAndDraftPlansAndLegacyMissingDoneTimesDoNotInventStreaks() throws {
    let store = try statsStore()
    let a = try statsTask(store, day: "2026-11-01")
    let b = try statsTask(store, day: "2026-11-02")
    try statsDone(store, a, at: "2026-11-01T09:00:00Z")
    try statsDone(store, b, at: "2026-11-02T09:00:00Z")
    try store.commit(day: DayKey("2026-11-02")!)
    try store.db.write { db in try db.execute(sql: "UPDATE dayPlan SET status = 'closed' WHERE id = ?", arguments: [b.dayPlanId]) }
    let report = try store.stats(from: DayKey("2026-11-01")!, through: DayKey("2026-11-02")!, calendar: statsCalendar())
    #expect(report.days.map(\.qualifiesForStreak) == [false, true])
    #expect(report.metrics.completion.denominator == 1)
    #expect(report.streak.days == 1)
    try store.db.write { db in try db.execute(sql: "UPDATE task SET doneAt = NULL WHERE id = ?", arguments: [b.id]) }
    let missing = try store.stats(from: report.from, through: report.through, calendar: statsCalendar())
    #expect(missing.streak.days == 0)
    #expect(missing.missingData.missingCompletionTimestampCount == 1)
}

@Test func statsProspectiveDenominatorsSurviveLaterEditsDropsCarryAndClose() throws {
    let store = try statsStore()
    let a = try statsTask(store, day: "2026-11-01", tags: ["Three"])
    let b = try statsTask(store, day: "2026-11-01", title: "Carry", minutes: 45, tags: ["Three"])
    try store.commit(day: DayKey("2026-11-01")!)
    try store.updateTask(a.id, blockMinutes: 90)
    let late = try statsTask(store, day: "2026-11-01", title: "Added later", minutes: 15)
    try statsDone(store, a, at: "2026-11-01T10:00:00Z")
    try statsDone(store, late, at: "2026-11-01T11:00:00Z")
    try statsSession(store, task: a, at: "2026-11-01T09:00:00Z", seconds: 1800)
    let read = { try store.stats(from: DayKey("2026-11-01")!, through: DayKey("2026-11-01")!, calendar: statsCalendar()) }
    let before = try read()
    #expect(before.metrics.committedPlannedTaskCount == 2)
    #expect(before.metrics.completedTaskCount == 1)
    #expect(before.metrics.completion.value == 0.5)
    #expect(before.metrics.committedPlannedSeconds == 4500)
    #expect(before.metrics.derivedPlannedSeconds == 9000)
    #expect(before.metrics.actualToPlanned.value == 0.4)
    let closed = try store.closeDay(DayKey("2026-11-01")!, now: DayKey("2026-11-01")!.startDate.addingTimeInterval(23 * 3600))
    guard case .closed = closed else { Issue.record("Expected a frozen close summary"); return }
    try store.carryTask(b.id, to: DayKey("2026-11-03")!)
    let after = try read()
    #expect(after.metrics.completion.value == 0.5)
    #expect(after.metrics.committedPlannedSeconds == 4500)
    #expect(after.metrics.derivedPlannedSeconds == 6300)
    #expect(after.tags.first?.metrics.completion.value == 0.5)
    try store.db.write { db in
        try db.execute(sql: "UPDATE task SET status = 'dropped', deletedAt = ? WHERE id = ?", arguments: [Date(), a.id])
    }
    #expect(try read().metrics.completion.value == 0.5)
    #expect(try read().metrics.focusSeconds == 1800)
}

@Test func statsLegacyPlansKeepDerivedTotalsWithoutInventingCommitmentRatios() throws {
    let store = try statsStore()
    let legacy = try statsTask(store, day: "2026-11-01")
    let modern = try statsTask(store, day: "2026-11-02", minutes: 60)
    try store.commit(day: DayKey("2026-11-01")!)
    try store.commit(day: DayKey("2026-11-02")!)
    try statsDone(store, legacy, at: "2026-11-01T10:00:00Z")
    try statsSession(store, task: legacy, at: "2026-11-01T09:00:00Z", seconds: 900)
    try statsSession(store, task: modern, at: "2026-11-02T09:00:00Z", seconds: 1800)
    try store.db.write { db in
        try db.execute(sql: "DELETE FROM planCommitment WHERE planId = ?", arguments: [legacy.dayPlanId])
    }
    let report = try store.stats(from: DayKey("2026-11-01")!, through: DayKey("2026-11-02")!, calendar: statsCalendar())
    #expect(report.metrics.focusSeconds == 2700)
    #expect(report.metrics.derivedPlannedSeconds == 5400)
    #expect(report.metrics.committedPlanCount == 2)
    #expect(report.metrics.commitmentSnapshotPlanCount == 1)
    #expect(report.metrics.legacyCommittedPlanCount == 1)
    #expect(report.metrics.committedPlannedSeconds == 3600)
    #expect(report.metrics.accuracyFocusSeconds == 1800)
    #expect(report.metrics.actualToPlanned.value == 0.5)
    #expect(report.metrics.completion.value == 0)
    #expect(report.days.first?.metrics.completion.value == nil)
    #expect(report.days.first?.metrics.actualToPlanned.value == nil)
    #expect(report.missingData.commitmentSnapshotsUnavailable)
    #expect(report.days.first?.qualifiesForStreak == true)
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report.days.first!.metrics.completion)) as? [String: Any]
    #expect(json?["value"] is NSNull)
}

@Test func statsRecordedBreakDecisionsUseOnlyKnownEndedFocusChoices() throws {
    let store = try statsStore()
    let task = try statsTask(store, day: "2026-11-02", tags: ["Three"])
    let at = statsDate("2026-11-02T09:00:00Z")
    try store.startFocus(taskId: task.id, now: at)
    try store.finishFocus(outcome: .progress, rating: .okay, note: nil, markTaskDone: false,
                          continuation: .break, now: at.addingTimeInterval(600))
    try store.stop(now: at.addingTimeInterval(900))
    try store.startFocus(taskId: task.id, now: at.addingTimeInterval(1200))
    try store.finishFocus(outcome: .progress, rating: .focused, note: nil, markTaskDone: false,
                          breakDecision: .skipped, now: at.addingTimeInterval(1800))
    try store.startFocus(taskId: task.id, now: at.addingTimeInterval(2100))
    try store.stop(now: at.addingTimeInterval(2400))
    try store.startFocus(taskId: task.id, now: at.addingTimeInterval(2700))
    try store.pause(now: at.addingTimeInterval(3000))
    let report = try store.stats(from: DayKey("2026-11-02")!, through: DayKey("2026-11-02")!,
                                 now: at.addingTimeInterval(10000), calendar: statsCalendar())
    #expect(report.metrics.focusSeconds == 1800)
    #expect(report.metrics.breaks.endedFocusSessionCount == 3)
    #expect(report.metrics.breaks.pendingFocusSessionCount == 1)
    #expect(report.metrics.breaks.takenCount == 1)
    #expect(report.metrics.breaks.skippedCount == 1)
    #expect(report.metrics.breaks.recordedDecisionCount == 2)
    #expect(report.metrics.breaks.missingDecisionCount == 1)
    #expect(report.metrics.breaks.skippedShare.value == 0.5)
    #expect(report.missingData.missingBreakDecisionCount == 1)
    #expect(report.tags.first?.metrics.breaks.skippedShare.value == 0.5)
    let repeated = try store.stats(from: report.from, through: report.through, now: report.takenAt, calendar: statsCalendar())
    #expect(repeated == report)
}

@Test func statsKeepsOriginalDenominatorsWhenCommittedTaskReferencesAreMissing() throws {
    let store = try statsStore()
    let task = try statsTask(store, day: "2026-11-02", tags: ["Three"])
    try store.commit(day: DayKey("2026-11-02")!)
    try statsSession(store, task: task, at: "2026-11-02T09:00:00Z", seconds: 600)
    var config = Configuration()
    config.foreignKeysEnabled = false
    let legacy = try DatabaseQueue(path: store.db.path, configuration: config)
    try legacy.write { db in try db.execute(sql: "DELETE FROM task WHERE id = ?", arguments: [task.id]) }
    let report = try store.stats(from: DayKey("2026-11-02")!, through: DayKey("2026-11-02")!, calendar: statsCalendar())
    #expect(report.metrics.focusSeconds == 600)
    #expect(report.metrics.committedPlannedSeconds == 1800)
    #expect(report.metrics.completion.denominator == 1)
    #expect(report.metrics.completion.value == 0)
    #expect(report.missingData.committedTasksMissingCurrentReferences == 1)
    #expect(report.metrics.quality.focusedShare.value == nil)
    #expect(report.metrics.breaks.skippedShare.value == nil)
}

@Test func statsFullWeeksAndRangeBoundsRespectCivilDates() throws {
    let store = try statsStore()
    let full = try store.stats(from: DayKey("2026-10-26")!, through: DayKey("2026-11-01")!, calendar: statsCalendar())
    #expect(full.weeks.count == 1)
    #expect(full.weeks.first?.isPartial == false)
    #expect(full.weeks.first?.weekStarting == DayKey("2026-10-26")!)
    let partial = try store.stats(from: full.from, through: full.through, now: statsDate("2026-11-01T12:00:00Z"), calendar: statsCalendar())
    #expect(partial.weeks.first?.includedDayCount == 7)
    #expect(partial.weeks.first?.isPartial == true)
    let max = try store.stats(from: DayKey("2025-11-03")!, through: DayKey("2026-11-03")!, calendar: statsCalendar())
    #expect(max.days.count == 366)
    #expect(throws: ThreeError.self) { try store.stats(from: DayKey("2025-11-02")!, through: max.through) }
    #expect(throws: ThreeError.self) { try store.stats(from: max.through, through: max.from) }
    #expect(throws: ThreeError.self) {
        try store.stats(through: DayKey("2026-11-04")!, now: statsDate("2026-11-03T12:00:00Z"), calendar: statsCalendar())
    }
}

@Test func statsResolvesMovedCommitmentsWithoutAnOriginalDaySession() throws {
    let original = DayKey("2026-11-01")!
    for destination in [DayKey("2026-11-02"), nil] {
        for hasSession in [false, true] {
            let store = try statsStore()
            let task = try statsTask(store, day: original.rawValue, tags: ["Three"])
            try store.commit(day: original)
            try store.schedule(task.id, on: destination)
            try store.setTaskStatus(task.id, .done)
            if hasSession {
                try statsSession(store, task: task, at: "2026-11-01T09:00:00Z", seconds: 600)
            }
            let report = try store.stats(from: original, through: original, calendar: statsCalendar())
            #expect(report.metrics.completion.value == 1)
            #expect(report.metrics.completion.denominator == 1)
            #expect(report.metrics.committedPlannedSeconds == 1800)
            #expect(report.metrics.focusSeconds == (hasSession ? 600 : 0))
            #expect(report.weeks.first?.metrics.completion.value == 1)
            #expect(report.missingData.committedTasksMissingCurrentReferences == 0)
            let tagged = try #require(report.tags.first { $0.tag.name == "Three" })
            #expect(tagged.metrics.committedPlannedSeconds == 1800)
            #expect(tagged.metrics.completion.value == 1)
            #expect(tagged.days.first?.metrics.completion.value == 1)
        }
    }
}

@Test func statsFreezesRunningAndPausedWorkAndAllowsAccuracyAboveOneHundredPercent() throws {
    let store = try statsStore()
    let task = try statsTask(store, day: "2026-11-02", minutes: 15)
    let start = statsDate("2026-11-02T09:00:00Z")
    try store.startFocus(taskId: task.id, now: start)
    let running = try store.stats(from: DayKey("2026-11-02")!, through: DayKey("2026-11-02")!,
                                  now: start.addingTimeInterval(1800), calendar: statsCalendar())
    #expect(running.metrics.focusSeconds == 1800)
    #expect(running.metrics.actualToPlanned.percent == 200)
    #expect(running.metrics.breaks.pendingFocusSessionCount == 1)
    #expect(running.metrics.breaks.missingDecisionCount == 0)
    try store.pause(now: start.addingTimeInterval(1800))
    let paused = try store.stats(from: running.from, through: running.through,
                                 now: start.addingTimeInterval(20000), calendar: statsCalendar())
    #expect(paused.metrics.focusSeconds == 1800)
    #expect(paused.metrics.actualToPlanned.percent == 200)
    #expect(running.metrics.focusSeconds == 1800)
    #expect(paused.metrics.quality.focusedShare.value == nil)
}

@Test func statsSkippedCivilDateRemainsAnEmptyDateAndStreakUsesReportTimeZone() throws {
    let store = try statsStore()
    let task = try statsTask(store, day: "2011-12-31")
    try store.commit(day: DayKey("2011-12-31")!)
    try statsDone(store, task, at: "2011-12-30T12:00:00Z")
    try statsSession(store, task: task, at: "2011-12-30T12:30:00Z", seconds: 600)
    let local = try store.stats(from: DayKey("2011-12-29")!, through: DayKey("2011-12-31")!, calendar: statsCalendar("Pacific/Apia"))
    #expect(local.days.map(\.day.rawValue) == ["2011-12-29", "2011-12-30", "2011-12-31"])
    #expect(local.days.map(\.metrics.focusSeconds) == [0, 0, 600])
    #expect(local.streak.days == 1)
    let utc = try store.stats(from: local.from, through: local.through, calendar: statsCalendar())
    #expect(utc.days.map(\.metrics.focusSeconds) == [0, 600, 0])
    #expect(utc.streak.days == 0)
}

@Test(arguments: [
    ("America/Los_Angeles", "2026-03-08", "2026-03-08T09:30:00Z"),
    ("America/Los_Angeles", "2026-11-01", "2026-11-01T08:30:00Z"),
    ("America/Sao_Paulo", "2018-11-04", "2018-11-04T03:30:00Z"),
    ("Pacific/Apia", "2011-12-31", "2011-12-30T12:30:00Z"),
])
func statsDSTAndMidnightTransitionsMatchHistory(zone: String, day: String, at: String) throws {
    let store = try statsStore()
    let task = try statsTask(store, day: day)
    try statsSession(store, task: task, at: at, seconds: 3600, paused: 18000)
    let calendar = statsCalendar(zone)
    let stats = try store.stats(from: DayKey(day)!, through: DayKey(day)!, calendar: calendar)
    let history = try store.historyReport(from: DayKey(day)!, through: DayKey(day)!, calendar: calendar)
    #expect(stats.metrics.focusSeconds == 3600)
    #expect(stats.metrics.focusSeconds == history.totals.focusSeconds)
    #expect(stats.days.first?.day == DayKey(day)!)
}
