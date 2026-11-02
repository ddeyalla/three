import Foundation
import Testing
@testable import ThreeCore

private func freshStore() throws -> Store {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("three-\(UUID().uuidString).sqlite")
    return try Store(url: url)
}

/// Whole seconds: the database stores dates at millisecond precision.
private func wholeSecondNow() -> Date { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) }

private func task(_ title: String, _ minutes: Int = 60, _ category: String = "Coding") -> NewTask {
    NewTask(title: title, category: category, blockMinutes: minutes)
}

@Test func seedsFiveCategories() throws {
    let store = try freshStore()
    #expect(try store.categories().map(\.name) == ["Coding", "Writing", "Admin", "Learning", "Meeting prep"])
}

@Test func refusesSixthTask() throws {
    let store = try freshStore()
    for i in 1...5 { try store.addTask(task("T\(i)"), source: .cli) }
    #expect(throws: ThreeError.tooManyTasks) { try store.addTask(task("T6"), source: .cli) }
}

@Test func droppedTasksFreeASlot() throws {
    let store = try freshStore()
    for i in 1...5 { try store.addTask(task("T\(i)"), source: .cli) }
    let first = try store.snapshot().tasks[0]
    try store.setTaskStatus(first.id, .dropped)
    try store.addTask(task("T6"), source: .cli)
    #expect(try store.snapshot().activeTaskCount == 5)
}

@Test func unknownCategoryIsRejected() throws {
    let store = try freshStore()
    #expect(throws: ThreeError.noSuchCategory("Gaming")) { try store.addTask(task("x", 30, "Gaming"), source: .cli) }
}

@Test func timerExcludesPausedTime() throws {
    let store = try freshStore()
    try store.addTask(task("Write spec", 90), source: .cli)
    let t0 = wholeSecondNow()
    let s = try store.startFocus(now: t0)
    #expect(s.plannedSeconds == 45 * 60)
    try store.pause(now: t0.addingTimeInterval(600))
    try store.resume(now: t0.addingTimeInterval(900))
    let running = try #require(try store.snapshot().running)
    #expect(running.elapsed(at: t0.addingTimeInterval(1200)) == 900)
    #expect(running.plannedEnd == t0.addingTimeInterval(45 * 60 + 300))
}

@Test func onlyOneFocusSessionRuns() throws {
    let store = try freshStore()
    try store.addTask(task("A"), source: .cli)
    try store.startFocus()
    #expect(throws: ThreeError.alreadyRunning) { try store.startFocus() }
}

@Test func startingFocusEndsARunningBreak() throws {
    let store = try freshStore()
    try store.addTask(task("A"), source: .cli)
    try store.startBreak(minutes: 5)
    try store.startFocus()
    let snap = try store.snapshot()
    #expect(snap.running?.kind == .focus)
    #expect(snap.sessions.filter { $0.endedAt != nil }.count == 1)
}

@Test func sessionLengthFollowsBlockLeft() throws {
    let store = try freshStore()
    try store.addTask(task("Short", 25), source: .cli)
    #expect(try store.startFocus().plannedSeconds == 25 * 60)
}

@Test func extendingAnOverrunAddsFromNow() throws {
    let store = try freshStore()
    try store.addTask(task("A", 30), source: .cli)
    let t0 = wholeSecondNow()
    try store.startFocus(minutes: 30, now: t0)
    let late = t0.addingTimeInterval(35 * 60)
    try store.extend(minutes: 15, now: late)
    let running = try #require(try store.snapshot().running)
    #expect(running.remaining(at: late) == 15 * 60)
}

@Test func reflectionClosesSessionAndMarksTask() throws {
    let store = try freshStore()
    try store.addTask(task("A", 30), source: .cli)
    try store.startFocus()
    try store.finishFocus(outcome: .done, rating: .focused, note: "shipped", markTaskDone: true)
    let snap = try store.snapshot()
    #expect(snap.running == nil)
    #expect(snap.tasks[0].task.status == .done)
    #expect(snap.sessions[0].outcome == .done)
    #expect(snap.nextTask == nil)
}

@Test func longBreakAfterHundredMinutesOfFocus() throws {
    let store = try freshStore()
    try store.addTask(task("A", 240), source: .cli)
    let t0 = DayKey.today.startDate.addingTimeInterval(9 * 3600)
    try store.startFocus(minutes: 60, now: t0)
    try store.finishFocus(outcome: .progress, rating: .okay, note: nil, markTaskDone: false, now: t0.addingTimeInterval(3600))
    #expect(try store.suggestedBreakMinutes(now: t0.addingTimeInterval(3600)) == 5)
    try store.startFocus(minutes: 45, now: t0.addingTimeInterval(3700))
    try store.finishFocus(outcome: .progress, rating: .okay, note: nil, markTaskDone: false, now: t0.addingTimeInterval(3700 + 2700))
    #expect(try store.suggestedBreakMinutes(now: t0.addingTimeInterval(3700 + 2700)) == 15)
}

@Test func replanningKeepsWorkedTasks() throws {
    let store = try freshStore()
    try store.addTask(task("Worked"), source: .cli)
    try store.addTask(task("Untouched"), source: .cli)
    try store.startFocus()
    try store.stop()
    try store.setPlan([task("New one")], day: .today, source: .mcp, commit: true)
    let snap = try store.snapshot()
    #expect(snap.tasks.map(\.task.title) == ["Worked", "New one"])
    #expect(snap.plan?.status == .committed)
}

@Test func moveTaskReorders() throws {
    let store = try freshStore()
    for t in ["A", "B", "C"] { try store.addTask(task(t), source: .cli) }
    let c = try store.snapshot().tasks[2]
    try store.moveTask(c.id, to: 0)
    #expect(try store.snapshot().tasks.map(\.task.title) == ["C", "A", "B"])
}

@Test func dayKeyRoundTrips() {
    let key = DayKey("2026-11-02")!
    #expect(key.adding(days: 1).rawValue == "2026-11-03")
    #expect(DayKey("nope") == nil)
}

@Test func startingWorkCommitsADraft() throws {
    let store = try freshStore()
    try store.addTask(task("A"), source: .app)
    #expect(try store.snapshot().plan?.status == .draft)
    try store.startFocus()
    #expect(try store.snapshot().plan?.status == .committed)
}

@Test func pushToTomorrowCarriesTask() throws {
    let store = try freshStore()
    try store.addTask(task("Later", 30, "Writing"), source: .app)
    let id = try store.snapshot().tasks[0].id
    try store.pushToTomorrow(id)
    #expect(try store.snapshot().tasks[0].task.status == .carried)
    let tomorrow = try store.snapshot(for: DayKey.today.adding(days: 1))
    #expect(tomorrow.tasks.map(\.task.title) == ["Later"])
    #expect(tomorrow.tasks[0].category.name == "Writing")
}

@Test func dueBreakEndsAtItsPlannedEnd() throws {
    let store = try freshStore()
    let t0 = wholeSecondNow()
    try store.startBreak(minutes: 5, now: t0)
    try store.finishBreakIfDue(now: t0.addingTimeInterval(120))
    #expect(try store.snapshot().running != nil)
    try store.finishBreakIfDue(now: t0.addingTimeInterval(900))
    let s = try #require(try store.snapshot().sessions.first)
    #expect(s.endedAt == t0.addingTimeInterval(300))
}
