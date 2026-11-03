import Foundation
import GRDB
import Testing
@testable import ThreeCore

private func planningStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-guards-\(UUID().uuidString)/db.sqlite"))
}

private func proposed(_ title: String) -> NewTask {
    NewTask(title: title, category: "Coding", blockMinutes: 30)
}

@Test func draftReplacementRefusesCommittedWorkWithoutMutation() throws {
    let store = try planningStore()
    let task = try store.addTask(proposed("Keep me"), source: .app)
    try store.commit()
    let before = try store.snapshot()
    #expect(throws: ThreeError.self) {
        try store.setPlan([proposed("Replacement")], day: .today, source: .mcp, commit: false)
    }
    let after = try store.snapshot()
    #expect(after.plan == before.plan)
    #expect(after.tasks == before.tasks)
    #expect(after.tasks.first?.id == task.id)
}

@Test func closedDayCannotBeReopenedOrEdited() throws {
    let store = try planningStore()
    let task = try store.addTask(proposed("Closed work"), source: .app)
    try store.db.write { try $0.execute(sql: "UPDATE dayPlan SET status = 'closed'") }
    let before = try store.snapshot()
    #expect(throws: ThreeError.self) { try store.commit() }
    for commit in [false, true] {
        #expect(throws: ThreeError.self) { try store.setPlan([proposed("New")], day: .today, source: .mcp, commit: commit) }
    }
    #expect(throws: ThreeError.self) { try store.startFocus(taskId: task.id) }
    #expect(throws: ThreeError.self) { try store.setTaskStatus(task.id, .todo) }
    #expect(throws: ThreeError.self) { try store.schedule(task.id, on: nil) }
    #expect(throws: ThreeError.self) { try store.addTask(proposed("Extra"), source: .cli) }
    let after = try store.snapshot()
    #expect(after.plan == before.plan)
    #expect(after.tasks == before.tasks)
    #expect(after.running == nil)
}

@Test func invalidDraftRollsBackReplacement() throws {
    let store = try planningStore()
    try store.addTask(proposed("Original"), source: .app)
    let before = try store.snapshot()
    #expect(throws: ThreeError.self) {
        try store.setPlan([proposed("Valid"), proposed(" \n")], day: .today, source: .mcp, commit: false)
    }
    #expect(try store.snapshot().tasks == before.tasks)
    #expect(try store.snapshot().plan == before.plan)
}

@Test func updatesCannotBypassTitlesDeletionOrCap() throws {
    let store = try planningStore()
    let dropped = try store.addTask(proposed("Dropped"), source: .cli)
    try store.setTaskStatus(dropped.id, .dropped)
    for index in 1...5 { try store.addTask(proposed("Task \(index)"), source: .app) }
    #expect(throws: ThreeError.tooManyTasks) { try store.setTaskStatus(dropped.id, .todo) }
    #expect(throws: ThreeError.tooManyTasks) { try store.setTaskStatus(dropped.id, .done) }
    let task = try #require(try store.snapshot().tasks.last)
    #expect(throws: ThreeError.self) { try store.updateTask(task.id, title: " \n ") }
    #expect(throws: ThreeError.self) { try store.setTaskStatus(task.id, .active) }
    try store.removeTask(task.id)
    #expect(throws: ThreeError.noSuchTask(task.id)) { try store.updateTask(task.id, title: "Resurrected", status: .todo) }
    #expect(throws: ThreeError.noSuchTask(task.id)) { try store.moveTask(task.id, to: 0) }
}

@Test func carriedTaskCannotBeReopened() throws {
    let store = try planningStore()
    let task = try store.addTask(proposed("Carry"), source: .app)
    try store.pushToTomorrow(task.id)
    #expect(throws: ThreeError.self) { try store.setTaskStatus(task.id, .todo) }
    #expect(try store.snapshot().tasks.first?.task.status == .carried)
    #expect(try store.snapshot(for: DayKey.today.adding(days: 1)).tasks.count == 1)
}

@Test func datesValidateAtConstructionAndDecoding() throws {
    for raw in ["2026-02-30", "2026-13-01", "2026-00-10", "2026-1-01", "2026-01-01junk", "", "0000-01-01"] {
        #expect(DayKey(raw) == nil)
        let data = try JSONEncoder().encode(raw)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DayKey.self, from: data) }
    }
    #expect(DayKey("2024-02-29")?.rawValue == "2024-02-29")
    #expect(DayKey("2026-02-29") == nil)
}

@Test func removingWorkedCarriedTaskCannotReopenTheOriginal() throws {
    let store = try planningStore()
    let original = try store.addTask(proposed("Carry after work"), source: .app)
    try store.startFocus(taskId: original.id)
    try store.stop()
    let copy = try store.pushToTomorrow(original.id)
    #expect(throws: ThreeError.self) { try store.removeTask(original.id) }
    #expect(throws: ThreeError.self) { try store.setTaskStatus(original.id, .todo) }
    #expect(try store.snapshot().tasks.first?.task.status == .carried)
    #expect(try store.snapshot(for: DayKey.today.adding(days: 1)).tasks.map(\.id) == [copy.id])
}

@Test func closedOrDeletedTasksRejectStepAndTagWrites() throws {
    let store = try planningStore()
    let task = try store.addTask(proposed("Protected work"), source: .app)
    let step = try store.addStep(to: task.id, title: "Keep this step")
    try store.addTag("keep", to: task.id)
    let before = try store.snapshot().tasks[0]
    for state in ["closed", "deleted"] {
        try store.db.write { db in
            if state == "closed" {
                try db.execute(sql: "UPDATE dayPlan SET status = 'closed'")
            } else {
                try db.execute(sql: "UPDATE dayPlan SET status = 'draft'")
                try db.execute(sql: "UPDATE task SET deletedAt = CURRENT_TIMESTAMP WHERE id = ?", arguments: [task.id])
            }
        }
        #expect(throws: ThreeError.self) { try store.addStep(to: task.id, title: "New") }
        #expect(throws: ThreeError.self) { try store.setStep(step.id, done: true) }
        #expect(throws: ThreeError.self) { try store.setStep(step.id, title: "Changed") }
        #expect(throws: ThreeError.self) { try store.removeStep(step.id) }
        #expect(throws: ThreeError.self) { try store.addTag("new", to: task.id) }
        #expect(throws: ThreeError.self) { try store.removeTag(before.tags[0].id, from: task.id) }
        #expect(try store.db.read { try Step.fetchAll($0) } == before.steps)
        #expect(try store.db.read { try Tag.fetchAll($0) } == before.tags)
    }
}
