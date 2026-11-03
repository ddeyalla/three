import Foundation
import GRDB
import Testing
@testable import ThreeCore

private func closeStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-close-\(UUID().uuidString)/db.sqlite"))
}

private let closeDay = DayKey("2026-10-20")!
private var closeDue: Date { closeDay.startDate.addingTimeInterval(22 * 3600) }

@discardableResult
private func closeTask(_ store: Store, day: DayKey = closeDay, title: String = "Unfinished") throws -> FocusTask {
    try store.addTask(NewTask(title: title, category: "Coding", blockMinutes: 45, strict: true,
                              linearRef: "https://linear.app/brunoh-ai/issue/BPRO-404", notes: "Keep context", tags: ["release"]),
                      day: day, source: .mcp)
}

@Suite struct DayCloseTests {
    @Test func dayCloseRequiresANonemptyCommittedPlanAndNeverCreatesWork() throws {
        let store = try closeStore()
        #expect(try store.closeDay(closeDay, now: closeDue) == .notEligible(.noCommittedPlan))
        #expect(try store.snapshot(for: closeDay).plan == nil)
        try store.setPlan([], day: closeDay, source: .app, commit: true)
        #expect(try store.closeDay(closeDay, now: closeDue) == .notEligible(.emptyPlan))
        let draft = closeDay.adding(days: 1)
        let task = try closeTask(store, day: draft)
        #expect(try store.closeDay(draft, now: closeDue.addingTimeInterval(86400)) == .notEligible(.noCommittedPlan))
        try store.updateTask(task.id, title: "Still editable")
        #expect(try store.recentDayCloses().isEmpty)
        #expect(try store.snapshot(for: closeDay.adding(days: 2)).plan == nil)
    }

    @Test func dayCloseIsDurableIdempotentAndFreezesOutcomesBeforeCarry() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        let step = try store.addStep(to: task.id, title: "Investigate")
        try store.setStep(step.id, done: true)
        try store.addStep(to: task.id, title: "Ship")
        let at = closeDay.startDate.addingTimeInterval(9 * 3600)
        try store.startFocus(taskId: task.id, now: at)
        try store.pause(now: at.addingTimeInterval(300))
        try store.resume(now: at.addingTimeInterval(420))
        try store.finishFocus(outcome: .progress, rating: .focused, note: "Keep history", markTaskDone: false,
                              breakDecision: .skipped, now: at.addingTimeInterval(720))
        #expect(try store.closeDay(closeDay, now: closeDue.addingTimeInterval(-1)) == .notEligible(.notDue))
        let first = try store.closeDay(closeDay, now: closeDue)
        guard case .closed(let summary) = first else { Issue.record("Expected durable close"); return }
        #expect(try JSONDecoder().decode(DayCloseResult.self, from: JSONEncoder().encode(first)) == first)
        #expect(summary.focusedSeconds == 600)
        #expect(summary.plannedMinutes == 45)
        #expect(summary.commitment?.tasks.map(\.taskId) == [task.id])
        #expect(summary.focusSessions.first?.note == "Keep history")
        #expect(summary.skippedBreakCount == 1)
        #expect(summary.reason == .due)
        #expect(try store.closeDay(closeDay, now: closeDue.addingTimeInterval(10)) == first)
        let reopened = try Store(url: URL(fileURLWithPath: store.db.path))
        #expect(try reopened.closeDay(closeDay, now: closeDue.addingTimeInterval(86400)) == first)
        #expect(try reopened.recentDayCloses() == [summary])
        #expect(throws: ThreeError.self) { try reopened.updateTask(task.id, title: "Forbidden") }
        #expect(throws: ThreeError.self) { try reopened.addStep(to: task.id, title: "Forbidden") }
        let today = closeDay.adding(days: 1)
        let copy = try reopened.carryTask(task.id, to: today, now: closeDue)
        #expect(copy.carriedFromTaskId == task.id)
        #expect(copy.strict && copy.notes == task.notes && copy.linearRef == task.linearRef)
        #expect(copy.categoryId == task.categoryId && copy.createdBy == .mcp && copy.scheduledStart == nil)
        let copied = try #require(try reopened.snapshot(for: today).tasks.first)
        #expect(copied.steps.map(\.done) == [true, false])
        #expect(copied.steps.map(\.title) == ["Investigate", "Ship"])
        #expect(copied.tags.map(\.name) == ["release"])
        #expect(copied.focusedSeconds == 0)
        #expect(try reopened.snapshot(for: closeDay).tasks.first?.focusedSeconds == 600)
        #expect(try reopened.snapshot(for: closeDay).tasks.first?.task.status == .carried)
        #expect(try reopened.dayCloseSummary(for: closeDay) == summary)
        #expect(try reopened.carryTask(task.id, to: today).id == copy.id)
        #expect(try reopened.pushToTomorrow(task.id).id == copy.id)
        #expect(throws: ThreeError.self) { try reopened.carryTask(task.id, to: today.adding(days: 1)) }
        #expect(throws: ThreeError.self) { try reopened.dismissCarry(task.id) }
        #expect(try reopened.dayCloseReview(for: closeDay)?.offers.isEmpty == true)
        #expect(try reopened.dayCloseReview(for: closeDay)?.decisions.first?.copyTaskId == copy.id)
        #expect(try reopened.snapshot(for: today).tasks.count == 1)
    }

    @Test func resolvedDayClosesEarlyButFuturePlansRemainEditable() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        try store.commit(day: closeDay)
        try store.setTaskStatus(task.id, .done)
        guard case .closed(let summary) = try store.closeDay(closeDay, now: closeDay.startDate.addingTimeInterval(3600)) else {
            Issue.record("Expected resolved close"); return
        }
        #expect(summary.reason == .resolved && summary.doneCount == 1 && summary.committedDoneCount == 1)
        let future = closeDay.adding(days: 1)
        let next = try closeTask(store, day: future)
        try store.commit(day: future)
        try store.setTaskStatus(next.id, .done)
        #expect(try store.closeDay(future, now: closeDue) == .notEligible(.futureDay))
        try store.updateTask(next.id, title: "Still editable")
    }

    @Test func focusAndDeferredReflectionDelayCloseWithoutChangingTheTimer() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        let session = try store.startFocus(taskId: task.id, now: closeDue.addingTimeInterval(-600))
        #expect(try store.closeDay(closeDay, now: closeDue) == .deferred(.focus))
        #expect(try store.snapshot(for: closeDay).running == session)
        try store.pause(now: closeDue)
        #expect(try store.closeDay(closeDay, now: closeDue) == .deferred(.focus))
        let paused = try #require(try store.snapshot(for: closeDay).running)
        let prompt = ReflectionPrompt(session: paused, openedAt: closeDue)
        #expect(try store.deferReflection(prompt, now: closeDue.addingTimeInterval(120)))
        #expect(try store.closeDay(closeDay, now: closeDue.addingTimeInterval(120)) == .deferred(.reflection))
        #expect(throws: ThreeError.self) { try store.carryTask(task.id, to: closeDay.adding(days: 1)) }
        #expect(throws: ThreeError.self) { try store.dismissCarry(task.id) }
        try store.dismissDeferredReflection(session.id, now: closeDue.addingTimeInterval(180))
        guard case .closed(let summary) = try store.closeDay(closeDay, now: closeDue.addingTimeInterval(180)) else {
            Issue.record("Expected close after reflection decision"); return
        }
        #expect(summary.skippedBreakCount == nil)
    }

    @Test func recoveryPredicateRunsInsideTheCloseTransaction() throws {
        let store = try closeStore()
        try closeTask(store)
        try store.commit(day: closeDay)
        try store.db.write { db in
            try db.execute(sql: "INSERT INTO preference(key, value) VALUES('test.pendingRecovery', 'yes')")
        }
        let check: DayCloseRecoveryCheck = { db, day in
            #expect(day == closeDay)
            return try String.fetchOne(db, sql: "SELECT value FROM preference WHERE key = 'test.pendingRecovery'") == "yes"
        }
        #expect(try store.closeDay(closeDay, now: closeDue, pendingRecovery: check) == .deferred(.recovery))
        #expect(try store.dayCloseSummary(for: closeDay) == nil)
        try store.db.write { try $0.execute(sql: "UPDATE preference SET value = 'no' WHERE key = 'test.pendingRecovery'") }
        guard case .closed = try store.closeDay(closeDay, now: closeDue, pendingRecovery: check) else {
            Issue.record("Expected close after recovery decision"); return
        }
    }

    @Test func dismissalIsDurableAndPreservesTheFrozenDay() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        try store.commit(day: closeDay)
        try store.closeDay(closeDay, now: closeDue)
        let summary = try store.dayCloseSummary(for: closeDay)
        let first = try store.dismissCarry(task.id, now: closeDue)
        let reopened = try Store(url: URL(fileURLWithPath: store.db.path))
        #expect(try reopened.dismissCarry(task.id, now: closeDue.addingTimeInterval(120)) == first)
        #expect(try reopened.snapshot(for: closeDay).tasks.first?.task.status == .dropped)
        #expect(try reopened.dayCloseSummary(for: closeDay) == summary)
        #expect(try reopened.carryover(before: closeDay.adding(days: 1)).isEmpty)
        #expect(try reopened.snapshot(for: closeDay.adding(days: 1)).plan == nil)
        #expect(throws: ThreeError.self) { try reopened.carryTask(task.id, to: closeDay.adding(days: 1)) }
        #expect(try reopened.dayCloseReview(for: closeDay)?.decisions == [first])
    }

    @Test func concurrentAcceptanceOfOneClosedSourceReturnsTheSameCopy() async throws {
        let store = try closeStore()
        let peer = try Store(url: URL(fileURLWithPath: store.db.path))
        let task = try closeTask(store)
        try store.commit(day: closeDay)
        try store.closeDay(closeDay, now: closeDue)
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for writer in [store, peer] {
                group.addTask { try writer.carryTask(task.id, to: closeDay.adding(days: 1)).id }
            }
            var result: [String] = []
            for try await id in group { result.append(id) }
            return result
        }
        #expect(ids.count == 2 && Set(ids).count == 1)
        #expect(try store.snapshot(for: closeDay.adding(days: 1)).tasks.count == 1)
    }

    @Test func carryFailureRollsBackCopyStepsTagsDecisionAndSource() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        try store.addStep(to: task.id, title: "Step")
        try store.commit(day: closeDay)
        try store.closeDay(closeDay, now: closeDue)
        try store.db.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_carry BEFORE UPDATE OF status ON task WHEN NEW.status = 'carried' BEGIN SELECT RAISE(ABORT, 'simulated interrupted acceptance'); END")
        }
        #expect(throws: DatabaseError.self) { try store.carryTask(task.id, to: closeDay.adding(days: 1)) }
        #expect(try store.carryDecision(for: task.id) == nil)
        #expect(try store.snapshot(for: closeDay).tasks.first?.task.status == .todo)
        #expect(try store.snapshot(for: closeDay.adding(days: 1)).plan == nil)
        #expect(try store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM task") } == 1)
        #expect(try store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM step") } == 1)
        #expect(try store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM taskTag") } == 1)
        try store.db.write { try $0.execute(sql: "DROP TRIGGER reject_carry") }
        try store.carryTask(task.id, to: closeDay.adding(days: 1))
        #expect(try store.snapshot(for: closeDay.adding(days: 1)).tasks.count == 1)
    }

    @Test func closedSourceCarryHonorsDestinationCapAndClosedDestination() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        try store.commit(day: closeDay)
        try store.closeDay(closeDay, now: closeDue)
        let destination = closeDay.adding(days: 1)
        for index in 0..<5 { try closeTask(store, day: destination, title: "Full \(index)") }
        #expect(throws: ThreeError.tooManyTasks) { try store.carryTask(task.id, to: destination) }
        #expect(try store.carryDecision(for: task.id) == nil)
        try store.commit(day: destination)
        try store.closeDay(destination, now: closeDue.addingTimeInterval(86400))
        #expect(throws: ThreeError.self) { try store.carryTask(task.id, to: destination) }
        #expect(try store.snapshot(for: closeDay).tasks.first?.task.status == .todo)
    }

    @Test func closeRollbackLeavesTheCommittedPlanAndNoSummary() throws {
        let store = try closeStore()
        try closeTask(store)
        try store.commit(day: closeDay)
        try store.db.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_close BEFORE UPDATE OF status ON dayPlan WHEN NEW.status = 'closed' BEGIN SELECT RAISE(ABORT, 'simulated interrupted close'); END")
        }
        #expect(throws: DatabaseError.self) { try store.closeDay(closeDay, now: closeDue) }
        #expect(try store.dayCloseSummary(for: closeDay) == nil)
        #expect(try store.snapshot(for: closeDay).plan?.status == .committed)
        try store.db.write { try $0.execute(sql: "DROP TRIGGER reject_close") }
        try store.closeDay(closeDay, now: closeDue)
        #expect(try store.recentDayCloses().count == 1)
    }

    @Test func catchupIsBoundedAndCanContinuePastDeferredDays() throws {
        let store = try closeStore()
        for offset in 0..<5 {
            let day = closeDay.adding(days: offset)
            try closeTask(store, day: day)
            try store.commit(day: day)
        }
        let now = closeDue.addingTimeInterval(6 * 86400)
        let pending: DayCloseRecoveryCheck = { _, day in day == closeDay }
        let first = try store.closeEligibleDays(now: now, limit: 2, pendingRecovery: pending)
        #expect(first.attempts.count == 2 && first.attempts[0].result == .deferred(.recovery))
        #expect(first.nextAfter == closeDay.adding(days: 1))
        let second = try store.closeEligibleDays(now: now, limit: 2, after: first.nextAfter, pendingRecovery: pending)
        #expect(second.nextAfter == closeDay.adding(days: 3))
        let third = try store.closeEligibleDays(now: now, limit: 2, after: second.nextAfter, pendingRecovery: pending)
        #expect(third.attempts.count == 1 && third.nextAfter == nil)
        #expect(try store.recentDayCloses().count == 4)
        #expect(try store.closeEligibleDays(now: now, pendingRecovery: pending).attempts.count == 1)
        #expect(throws: ThreeError.self) { try store.closeEligibleDays(now: now, limit: 32) }
    }

    @Test func reviewStepsReachEveryClosedDayBeyondTheRecentWindow() throws {
        let store = try closeStore()
        let count = 40
        for offset in 0..<count {
            let day = closeDay.adding(days: offset)
            try closeTask(store, day: day)
            try store.commit(day: day)
        }
        let now = closeDue.addingTimeInterval(Double(count) * 86400)
        var batch = try store.closeEligibleDays(now: now, limit: 31)
        while let after = batch.nextAfter { batch = try store.closeEligibleDays(now: now, limit: 31, after: after) }
        let latest = closeDay.adding(days: count - 1)
        #expect(try store.recentDayCloses().count == 31)
        #expect(try store.recentDayCloses().first?.day == latest)

        var day = latest
        var visited = [day]
        while let previous = try store.closedDays(around: day).previous { day = previous; visited.append(day) }
        #expect(day == closeDay)
        #expect(visited.count == count)
        #expect(try store.closedDays(around: closeDay).previous == nil)
        while let next = try store.closedDays(around: day).next { day = next; visited.append(day) }
        #expect(day == latest)
        #expect(visited.count == 2 * count - 1)
        #expect(try store.closedDays(around: latest).next == nil)
        // A day that never closed (today) steps back to the latest close.
        #expect(try store.closedDays(around: latest.adding(days: 1)).previous == latest)
    }

    @Test func closedDayNeighboursAreEmptyWithoutClosesAndSkipGapDays() throws {
        let store = try closeStore()
        let empty = try store.closedDays(around: closeDay)
        #expect(empty.previous == nil && empty.next == nil)

        let later = closeDay.adding(days: 3)
        for day in [closeDay, later] {
            try closeTask(store, day: day)
            try store.commit(day: day)
        }
        let batch = try store.closeEligibleDays(now: later.startDate.addingTimeInterval(22 * 3600))
        #expect(batch.attempts.count == 2)
        // A gap day that never closed sits between the two closes.
        let gap = try store.closedDays(around: closeDay.adding(days: 1))
        #expect(gap.previous == closeDay && gap.next == later)
        let first = try store.closedDays(around: closeDay)
        #expect(first.previous == nil && first.next == later)
        let last = try store.closedDays(around: later)
        #expect(last.previous == closeDay && last.next == nil)
    }

    @Test func commitmentSnapshotStaysProspectiveAndStableAcrossPlanEdits() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        try store.commit(day: closeDay)
        let initial = try store.planCommitment(for: closeDay)
        try store.updateTask(task.id, blockMinutes: 60, status: .dropped)
        try closeTask(store, title: "Added after commitment")
        try store.commit(day: closeDay)
        #expect(try store.planCommitment(for: closeDay) == initial)
        #expect(initial?.plannedMinutes == 45)
        try store.closeDay(closeDay, now: closeDue)
        #expect(try store.dayCloseSummary(for: closeDay)?.plannedMinutes == 45)
        #expect(try store.dayCloseSummary(for: closeDay)?.committedDoneCount == 0)
    }

    @Test func planDayAndImplicitFocusCommitCaptureTheSameDenominator() throws {
        let store = try closeStore()
        try store.setPlan([NewTask(title: "Committed", category: "Coding", blockMinutes: 30)], day: closeDay, source: .mcp, commit: true)
        #expect(try store.planCommitment(for: closeDay)?.plannedMinutes == 30)
        let next = closeDay.adding(days: 1)
        let task = try closeTask(store, day: next)
        try store.startFocus(taskId: task.id, now: next.startDate)
        #expect(try store.planCommitment(for: next)?.plannedMinutes == 45)
    }

    @Test func closeSettingsUseSeparateValidatedPreferences() throws {
        let store = try closeStore()
        #expect(try store.dayCloseSettings().closeMinute == 1320)
        var timer = Preferences()
        timer.sessionMinutes = 25
        try store.setPreferences(timer)
        var settings = DayCloseSettings()
        settings.closeMinute = 20 * 60 + 30
        try store.setDayCloseSettings(settings)
        try closeTask(store)
        try store.commit(day: closeDay)
        let at = Calendar.current.date(bySettingHour: 20, minute: 30, second: 0, of: closeDay.startDate)!
        #expect(try store.dayCloseStatus(for: closeDay, now: at.addingTimeInterval(-1)) == .notEligible(.notDue))
        #expect(try store.dayCloseStatus(for: closeDay, now: at) == .ready(.due))
        #expect(try store.preferences() == timer)
        for value in [-1, 1440, Int.max] {
            settings.closeMinute = value
            #expect(throws: ThreeError.self) { try store.setDayCloseSettings(settings) }
        }
        #expect(try Store(url: URL(fileURLWithPath: store.db.path)).dayCloseSettings().closeMinute == 1230)
    }

    @Test func upgradeFromV10PreservesOldDataWithoutInventingCommitmentsOrBreakDecisions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("three-upgrade-close-\(UUID().uuidString)/db.sqlite")
        do {
            let old = try Store(url: url, upTo: "v10-planning-supervisor")
            try old.db.write { db in
                let category = try String.fetchOne(db, sql: "SELECT id FROM category LIMIT 1")!
                try db.execute(sql: """
                    INSERT INTO dayPlan(id, day, status, source, createdAt, committedAt, updatedAt)
                    VALUES('old-plan', ?, 'committed', 'cli', ?, ?, ?)
                    """, arguments: [closeDay, closeDay.startDate, closeDay.startDate, closeDay.startDate])
                try db.execute(sql: """
                    INSERT INTO task(id, dayPlanId, position, title, categoryId, blockMinutes, status, createdBy, updatedAt)
                    VALUES('old-task', 'old-plan', 0, 'Legacy unfinished', ?, 30, 'partial', 'cli', ?)
                    """, arguments: [category, closeDay.startDate])
                try db.execute(sql: """
                    INSERT INTO session(id, taskId, kind, plannedSeconds, startedAt, pausedSeconds, endedAt, endReason, updatedAt)
                    VALUES('old-session', 'old-task', 'focus', 1800, ?, 60, ?, 'stopped', ?)
                    """, arguments: [closeDay.startDate, closeDay.startDate.addingTimeInterval(660), closeDay.startDate.addingTimeInterval(660)])
            }
        }
        let store = try Store(url: url)
        #expect(try store.planCommitment(for: closeDay) == nil)
        try store.commit(day: closeDay)
        #expect(try store.planCommitment(for: closeDay) == nil)
        guard case .closed(let summary) = try store.closeDay(closeDay, now: closeDue) else {
            Issue.record("Expected legacy committed day to close"); return
        }
        #expect(summary.commitment == nil && summary.plannedMinutes == 30)
        #expect(summary.skippedBreakCount == nil)
        #expect(summary.focusSessions.first?.focusRating == nil)
        #expect(summary.focusedSeconds == 600)
        #expect(summary.tasks.first?.carriedFromTaskId == nil)
        let copy = try store.carryTask("old-task", to: closeDay.adding(days: 1))
        #expect(copy.carriedFromTaskId == "old-task")
        #expect(try store.snapshot(for: closeDay).sessions.map(\.id) == ["old-session"])
        #expect(try store.db.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }.isEmpty)
        #expect(try Store(url: url).dayCloseSummary(for: closeDay) == summary)
    }

    @Test func legacyClosedSourceCanBeAcceptedWithoutFabricatingACloseSummary() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        try store.db.write { try $0.execute(sql: "UPDATE dayPlan SET status = 'closed' WHERE id = ?", arguments: [task.dayPlanId]) }
        #expect(try store.dayCloseStatus(for: closeDay, now: closeDue) == .notEligible(.legacyClosed))
        #expect(try store.dayCloseSummary(for: closeDay) == nil)
        try store.carryTask(task.id, to: closeDay.adding(days: 1))
        #expect(try store.dayCloseSummary(for: closeDay) == nil)
        #expect(try store.snapshot(for: closeDay).tasks.first?.task.status == .carried)
    }

    @Test func concurrentClosePersistsOneSummaryAndOneResult() async throws {
        let store = try closeStore()
        let peer = try Store(url: URL(fileURLWithPath: store.db.path))
        try closeTask(store)
        try store.commit(day: closeDay)
        let results = try await withThrowingTaskGroup(of: DayCloseResult.self) { group in
            for writer in [store, peer] { group.addTask { try writer.closeDay(closeDay, now: closeDue) } }
            var results: [DayCloseResult] = []
            for try await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 2 && results[0] == results[1])
        #expect(try store.recentDayCloses().count == 1)
    }

    @Test func acceptAndDismissRaceHasExactlyOneDurableDecision() async throws {
        let store = try closeStore()
        let peer = try Store(url: URL(fileURLWithPath: store.db.path))
        let task = try closeTask(store)
        try store.commit(day: closeDay)
        try store.closeDay(closeDay, now: closeDue)
        let results = await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? store.carryTask(task.id, to: closeDay.adding(days: 1))) != nil }
            group.addTask { (try? peer.dismissCarry(task.id)) != nil }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(results.filter { $0 }.count == 1)
        let decision = try #require(try store.carryDecision(for: task.id))
        let copies = try store.snapshot(for: closeDay.adding(days: 1)).tasks
        #expect(copies.count == (decision.decision == .accepted ? 1 : 0))
        #expect(try store.snapshot(for: closeDay).tasks.first?.task.status == (decision.decision == .accepted ? .carried : .dropped))
    }

    @Test func localCloseTimeUsesTheWallClockOnDaylightSavingBoundaries() throws {
        let store = try closeStore()
        for day in [DayKey("2026-03-08")!, DayKey("2026-11-01")!] {
            try closeTask(store, day: day)
            try store.commit(day: day)
            let due = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: day.startDate)!
            if ProcessInfo.processInfo.environment["TZ"] == "America/New_York" {
                #expect(Calendar.current.timeZone.identifier == "America/New_York")
                #expect(due.timeIntervalSince(day.startDate) == (day.rawValue == "2026-03-08" ? 21 : 23) * 3600)
            }
            #expect(try store.dayCloseStatus(for: day, now: due.addingTimeInterval(-1)) == .notEligible(.notDue))
            #expect(try store.dayCloseStatus(for: day, now: due) == .ready(.due))
        }
    }

    @Test func explicitBreakDecisionsMatchActualContinuationAndRollBackOnConflict() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        let start = closeDay.startDate.addingTimeInterval(3600)
        let running = try store.startFocus(taskId: task.id, now: start)
        #expect(throws: ThreeError.self) {
            try store.finishFocus(outcome: .progress, rating: .okay, note: nil, markTaskDone: false,
                                  continuation: .break, breakDecision: .skipped, now: start.addingTimeInterval(60))
        }
        #expect(try store.snapshot(for: closeDay).running == running)
        #expect(throws: ThreeError.self) {
            try store.finishFocus(outcome: .progress, rating: .okay, note: nil, markTaskDone: false,
                                  breakDecision: .taken, now: start.addingTimeInterval(60))
        }
        try store.finishFocus(outcome: .progress, rating: .okay, note: nil, markTaskDone: false,
                              continuation: .break, now: start.addingTimeInterval(60))
        try store.stop(now: start.addingTimeInterval(120))
        try store.closeDay(closeDay, now: closeDue)
        #expect(try store.dayCloseSummary(for: closeDay)?.skippedBreakCount == 0)
        #expect(try store.dayCloseSummary(for: closeDay)?.breakDecisions.first?.decision == .taken)
    }

    @Test func carryPreservesArchivedTagAndDeletedCategoryReferences() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        try store.commit(day: closeDay)
        try store.closeDay(closeDay, now: closeDue)
        let originalTag = try #require(try store.snapshot(for: closeDay).tasks.first?.tags.first)
        try store.db.write { db in
            try db.execute(sql: "UPDATE category SET deletedAt = ? WHERE id = ?", arguments: [closeDue, task.categoryId])
            try db.execute(sql: "UPDATE tag SET archived = 1 WHERE id = ?", arguments: [originalTag.id])
        }
        let copy = try store.carryTask(task.id, to: closeDay.adding(days: 1))
        #expect(copy.categoryId == task.categoryId)
        let row = try #require(try store.snapshot(for: closeDay.adding(days: 1)).tasks.first)
        #expect(row.tags.first?.id == originalTag.id && row.tags.first?.archived == true)
        #expect(row.category.deletedAt == closeDue)
    }

    @Test func dismissedDecisionRollsBackWhenTheSourceCannotChange() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        try store.commit(day: closeDay)
        try store.closeDay(closeDay, now: closeDue)
        try store.db.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_dismiss BEFORE UPDATE OF status ON task WHEN NEW.status = 'dropped' BEGIN SELECT RAISE(ABORT, 'simulated interrupted dismissal'); END")
        }
        #expect(throws: DatabaseError.self) { try store.dismissCarry(task.id) }
        #expect(try store.carryDecision(for: task.id) == nil)
        #expect(try store.dayCloseReview(for: closeDay)?.offers.map(\.id) == [task.id])
        try store.db.write { try $0.execute(sql: "DROP TRIGGER reject_dismiss") }
        try store.dismissCarry(task.id)
        #expect(try store.dayCloseReview(for: closeDay)?.offers.isEmpty == true)
    }

    @Test func invalidPersistedCloseSettingsThrowWithoutClosingThePlan() throws {
        let store = try closeStore()
        try closeTask(store)
        try store.commit(day: closeDay)
        try store.db.write { db in
            try db.execute(sql: "INSERT INTO preference(key, value) VALUES('dayClose', '{\"closeMinute\":1440}')")
        }
        #expect(throws: ThreeError.self) { try store.closeDay(closeDay, now: closeDue) }
        #expect(try store.dayCloseSummary(for: closeDay) == nil)
        #expect(try store.snapshot(for: closeDay).plan?.status == .committed)
    }

    @Test func implicitTomorrowCannotRetargetAnEarlierSuccessfulAcceptance() throws {
        let store = try closeStore()
        let task = try closeTask(store)
        let destination = closeDay.adding(days: 2)
        let copy = try store.carryTask(task.id, to: destination)
        #expect(throws: ThreeError.self) { try store.pushToTomorrow(task.id) }
        #expect(try store.carryTask(task.id, to: destination).id == copy.id)
        #expect(try store.snapshot(for: closeDay.adding(days: 1)).plan == nil)
    }
}
