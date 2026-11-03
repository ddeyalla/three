import Foundation
import Testing
import ThreeCore
@testable import ThreeApp

@MainActor
struct StrictTaskActionTests {
    private func store() throws -> Store {
        try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-strict-action-\(UUID().uuidString)/db.sqlite"))
    }

    @Test func activeTaskTighteningRefreshesBlockingStateWithoutRevokingAnException() throws {
        let store = try store()
        let reader = try Store(url: URL(fileURLWithPath: store.db.path))
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let first = try store.addBlockRule(.domain(BlockDomain(parsing: "example.com")), now: now)
        let second = try store.addBlockRule(.domain(BlockDomain(parsing: "example.org")), now: now)
        let task = try store.addTask(NewTask(title: "Focus", category: "Coding", blockMinutes: 60), source: .app)
        let session = try store.startFocus(taskId: task.id, minutes: 60, now: now)
        let exception = try store.requestBlockException(ruleId: first.id, reason: "Already granted", now: now)
        let before = BlockingState(status: try reader.blockStatus(now: now), now: now)
        #expect(before.availableRule(id: second.id) == second)

        try store.setTaskStrict(task.id)
        let refreshed = BlockingState(status: try reader.blockStatus(now: now), now: now)
        #expect(try reader.snapshot().runningTask?.task.strict == true)
        #expect(try reader.snapshot().running == session)
        #expect(refreshed.policy.strict)
        #expect(refreshed.unblockOptions.isEmpty)
        #expect(refreshed.policy.exceptions == [exception])
        #expect(!refreshed.policy.blocked.contains { $0.id == first.id })
        #expect(refreshed.policy.blocked.contains { $0.id == second.id })
        for rule in [first, second] {
            #expect(throws: BlockError.strictSession) {
                try store.requestBlockException(ruleId: rule.id, reason: "New request", now: now.addingTimeInterval(1))
            }
        }
        let expired = BlockingState(status: try reader.blockStatus(now: exception.expiresAt), now: exception.expiresAt)
        #expect(expired.policy.strict)
        #expect(expired.policy.exceptions.isEmpty)
        #expect(Set(expired.policy.blocked.map(\.id)) == Set([first.id, second.id]))
        #expect(expired.unblockOptions.isEmpty)
    }

    @Test func prepareStrictTaskNativeFixture() throws {
        let store: Store
        if let path = ProcessInfo.processInfo.environment["THREE_STRICT_FIXTURE_DB"] {
            guard !FileManager.default.fileExists(atPath: path) else {
                throw ThreeError.invalid("The strict fixture requires a new database path.")
            }
            store = try Store(url: URL(fileURLWithPath: path))
        } else {
            store = try self.store()
        }
        let task = try store.addTask(NewTask(title: "406 Make this active task strict", category: "Coding", blockMinutes: 60), source: .app)
        try store.addTask(NewTask(title: "406 Already strict", category: "Coding", blockMinutes: 30, strict: true), source: .app)
        try store.addTask(NewTask(title: "406 Keep menus open", category: "Writing", blockMinutes: 30), source: .app)
        try store.addBlockRule(.domain(BlockDomain(parsing: "example.com")))
        try store.startFocus(taskId: task.id, minutes: 60)
        #expect(try store.snapshot().runningTask?.task.strict == false)
        #expect(try store.snapshot().tasks.count == 3)
        #expect(try !store.planningSettings().enabled)
    }
}
