import Foundation
import Testing
@testable import ThreeCore

private func reviewStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-review-\(UUID()).sqlite"))
}

@Test func carryingARunningTaskLeavesItsPlanAndTimerIntact() throws {
    let store = try reviewStore()
    let task = try store.addTask(NewTask(title: "Draft", category: "Writing", blockMinutes: 30), source: .app)
    try store.startFocus(taskId: task.id)
    let before = try store.snapshot()
    #expect(throws: ThreeError.self) { try store.pushToTomorrow(task.id) }
    let after = try store.snapshot()
    #expect(after.tasks.map(\.task) == before.tasks.map(\.task))
    #expect(after.sessions == before.sessions)
    #expect(after.running == before.running)
    #expect(try store.snapshot(for: .today.adding(days: 1)).tasks.isEmpty)
}

@Test func carryingATaskTwiceCannotDuplicateIt() throws {
    let store = try reviewStore()
    let task = try store.addTask(NewTask(title: "Draft", category: "Writing", blockMinutes: 30), source: .app)
    let copy = try store.pushToTomorrow(task.id)
    #expect(throws: ThreeError.self) { try store.pushToTomorrow(task.id) }
    #expect(try store.snapshot(for: .today.adding(days: 1)).tasks.map(\.id) == [copy.id])
}

@Test(arguments: [TaskStatus.done, .dropped, .carried])
func closedTasksCannotStartOrBeCarried(status: TaskStatus) throws {
    let store = try reviewStore()
    let task = try store.addTask(NewTask(title: "Draft", category: "Writing", blockMinutes: 30), source: .app)
    try store.setTaskStatus(task.id, status)
    #expect(throws: ThreeError.self) { try store.startFocus(taskId: task.id) }
    #expect(try store.snapshot().running == nil)
    #expect(throws: ThreeError.self) { try store.pushToTomorrow(task.id) }
    #expect(try store.snapshot().tasks.first?.task.status == status)
}

@Test func reflectionContinuationFailureKeepsTheOriginalBlock() throws {
    let store = try reviewStore()
    let task = try store.addTask(NewTask(title: "Draft", category: "Writing", blockMinutes: 30), source: .app)
    try store.startFocus(taskId: task.id)
    let before = try store.snapshot()
    #expect(throws: ThreeError.self) {
        try store.finishFocus(outcome: .done, rating: .focused, note: "Keep this", markTaskDone: true,
                              expectedSession: before.running, continuation: .task("removed-next-task"))
    }
    let after = try store.snapshot()
    #expect(after.running == before.running)
    #expect(after.tasks.map(\.task) == before.tasks.map(\.task))
    #expect(after.sessions == before.sessions)
    #expect(try store.logbook().isEmpty)
}

@Test func timerDurationsAreValidatedBeforeMutation() throws {
    let store = try reviewStore()
    try store.addTask(NewTask(title: "Draft", category: "Writing", blockMinutes: 30), source: .app)
    try store.startFocus()
    let before = try store.snapshot().running
    for minutes in [0, -5, 481, Int.max] {
        #expect(throws: ThreeError.self) { try store.extend(minutes: minutes) }
        #expect(try store.snapshot().running == before)
    }
    try store.stop()
    for minutes in [0, -5, 121, Int.max] {
        #expect(throws: ThreeError.self) { try store.startBreak(minutes: minutes) }
        #expect(try store.snapshot().running == nil)
    }
}

@Test(arguments: ["1e309h", "nanh", "infh", "1e300h", "153722867280912930h", "1h9223372036854775807m", "1h30mm"])
func malformedDurationsCannotCrashTheParser(value: String) {
    #expect(QuickAdd.parseMinutes(value) == nil)
    #expect(!QuickAdd.parse("Read \(value)", categories: []).title.isEmpty)
}

@Test(arguments: [false, true])
func reflectionAndContinuationShareOneBoundary(takeBreak: Bool) throws {
    let store = try reviewStore()
    let first = try store.addTask(NewTask(title: "First", category: "Writing", blockMinutes: 30), source: .app)
    let next = try store.addTask(NewTask(title: "Next", category: "Coding", blockMinutes: 30), source: .app)
    let at = DayKey.today.startDate.addingTimeInterval(9 * 3600)
    let session = try store.startFocus(taskId: first.id, now: at)
    let finish = at.addingTimeInterval(30 * 60)
    try store.finishFocus(outcome: .done, rating: .focused, note: "Finished", markTaskDone: true,
                          expectedSession: session, continuation: takeBreak ? .break : .task(next.id), now: finish)
    let snapshot = try store.snapshot()
    #expect(snapshot.running?.kind == (takeBreak ? .break : .focus))
    #expect(snapshot.running?.taskId == (takeBreak ? nil : next.id))
    #expect(snapshot.running?.startedAt == finish)
    let ended = try #require(snapshot.sessions.first { $0.id == session.id })
    #expect(ended.endedAt == finish)
    #expect(ended.note == "Finished")
    #expect(snapshot.tasks.first { $0.id == first.id }?.task.status == .done)
    #expect(throws: ThreeError.self) {
        try store.finishFocus(outcome: .stuck, rating: .scattered, note: nil, markTaskDone: false,
                              expectedSession: session, continuation: .break, now: finish)
    }
    #expect(try store.snapshot().running == snapshot.running)
}
