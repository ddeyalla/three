import Foundation
import GRDB
import Testing
@testable import ThreeCore

private func historyStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-history-\(UUID().uuidString)/db.sqlite"))
}

private func historyCalendar(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func historyDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}

private func historyTask(_ title: String = "Ship history", minutes: Int = 30) -> NewTask {
    NewTask(title: title, category: "Coding", blockMinutes: minutes, linearRef: "https://linear.app/brunoh-ai/issue/BPRO-402",
            notes: "Keep the source", tags: ["Three"])
}

@Test func historyReportCountsPausedWorkAndBreaksSeparately() throws {
    let store = try historyStore()
    let day = DayKey("2026-11-03")!
    let task = try store.addTask(historyTask(), day: day, source: .cli)
    try store.addStep(to: task.id, title: "Verify")
    let start = historyDate("2026-11-03T09:00:00Z")
    let focus = try store.startFocus(taskId: task.id, minutes: 30, now: start)
    try store.pause(now: start.addingTimeInterval(600))
    try store.resume(now: start.addingTimeInterval(900))
    try store.finishFocus(outcome: .done, rating: .focused, note: "Shipped", markTaskDone: true,
                          now: start.addingTimeInterval(2100))
    let rest = try store.startBreak(minutes: 5, now: start.addingTimeInterval(2100))
    try store.stop(now: start.addingTimeInterval(2400))
    let report = try store.historyReport(from: day, through: day, now: start.addingTimeInterval(3600), calendar: historyCalendar())
    let detail = try #require(report.days.first)
    #expect(report.totals.focusSeconds == 1800)
    #expect(report.totals.breakSeconds == 300)
    #expect(report.totals.plannedSeconds == 1800)
    #expect(report.totals.plannedTaskCount == 1)
    #expect(report.totals.doneTaskCount == 1)
    #expect(report.totals.focusSessionCount == 1)
    #expect(report.totals.breakSessionCount == 1)
    #expect(detail.sessions.map(\.id) == [focus.id, rest.id])
    #expect(detail.sessions.first?.session.note == "Shipped")
    #expect(detail.sessions.first?.session.focusRating == .focused)
    #expect(detail.sessions.first?.session.outcome == .done)
    #expect(detail.tasks.first?.focusSeconds == 1800)
    #expect(detail.tasks.first?.steps.map(\.title) == ["Verify"])
    #expect(detail.tasks.first?.tags.map(\.name) == ["Three"])
    #expect(detail.categories.map(\.focusSeconds) == [1800])
    #expect(report.plannedMetrics == .derivedFromCurrentTaskRows)
    #expect(report.dateAttribution == .sessionStartDayInReportTimeZone)
}

@Test func historyReportFreezesPausedAndRunningSessionsAtItsReadTime() throws {
    let store = try historyStore()
    let day = DayKey("2026-11-03")!
    let task = try store.addTask(historyTask(), day: day, source: .cli)
    let start = historyDate("2026-11-03T09:00:00Z")
    try store.startFocus(taskId: task.id, now: start)
    try store.pause(now: start.addingTimeInterval(600))
    let paused = try store.historyReport(from: day, through: day, now: start.addingTimeInterval(900), calendar: historyCalendar())
    #expect(paused.totals.focusSeconds == 600)
    #expect(paused.days.first?.sessions.first?.session.isPaused == true)
    try store.resume(now: start.addingTimeInterval(1200))
    let running = try store.historyReport(from: day, through: day, now: start.addingTimeInterval(1800), calendar: historyCalendar())
    #expect(running.totals.focusSeconds == 1200)
    #expect(paused.totals.focusSeconds == 600)
    #expect(running.takenAt == start.addingTimeInterval(1800))
}

@Test func historyReportAttributesCrossMidnightWorkToItsLocalStartDay() throws {
    let store = try historyStore()
    let first = DayKey("2026-10-31")!, last = DayKey("2026-11-01")!
    let task = try store.addTask(historyTask(), day: first, source: .app)
    let start = historyDate("2026-10-31T23:50:00Z")
    try store.startFocus(taskId: task.id, now: start)
    try store.pause(now: start.addingTimeInterval(300))
    try store.resume(now: start.addingTimeInterval(900))
    try store.stop(now: start.addingTimeInterval(1800))
    let report = try store.historyReport(from: first, through: last, calendar: historyCalendar())
    #expect(report.days.map(\.totals.focusSeconds) == [1200, 0])
    #expect(report.months.map(\.month) == ["2026-10", "2026-11"])
    #expect(report.months.map(\.totals.focusSeconds) == [1200, 0])
    #expect(report.days.last?.sessions.isEmpty == true)
}

@Test(arguments: [
    ("2026-03-08", "2026-03-08T09:30:00Z", "2026-03-08T10:30:00Z", 23),
    ("2026-11-01", "2026-11-01T08:30:00Z", "2026-11-01T09:30:00Z", 25),
])
func historyReportUsesCalendarDaysAcrossDST(dayString: String, startString: String, endString: String, hours: Int) throws {
    let store = try historyStore()
    let day = DayKey(dayString)!
    let calendar = historyCalendar("America/Los_Angeles")
    let task = try store.addTask(historyTask(), day: day, source: .app)
    try store.startFocus(taskId: task.id, now: historyDate(startString))
    try store.stop(now: historyDate(endString))
    let range = try HistoryRange(from: day, through: day, calendar: calendar)
    #expect(range.end.timeIntervalSince(range.start) == Double(hours * 3600))
    let report = try store.historyReport(from: day, through: day, calendar: calendar)
    #expect(report.days.map(\.day) == [day])
    #expect(report.totals.focusSeconds == 3600)
    #expect(report.days.first?.sessions.count == 1)
}

@Test func historyReportReattributesSessionsWhenTheLocalTimeZoneChanges() throws {
    let store = try historyStore()
    let first = DayKey("2026-11-02")!, last = DayKey("2026-11-03")!
    let task = try store.addTask(historyTask(), day: last, source: .app)
    let start = historyDate("2026-11-03T00:30:00Z")
    try store.startFocus(taskId: task.id, now: start)
    try store.stop(now: start.addingTimeInterval(1800))
    let utc = try store.historyReport(from: first, through: last, calendar: historyCalendar())
    let pacific = try store.historyReport(from: first, through: last, calendar: historyCalendar("America/Los_Angeles"))
    #expect(utc.days.map(\.totals.focusSeconds) == [0, 1800])
    #expect(pacific.days.map(\.totals.focusSeconds) == [1800, 0])
    #expect(pacific.days.map(\.totals.plannedSeconds) == [0, 1800])
    #expect(pacific.days.first?.tasks.first?.plannedDay == last)
    #expect(pacific.timeZoneIdentifier == "America/Los_Angeles")
    #expect(pacific.totals.focusSeconds == utc.totals.focusSeconds)
}

@Test(arguments: [
    ("America/Sao_Paulo", "2018-11-04", "2018-11-05", 2),
    ("Pacific/Apia", "2011-12-29", "2011-12-31", 3),
    ("Pacific/Apia", "2011-12-30", "2011-12-30", 1),
])
func historyReportRetainsCivilDatesWhenTheTimeZoneMovesMidnight(zone: String, first: String, last: String, count: Int) throws {
    let store = try historyStore()
    let report = try store.historyReport(from: DayKey(first)!, through: DayKey(last)!, calendar: historyCalendar(zone))
    #expect(report.days.count == count)
    #expect(report.days.first?.day.rawValue == first)
    #expect(report.days.last?.day.rawValue == last)
    if first == "2011-12-30" {
        let range = try HistoryRange(from: DayKey(first)!, through: DayKey(last)!, calendar: historyCalendar(zone))
        #expect(range.start == range.end)
        let start = historyDate("2011-12-30T12:00:00Z")
        try store.db.write { db in
            try Session(id: "next-local-day", taskId: nil, kind: .focus, plannedSeconds: 1800,
                        startedAt: start, pausedAt: nil, pausedSeconds: 0, endedAt: start.addingTimeInterval(600),
                        endReason: .stopped, outcome: nil, focusRating: nil, note: nil, updatedAt: start).insert(db)
        }
        let skipped = try store.historyReport(from: DayKey(first)!, through: DayKey(last)!, calendar: historyCalendar(zone))
        let next = try store.historyReport(from: DayKey("2011-12-31")!, through: DayKey("2011-12-31")!, calendar: historyCalendar(zone))
        #expect(skipped.totals.focusSeconds == 0)
        #expect(next.totals.focusSeconds == 600)
    }
}

@Test func historyReportKeepsCarryCopiesSeparateAndLabelsMutablePlansDerived() throws {
    let store = try historyStore()
    let first = DayKey("2026-11-02")!, last = DayKey("2026-11-03")!
    let task = try store.addTask(historyTask(), day: first, source: .app)
    let start = historyDate("2026-11-02T09:00:00Z")
    try store.startFocus(taskId: task.id, now: start)
    try store.stop(now: start.addingTimeInterval(600))
    let copy = try store.carryTask(task.id, to: last)
    let dropped = try store.addTask(historyTask("Dropped"), day: last, source: .app)
    try store.setTaskStatus(dropped.id, .dropped)
    try store.startFocus(taskId: copy.id, now: start.addingTimeInterval(86400))
    try store.stop(now: start.addingTimeInterval(86400 + 1200))
    let report = try store.historyReport(from: first, through: last, calendar: historyCalendar())
    #expect(report.days.map(\.totals.focusSeconds) == [600, 1200])
    #expect(report.days.map(\.totals.plannedSeconds) == [0, 1800])
    #expect(report.totals.plannedTaskCount == 1)
    #expect(report.days.first?.tasks.first?.task.status == .carried)
    #expect(report.days.first?.sessions.first?.task?.id == task.id)
    #expect(report.days.last?.sessions.first?.task?.id == copy.id)
    #expect(report.days.last?.tasks.first?.task.notes == "Keep the source")
}

@Test func historyReportRetainsDeletedTasksPlansAndArchivedCategoriesAndTags() throws {
    let store = try historyStore()
    let day = DayKey("2026-11-03")!
    let task = try store.addTask(historyTask(), day: day, source: .app)
    let start = historyDate("2026-11-03T09:00:00Z")
    try store.startFocus(taskId: task.id, now: start)
    try store.stop(now: start.addingTimeInterval(600))
    try store.removeTask(task.id)
    #expect(try store.snapshot(for: day).tasks.first?.task.status == .dropped)
    try store.db.write { db in
        try db.execute(sql: "UPDATE task SET deletedAt = ? WHERE id = ?", arguments: [start, task.id])
        try db.execute(sql: "UPDATE category SET archived = 1, deletedAt = ? WHERE id = ?", arguments: [start, task.categoryId])
        try db.execute(sql: "UPDATE tag SET archived = 1")
        try db.execute(sql: "UPDATE dayPlan SET deletedAt = ? WHERE id = ?", arguments: [start, task.dayPlanId])
    }
    let report = try store.historyReport(from: day, through: day, calendar: historyCalendar())
    #expect(report.totals.focusSeconds == 600)
    #expect(report.totals.plannedSeconds == 0)
    #expect(report.days.first?.plan?.deletedAt != nil)
    #expect(report.days.first?.tasks.first?.task.deletedAt != nil)
    #expect(report.days.first?.sessions.first?.category?.archived == true)
    #expect(report.days.first?.tasks.first?.tags.first?.archived == true)
    #expect(report.days.first?.categories.first?.category?.deletedAt == start)
}

@Test func historyReportKeepsUnattachedSessionsWithoutInventingPlannedTasks() throws {
    let store = try historyStore()
    let day = DayKey("2026-11-03")!
    let task = try store.addToInbox(historyTask(), source: .app)
    let start = historyDate("2026-11-03T09:00:00Z")
    try store.db.write { db in
        for (id, taskId) in [("unattached", nil), ("inbox", Optional(task.id))] {
            try Session(id: id, taskId: taskId, kind: .focus, plannedSeconds: 1800,
                        startedAt: start, pausedAt: nil, pausedSeconds: 0, endedAt: start.addingTimeInterval(600),
                        endReason: .stopped, outcome: nil, focusRating: nil, note: nil, updatedAt: start).insert(db)
        }
    }
    let report = try store.historyReport(from: day, through: day, calendar: historyCalendar())
    #expect(report.totals.focusSeconds == 1200)
    #expect(report.totals.plannedTaskCount == 0)
    #expect(report.totals.plannedSeconds == 0)
    #expect(report.days.first?.sessions.map(\.id) == ["inbox", "unattached"])
    #expect(report.days.first?.sessions.last?.task == nil)
    #expect(report.days.first?.categories.reduce(0) { $0 + $1.focusSeconds } == 1200)
}

@Test func historyReportKeepsSessionsWhenLegacyReferencesAreMissing() throws {
    let store = try historyStore()
    let day = DayKey("2026-11-03")!
    let task = try store.addTask(historyTask(), day: day, source: .app)
    let start = historyDate("2026-11-03T09:00:00Z")
    let session = try store.startFocus(taskId: task.id, now: start)
    try store.stop(now: start.addingTimeInterval(600))
    var configuration = Configuration()
    configuration.foreignKeysEnabled = false
    let legacy = try DatabaseQueue(path: store.db.path, configuration: configuration)
    try legacy.write { db in
        try db.execute(sql: "DELETE FROM category WHERE id = ?", arguments: [task.categoryId])
    }
    let missingCategory = try store.historyReport(from: day, through: day, calendar: historyCalendar())
    #expect(missingCategory.totals.focusSeconds == 600)
    #expect(missingCategory.days.first?.tasks.first?.task.id == task.id)
    #expect(missingCategory.days.first?.tasks.first?.category == nil)
    #expect(missingCategory.days.first?.categories.first?.categoryId == task.categoryId)
    try legacy.write { db in
        try db.execute(sql: "DELETE FROM task WHERE id = ?", arguments: [task.id])
    }
    let missingTask = try store.historyReport(from: day, through: day, calendar: historyCalendar())
    #expect(missingTask.totals.focusSeconds == 600)
    #expect(missingTask.days.first?.sessions.first?.id == session.id)
    #expect(missingTask.days.first?.sessions.first?.session.taskId == task.id)
    #expect(missingTask.days.first?.sessions.first?.task == nil)
    #expect(missingTask.days.first?.categories.first?.focusSeconds == 600)
}

@Test func historyReportIncludesEmptyDaysAndValidatesTheInclusiveRange() throws {
    let store = try historyStore()
    let first = DayKey("2026-01-01")!, last = DayKey("2027-01-01")!
    let report = try store.historyReport(from: first, through: last, calendar: historyCalendar())
    #expect(report.days.count == 366)
    #expect(report.months.count == 13)
    #expect(report.days.first?.day == first)
    #expect(report.days.last?.day == last)
    #expect(report.days.allSatisfy { $0.tasks.isEmpty && $0.sessions.isEmpty && $0.totals == HistoryTotals() })
    #expect(throws: ThreeError.self) { try store.historyReport(from: last, through: first) }
    #expect(throws: ThreeError.self) { try store.historyReport(from: first, through: DayKey("2027-01-02")!) }
    #expect(throws: ThreeError.self) { try store.history(from: first, through: DayKey("2027-01-02")!) }
}

@Test func historyReportTotalsMatchSessionDayMonthCategoryAndLegacyReadsDeterministically() throws {
    let store = try historyStore()
    let first = DayKey("2026-10-31")!, last = DayKey("2026-11-02")!
    let task = try store.addTask(historyTask(), day: first, source: .app)
    let other = try store.addTask(NewTask(title: "Write", category: "Writing", blockMinutes: 45), day: last, source: .mcp)
    let start = first.startDate.addingTimeInterval(3600)
    for (id, offset, seconds) in [(task.id, 0, 1500), (task.id, 86400, 1200), (other.id, 172800, 2100)] {
        try store.startFocus(taskId: id, now: start.addingTimeInterval(Double(offset)))
        try store.stop(now: start.addingTimeInterval(Double(offset + seconds)))
    }
    try store.startBreak(minutes: 5, now: start.addingTimeInterval(172800 + 2100))
    try store.stop(now: start.addingTimeInterval(172800 + 2400))
    let now = start.addingTimeInterval(200000)
    let report = try store.historyReport(from: first, through: last, now: now)
    let repeated = try store.historyReport(from: first, through: last, now: now)
    #expect(report == repeated)
    #expect(report.totals.focusSeconds == 4800)
    #expect(report.totals.focusSeconds == report.days.reduce(0) { $0 + $1.totals.focusSeconds })
    #expect(report.totals.focusSeconds == report.months.reduce(0) { $0 + $1.totals.focusSeconds })
    #expect(report.totals.focusSeconds == report.days.flatMap(\.categories).reduce(0) { $0 + $1.focusSeconds })
    #expect(report.totals.focusSeconds == report.days.flatMap(\.tasks).reduce(0) { $0 + $1.focusSeconds })
    #expect(report.totals.focusSeconds == (try store.history(from: first, through: last)).filter { $0.kind == .focus }.reduce(0) { $0 + $1.elapsed(at: now) })
    #expect(report.days.flatMap(\.sessions).map(\.session) == (try store.history(from: first, through: last)))
    let encoded = try JSONEncoder().encode(report)
    #expect(try JSONDecoder().decode(HistoryReport.self, from: encoded) == report)
}
