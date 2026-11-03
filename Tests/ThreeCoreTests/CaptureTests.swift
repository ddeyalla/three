import Foundation
import GRDB
import Testing
@testable import ThreeCore

private func freshURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("three-\(UUID().uuidString).sqlite")
}

private func task(_ title: String, _ minutes: Int = 60, _ category: String = "Coding") -> NewTask {
    NewTask(title: title, category: category, blockMinutes: minutes)
}

@Test func inboxMigrationKeepsTasksAndSessions() throws {
    let url = freshURL()
    do {
        let old = try Store(url: url, upTo: "v2-calm-colors")
        let t = try old.addLegacyTaskFixture(task("Ship it"), source: .cli)
        try old.db.write { db in
            try db.execute(sql: """
                INSERT INTO session(id, taskId, kind, plannedSeconds, startedAt, pausedSeconds, endedAt, endReason, updatedAt)
                VALUES('s1', ?, 'focus', 1500, ?, 0, ?, 'completed', ?)
                """, arguments: [t.id, Date().addingTimeInterval(-1800), Date().addingTimeInterval(-300), Date()])
        }
    }
    let store = try Store(url: url)
    let snap = try store.snapshot()
    #expect(snap.tasks.map(\.task.title) == ["Ship it"])
    #expect(snap.tasks[0].focusedSeconds == 1500)
    #expect(try store.db.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }.isEmpty)
    try store.addToInbox(task("Later"), source: .cli)
    #expect(try store.inbox().map(\.task.title) == ["Later"])
}

@Test func inboxDoesNotCountTowardTheCap() throws {
    let store = try Store(url: freshURL())
    for i in 1...5 { try store.addTask(task("T\(i)"), source: .cli) }
    let parked = try store.addToInbox(task("Parked"), source: .cli)
    #expect(try store.inbox().count == 1)
    #expect(throws: ThreeError.tooManyTasks) { try store.schedule(parked.id, on: .today) }
    try store.schedule(parked.id, on: DayKey.today.adding(days: 1))
    #expect(try store.inbox().isEmpty)
    #expect(try store.upcoming()[0].tasks.map(\.task.title) == ["Parked"])
}

@Test func scheduleBackToInbox() throws {
    let store = try Store(url: freshURL())
    let t = try store.addTask(task("Move me"), source: .cli)
    try store.schedule(t.id, on: nil)
    #expect(try store.snapshot().tasks.isEmpty)
    #expect(try store.inbox().map(\.id) == [t.id])
    #expect(throws: ThreeError.invalid("Plan it for today before starting it.")) { try store.startFocus(taskId: t.id) }
}

@Test func stepsLiveUnderTheirTask() throws {
    let store = try Store(url: freshURL())
    let t = try store.addTask(task("Write PRD"), source: .cli)
    let a = try store.addStep(to: t.id, title: "Outline")
    try store.addStep(to: t.id, title: "Draft")
    try store.setStep(a.id, done: true)
    let steps = try store.snapshot().tasks[0].steps
    #expect(steps.map(\.title) == ["Outline", "Draft"])
    #expect(steps.map(\.done) == [true, false])
}

@Test func preferencesDriveTheTimer() throws {
    let store = try Store(url: freshURL())
    var p = Preferences()
    p.sessionMinutes = 25
    try store.setPreferences(p)
    let t = try store.addTask(task("Long one", 120), source: .cli)
    #expect(try store.startFocus(taskId: t.id).plannedSeconds == 25 * 60)
    p.sessionMinutes = 1
    #expect(throws: ThreeError.invalid("That length is out of range.")) { try store.setPreferences(p) }
}

@Test func categoriesEditAndArchive() throws {
    let store = try Store(url: freshURL())
    let c = try store.addCategory(name: "Health", colorHex: "#4FBF8B")
    #expect(throws: ThreeError.invalid("There's already a category called Coding.")) {
        try store.updateCategory(c.id, name: "Coding")
    }
    try store.updateCategory(c.id, colorHex: "#000000", archived: true)
    let saved = try store.categories().first { $0.id == c.id }
    #expect(saved?.archived == true && saved?.colorHex == "#000000")
}

@Test func quickAddParsesTodoistStyle() {
    let cats = ["Coding", "Writing", "Meeting prep"]
    let today = DayKey("2026-11-02")!  // a Monday
    let q = QuickAdd.parse("Write the PRD #writ 45m tomorrow", categories: cats, today: today)
    #expect(q == QuickAdd(title: "Write the PRD", category: "Writing", minutes: 45, when: .day(DayKey("2026-11-03")!)))
    #expect(QuickAdd.parse("Agenda #meetingprep 1h30m fri", categories: cats, today: today)
        == QuickAdd(title: "Agenda", category: "Meeting prep", minutes: 90, when: .day(DayKey("2026-11-06")!)))
    #expect(QuickAdd.parse("Read 3 chapters someday", categories: cats, today: today)
        == QuickAdd(title: "Read 3 chapters", category: nil, minutes: nil, when: .inbox))
    #expect(QuickAdd.parse("Fix #bug mon", categories: cats, today: today).title == "Fix #bug")
    #expect(QuickAdd.parse("x mon", categories: cats, today: today).when == .day(DayKey("2026-11-09")!))
}

@Test func markingRunningTaskDoneEndsItsBlock() throws {
    let store = try Store(url: freshURL())
    let t = try store.addTask(task("Ship it"), source: .cli)
    try store.startFocus(taskId: t.id)
    try store.setTaskStatus(t.id, .done)
    let snap = try store.snapshot()
    #expect(snap.running == nil)
    #expect(snap.sessions.last?.outcome == .done)
    #expect(snap.tasks[0].task.status == .done)
}

@Test func repairClosesBlocksOfDoneTasksWherePaused() throws {
    let url = freshURL()
    let pausedAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 600)
    do {
        let old = try Store(url: url, upTo: "v3-inbox-steps-prefs")
        let t = try old.addLegacyTaskFixture(task("woek"), source: .cli)
        try old.db.write { db in
            try db.execute(sql: """
                INSERT INTO session(id, taskId, kind, plannedSeconds, startedAt, pausedAt, pausedSeconds, updatedAt)
                VALUES('s1', ?, 'focus', 2700, ?, ?, 0, ?)
                """, arguments: [t.id, pausedAt.addingTimeInterval(-60), pausedAt, Date()])
            try db.execute(sql: "UPDATE task SET status = 'done'")
        }
    }
    let store = try Store(url: url)
    let snap = try store.snapshot(for: DayKey(pausedAt.addingTimeInterval(-60)))
    #expect(snap.running == nil)
    #expect(snap.sessions.first?.endedAt == pausedAt)
    #expect(snap.sessions.first.map { Int($0.elapsed(at: Date())) } == 60)
}

@Test func quickAddReadsDaysAndDurationsOnlyAtTheEnd() {
    let cats = ["Coding", "Admin"]
    let today = DayKey("2026-11-02")!
    #expect(QuickAdd.parse("Email Tom about invoice", categories: cats, today: today)
        == QuickAdd(title: "Email Tom about invoice", category: nil, minutes: nil, when: nil))
    #expect(QuickAdd.parse("SAT prep", categories: cats, today: today).title == "SAT prep")
    #expect(QuickAdd.parse("Read later", categories: cats, today: today).when == nil)
    #expect(QuickAdd.parse("Plan today's talk tomorrow", categories: cats, today: today)
        == QuickAdd(title: "Plan today's talk", category: nil, minutes: nil, when: .day(DayKey("2026-11-03")!)))
    #expect(QuickAdd.parse("#admin Call bank 15m", categories: cats, today: today)
        == QuickAdd(title: "Call bank", category: "Admin", minutes: 15, when: nil))
    #expect(QuickAdd.parse("tomorrow 30m", categories: cats, today: today).title.isEmpty)
}

@Test func openTasksFromEarlierDaysWaitInTheInbox() throws {
    let store = try Store(url: freshURL())
    let yesterday = DayKey.today.adding(days: -1)
    let left = try store.addTask(task("Left over"), day: yesterday, source: .cli)
    let done = try store.addTask(task("Finished"), day: yesterday, source: .cli)
    try store.setTaskStatus(done.id, .done)
    #expect(try store.inbox().map(\.id) == [left.id])
    try store.schedule(left.id, on: .today)
    #expect(try store.inbox().isEmpty)
    #expect(try store.snapshot().tasks.map(\.id) == [left.id])
}

@Test func deletingTheRunningTaskStopsItsBlock() throws {
    let store = try Store(url: freshURL())
    let t = try store.addTask(task("Oops"), source: .cli)
    try store.startFocus(taskId: t.id)
    try store.removeTask(t.id)
    let snap = try store.snapshot()
    #expect(snap.running == nil)
    #expect(snap.tasks.first { $0.id == t.id }?.task.status == .dropped)
}

@Test func pushToTomorrowCopiesSteps() throws {
    let store = try Store(url: freshURL())
    let t = try store.addTask(task("Big one"), source: .cli)
    let first = try store.addStep(to: t.id, title: "First")
    try store.addStep(to: t.id, title: "Second")
    try store.setStep(first.id, done: true)
    try store.pushToTomorrow(t.id)
    let copy = try store.snapshot(for: DayKey.today.adding(days: 1)).tasks[0]
    #expect(copy.steps.map(\.title) == ["First", "Second"])
    #expect(copy.steps.map(\.done) == [true, false])
    #expect(try store.snapshot().tasks[0].steps.count == 2)
    #expect(throws: ThreeError.self) { try store.schedule(t.id, on: DayKey.today.adding(days: 2)) }
}

@Test func moveSkipsHiddenDroppedTasks() throws {
    let store = try Store(url: freshURL())
    let b = try store.addTask(task("B"), source: .cli)
    let a = try store.addTask(task("A"), source: .cli)
    try store.addTask(task("C"), source: .cli)
    try store.startFocus(taskId: a.id)
    try store.stop()
    try store.removeTask(a.id)  // worked on, so it's dropped and hidden
    try store.moveTask(b.id, to: 1)
    let visible = try store.snapshot().tasks.filter { $0.task.status != .dropped }
    #expect(visible.map(\.task.title) == ["C", "B"])
}
