import Foundation
import Testing
@testable import ThreeCore

private func carryStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-carry-\(UUID().uuidString)/db.sqlite"))
}

private func carryWork(_ title: String) -> NewTask {
    NewTask(title: title, category: "Coding", blockMinutes: 45, strict: true,
            linearRef: "https://linear.app/brunoh-ai/issue/BPRO-398/review", notes: "Keep the issue context", tags: ["launch"])
}

@Test func acceptingOlderWorkPreservesDetailsAndHistory() throws {
    let store = try carryStore()
    let oldDay = DayKey.today.adding(days: -3)
    let original = try store.addTask(carryWork("Older unfinished work"), day: oldDay, source: .mcp)
    let checked = try store.addStep(to: original.id, title: "Investigate")
    try store.setStep(checked.id, done: true)
    try store.addStep(to: original.id, title: "Ship")
    let start = oldDay.startDate.addingTimeInterval(3600)
    try store.startFocus(taskId: original.id, now: start)
    try store.finishFocus(outcome: .progress, rating: .okay, note: "Context", markTaskDone: false,
                          now: start.addingTimeInterval(600))
    let before = try #require(try store.snapshot(for: oldDay).tasks.first)
    #expect(try store.carryover(before: .today).map(\.id) == [original.id])
    let copy = try store.carryTask(original.id, to: .today)
    let accepted = try #require(try store.snapshot().tasks.first)
    #expect(accepted.id == copy.id)
    #expect(copy.id != original.id)
    #expect(copy.title == original.title)
    #expect(copy.strict == original.strict)
    #expect(copy.linearRef == original.linearRef)
    #expect(copy.notes == original.notes)
    #expect(copy.createdBy == .mcp)
    #expect(copy.scheduledStart == nil)
    #expect(accepted.tags == before.tags)
    #expect(accepted.steps.map(\.title) == before.steps.map(\.title))
    #expect(accepted.steps.map(\.done) == [true, false])
    #expect(Set(accepted.steps.map(\.id)).isDisjoint(with: before.steps.map(\.id)))
    #expect(accepted.focusedSeconds == 0)
    #expect(try store.snapshot(for: oldDay).tasks.first?.focusedSeconds == 600)
    #expect(try store.snapshot(for: oldDay).tasks.first?.task.status == .carried)
    #expect(try store.snapshot().plan?.status == .draft)
    #expect(try store.carryover(before: .today).isEmpty)
    #expect(throws: ThreeError.self) { try store.carryTask(original.id, to: .today) }
    #expect(try store.snapshot().tasks.count == 1)
}

@Test func carryGuardsRollBackBothDays() throws {
    let store = try carryStore()
    let oldDay = DayKey.today.adding(days: -2)
    let task = try store.addTask(carryWork("Keep me"), day: oldDay, source: .app)
    for index in 0..<5 { try store.addTask(carryWork("Today \(index)"), source: .app) }
    let before = try store.snapshot(for: oldDay)
    let today = try store.snapshot()
    #expect(throws: ThreeError.tooManyTasks) { try store.carryTask(task.id, to: .today) }
    #expect(try store.snapshot().tasks == today.tasks)
    #expect(try store.snapshot(for: oldDay).tasks == before.tasks)
    for day in [oldDay, oldDay.adding(days: -1)] {
        #expect(throws: ThreeError.self) { try store.carryTask(task.id, to: day) }
    }
    let start = oldDay.startDate.addingTimeInterval(3600)
    try store.startFocus(taskId: task.id, now: start)
    let freeDay = DayKey.today.adding(days: 1)
    #expect(throws: ThreeError.self) { try store.carryTask(task.id, to: freeDay) }
    #expect(try store.snapshot(for: freeDay).plan == nil)
    #expect(try store.snapshot().running?.taskId == task.id)
    try store.stop(now: start.addingTimeInterval(60))
    try store.db.write { try $0.execute(sql: "UPDATE dayPlan SET status = 'closed' WHERE day = ?", arguments: [DayKey.today]) }
    #expect(throws: ThreeError.self) { try store.carryTask(task.id, to: .today) }
    try store.db.write { try $0.execute(sql: "UPDATE dayPlan SET status = 'closed' WHERE day = ?", arguments: [oldDay]) }
    #expect(throws: ThreeError.self) { try store.carryTask(task.id, to: freeDay) }
    #expect(try store.snapshot(for: freeDay).plan == nil)
    #expect(try store.snapshot(for: oldDay).tasks.first?.task.status == .partial)
}

@Test func dismissingCarryoverLeavesItOnItsOriginalDay() throws {
    let store = try carryStore()
    let day = DayKey.today.adding(days: -2)
    let task = try store.addTask(carryWork("Dismiss"), day: day, source: .mcp)
    try store.addStep(to: task.id, title: "Keep the step")
    try store.setTaskStatus(task.id, .dropped)
    #expect(try store.carryover(before: .today).isEmpty)
    #expect(try store.snapshot().plan == nil)
    let dismissed = try #require(try store.snapshot(for: day).tasks.first)
    #expect(dismissed.task.dayPlanId == task.dayPlanId)
    #expect(dismissed.task.status == .dropped)
    #expect(dismissed.steps.first?.title == "Keep the step")
    #expect(dismissed.tags.first?.name == "launch")
}

@Test func concurrentCarryAcceptanceKeepsTheFiveTaskCap() async throws {
    let store = try carryStore()
    let peer = try Store(url: URL(fileURLWithPath: store.db.path))
    let oldDay = DayKey.today.adding(days: -2)
    let first = try store.addTask(carryWork("First"), day: oldDay, source: .app)
    let second = try store.addTask(carryWork("Second"), day: oldDay, source: .app)
    for index in 0..<4 { try store.addTask(carryWork("Today \(index)"), source: .app) }
    let outcomes = await withTaskGroup(of: Bool.self) { group in
        for (writer, id) in [(store, first.id), (peer, second.id)] {
            group.addTask { (try? writer.carryTask(id, to: .today)) != nil }
        }
        var results: [Bool] = []
        for await result in group { results.append(result) }
        return results
    }
    #expect(outcomes.filter { $0 }.count == 1)
    #expect(try store.snapshot().activeTaskCount == 5)
    #expect(try store.carryover(before: .today).count == 1)
}
