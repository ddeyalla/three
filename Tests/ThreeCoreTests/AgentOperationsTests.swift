import Foundation
import Testing
@testable import ThreeCore

private func agentStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-agent-\(UUID().uuidString)/db.sqlite"))
}
private func agentTask(_ title: String) -> NewTask { NewTask(title: title, category: "Coding", blockMinutes: 30) }

@Test func carryoverReadsEarlierOpenPlansWithoutMovingTasks() throws {
    let store = try agentStore()
    let day = DayKey("2026-11-03")!
    let oldest = try store.addTask(agentTask("Oldest"), day: day.adding(days: -2), source: .app)
    let yesterday = try store.addTask(agentTask("Yesterday"), day: day.adding(days: -1), source: .cli)
    let done = try store.addTask(agentTask("Done"), day: day.adding(days: -1), source: .app)
    try store.setTaskStatus(done.id, .done)
    try store.addTask(agentTask("Today"), day: day, source: .app)
    try store.addToInbox(agentTask("Undated"), source: .cli)
    let first = try store.carryover(before: day)
    #expect(first.map(\.id) == [oldest.id, yesterday.id])
    #expect(try store.carryover(before: day) == first)
    #expect(try store.snapshot(for: day.adding(days: -2)).tasks.first?.task.status == .todo)
}

@Test func historyIncludesEndDateAndPersistedReflections() throws {
    let store = try agentStore()
    let day = DayKey("2026-11-03")!
    let task = try store.addTask(agentTask("Work"), day: day, source: .cli)
    let start = day.startDate.addingTimeInterval(3600)
    let session = try store.startFocus(taskId: task.id, minutes: 30, now: start)
    try store.finishFocus(outcome: .progress, rating: .focused, note: "Shipped a slice", markTaskDone: false,
                          now: start.addingTimeInterval(1800))
    let history = try store.history(from: day, through: day)
    #expect(history.map(\.id) == [session.id])
    #expect(history.first?.note == "Shipped a slice")
    #expect(history.first?.focusRating == .focused)
    #expect(try store.history(from: day.adding(days: 1), through: day.adding(days: 1)).isEmpty)
    #expect(throws: ThreeError.self) { try store.history(from: day, through: day.adding(days: -1)) }
    #expect(throws: ThreeError.self) { try store.history(from: day.adding(days: -366), through: day) }
}

@Test func strictnessOnlyTightensAndUpdatesTheSharedBlockPolicy() throws {
    let store = try agentStore()
    let task = try store.addTask(agentTask("Focus"), source: .mcp)
    try store.addBlockRule(.domain(BlockDomain(parsing: "example.com")))
    try store.startFocus(taskId: task.id)
    #expect(try !store.blockPolicy().strict)
    try store.setTaskStrict(task.id)
    let strict = try store.snapshot().tasks.first?.task
    #expect(strict?.strict == true)
    #expect(try store.blockPolicy().strict)
    try store.setTaskStrict(task.id)
    #expect(try store.snapshot().tasks.first?.task == strict)
    try store.stop()
    let untouched = try store.addTask(agentTask("Remove"), source: .cli)
    try store.removeTask(untouched.id)
    #expect(throws: ThreeError.noSuchTask(untouched.id)) { try store.setTaskStrict(untouched.id) }
}
