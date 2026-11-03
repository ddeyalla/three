import Foundation
import GRDB
import Testing
@testable import ThreeCore

@Test func legacyPlanDatesNormalizeWithoutLosingWork() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-day-\(UUID().uuidString)/db.sqlite")
    let day = DayKey("2026-01-01")!
    let taskId: String
    let sessionId: String
    do {
        let old = try Store(url: url, upTo: "v7-blocker")
        let task = try old.addTask(NewTask(title: "Legacy task", category: "Coding", blockMinutes: 30), day: day, source: .cli)
        taskId = task.id
        let start = day.startDate.addingTimeInterval(3600)
        sessionId = try old.startFocus(taskId: taskId, now: start).id
        try old.stop(now: start.addingTimeInterval(60))
        try old.addStep(to: taskId, title: "Keep this step")
        try old.addTag("keep", to: taskId)
        try old.db.write { try $0.execute(sql: "UPDATE dayPlan SET day = '2026-1-01'") }
    }
    let store = try Store(url: url)
    let snapshot = try store.snapshot(for: day)
    #expect(snapshot.tasks.map(\.id) == [taskId])
    #expect(snapshot.tasks[0].steps.map(\.title) == ["Keep this step"])
    #expect(snapshot.tasks[0].tags.map(\.name) == ["keep"])
    #expect(snapshot.sessions.map(\.id) == [sessionId])
    #expect(snapshot.tasks[0].focusedSeconds == 60)
    try store.updateTask(taskId, title: "Editable after upgrade")
    try store.schedule(taskId, on: .today)
    #expect(try store.snapshot().tasks.map(\.id) == [taskId])
    #expect(try store.db.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }.isEmpty)
}

@Test func canonicalDateCollisionRetainsEveryTaskAndAdmissionCap() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-collision-\(UUID().uuidString)/db.sqlite")
    let day = DayKey("2026-01-01")!
    var taskIds: [String] = []
    var canonicalPlanId: String?
    do {
        let old = try Store(url: url, upTo: "v7-blocker")
        for offset in 0...1 {
            for index in 0..<5 {
                let task = try old.addTask(NewTask(title: "Group \(offset) task \(index)", category: "Coding", blockMinutes: 30),
                                           day: day.adding(days: offset), source: .cli)
                taskIds.append(task.id)
            }
        }
        canonicalPlanId = try old.snapshot(for: day).plan?.id
        try old.commit(day: day.adding(days: 1))
        try old.db.write { try $0.execute(sql: "UPDATE dayPlan SET day = '2026-1-01' WHERE day = '2026-01-02'") }
    }
    let store = try Store(url: url)
    let snapshot = try store.snapshot(for: day)
    #expect(snapshot.plan?.id == canonicalPlanId)
    #expect(snapshot.plan?.status == .committed)
    #expect(snapshot.tasks.map(\.id) == taskIds)
    #expect(snapshot.tasks.map(\.task.position) == Array(0..<10))
    #expect(throws: ThreeError.tooManyTasks) {
        try store.addTask(NewTask(title: "No extra admission", category: "Coding", blockMinutes: 30), day: day, source: .app)
    }
    #expect(try store.db.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }.isEmpty)
    let reopened = try Store(url: url)
    #expect(try reopened.snapshot(for: day).tasks.map(\.id) == taskIds)
}

@Test func deletedLegacyPlanDoesNotResurrectDuringDateMerge() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-deleted-\(UUID().uuidString)/db.sqlite")
    let day = DayKey("2026-01-01")!
    let liveId: String
    do {
        let old = try Store(url: url, upTo: "v7-blocker")
        liveId = try old.addTask(NewTask(title: "Live work", category: "Coding", blockMinutes: 30), day: day, source: .app).id
        try old.addTask(NewTask(title: "Deleted work", category: "Coding", blockMinutes: 30), day: day.adding(days: 1), source: .app)
        try old.db.write { db in
            try db.execute(sql: "UPDATE dayPlan SET day = '2026-1-01', status = 'closed', deletedAt = CURRENT_TIMESTAMP WHERE day = '2026-01-02'")
        }
    }
    let store = try Store(url: url)
    let snapshot = try store.snapshot(for: day)
    #expect(snapshot.plan?.status == .draft)
    #expect(snapshot.tasks.map(\.id) == [liveId])
    #expect(try store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM task") } == 2)
}

@Test func olderWriterDatesRemainRecoverableAfterTheMigrationRan() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-writer-\(UUID().uuidString)/db.sqlite")
    let day = DayKey("2026-01-01")!
    let taskId: String
    do {
        let store = try Store(url: url)
        taskId = try store.addTask(NewTask(title: "Older writer", category: "Coding", blockMinutes: 30), day: day, source: .cli).id
        try store.db.write { try $0.execute(sql: "UPDATE dayPlan SET day = '2026-1-01'") }
    }
    let reopened = try Store(url: url)
    #expect(try reopened.snapshot(for: day).tasks.map(\.id) == [taskId])
    try reopened.schedule(taskId, on: .today)
    #expect(try reopened.snapshot().tasks.map(\.id) == [taskId])
}
