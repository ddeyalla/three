import Foundation
import GRDB
import Testing
@testable import ThreeCore

struct StrictTaskTests {
    private func store() throws -> Store {
        try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-strict-\(UUID().uuidString)/db.sqlite"))
    }

    @Test func tighteningAnActiveTaskPersistsAcrossConnectionsAndIsIdempotent() throws {
        let store = try store()
        let reader = try Store(url: URL(fileURLWithPath: store.db.path))
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        try store.addBlockRule(.domain(BlockDomain(parsing: "example.com")), now: now)
        let task = try store.addTask(NewTask(title: "Focus", category: "Coding", blockMinutes: 60), source: .app)
        let session = try store.startFocus(taskId: task.id, now: now)
        let before = try reader.snapshot()
        #expect(before.runningTask?.task.strict == false)
        #expect(try !reader.blockPolicy().strict)

        try store.setTaskStrict(task.id)
        let after = try reader.snapshot()
        let strict = try #require(after.runningTask?.task)
        #expect(strict.strict)
        #expect(try reader.blockPolicy().strict)
        #expect(after.running == session)
        #expect(after.sessions == before.sessions)
        #expect(strict.status == .active)
        #expect(strict.title == task.title)
        #expect(strict.dayPlanId == task.dayPlanId)
        try store.setTaskStrict(task.id)
        #expect(try reader.snapshot().runningTask?.task == strict)

        let reopened = try Store(url: URL(fileURLWithPath: store.db.path))
        #expect(try reopened.snapshot().runningTask?.task == strict)
        try reopened.stop()
        #expect(try !reader.blockPolicy().strict)
        #expect(try reader.snapshot().tasks.first?.task.strict == true)
    }

    @Test(arguments: [false, true])
    func closedAndDeletedPlansRejectTighteningEvenWhenAlreadyStrict(strict: Bool) throws {
        for state in ["closed", "deleted-plan"] {
            let store = try store()
            let task = try store.addTask(NewTask(title: "Protected", category: "Coding", blockMinutes: 30, strict: strict), source: .app)
            try store.db.write { db in
                if state == "closed" {
                    try db.execute(sql: "UPDATE dayPlan SET status = 'closed'")
                } else {
                    try db.execute(sql: "UPDATE dayPlan SET deletedAt = CURRENT_TIMESTAMP")
                }
            }
            let before = try store.db.read { try FocusTask.fetchOne($0, key: task.id) }
            #expect(throws: ThreeError.self) { try store.setTaskStrict(task.id) }
            #expect(try store.db.read { try FocusTask.fetchOne($0, key: task.id) } == before)
        }
    }

    @Test func deletedAndUnknownTasksCannotBeTightenedOrResurrected() throws {
        let store = try store()
        let task = try store.addTask(NewTask(title: "Deleted", category: "Coding", blockMinutes: 30), source: .app)
        try store.removeTask(task.id)
        let deleted = try store.db.read { try FocusTask.fetchOne($0, key: task.id) }
        #expect(throws: ThreeError.noSuchTask(task.id)) { try store.setTaskStrict(task.id) }
        #expect(throws: ThreeError.noSuchTask("missing")) { try store.setTaskStrict("missing") }
        #expect(try store.db.read { try FocusTask.fetchOne($0, key: task.id) } == deleted)
        #expect(try store.snapshot().tasks.isEmpty)
    }
}
