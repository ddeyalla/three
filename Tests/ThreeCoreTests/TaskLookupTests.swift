import Foundation
import Testing
@testable import ThreeCore

private func lookupStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-lookup-\(UUID().uuidString)/db.sqlite"))
}

private func work(_ title: String) -> NewTask { NewTask(title: title, category: "Coding", blockMinutes: 30) }

/// `three done <id>` and friends resolve ids through this lookup, so tasks on any day must be reachable.
@Test func tasksResolveByIdOrPrefixOnAnyDay() throws {
    let store = try lookupStore()
    let past = try store.addTask(work("Past"), day: DayKey.today.adding(days: -2), source: .cli)
    let later = try store.addTask(work("Later"), day: DayKey.today.adding(days: 3), source: .cli)
    let undated = try store.addToInbox(work("Someday"), source: .cli)
    #expect(try store.task(matching: past.id).id == past.id)
    #expect(try store.task(matching: String(past.id.prefix(8)).lowercased()).id == past.id)
    #expect(try store.task(matching: later.id).id == later.id)
    #expect(try store.task(matching: undated.id).id == undated.id)
    #expect(throws: ThreeError.noSuchTask("zz-no-such-task")) { try store.task(matching: "zz-no-such-task") }
    #expect(throws: ThreeError.self) { try store.task(matching: "") }
    try store.removeTask(undated.id)
    #expect(throws: ThreeError.self) { try store.task(matching: undated.id) }
}

/// Guard: an open (not yet closed) earlier day still accepts status changes.
@Test func openPastDayTasksCanBeMarkedDone() throws {
    let store = try lookupStore()
    let day = DayKey.today.adding(days: -1)
    let past = try store.addTask(work("Yesterday"), day: day, source: .cli)
    try store.setTaskStatus(store.task(matching: past.id).id, .done)
    #expect(try store.snapshot(for: day).tasks.first?.task.status == .done)
}

/// Closed days stay frozen on purpose; the refusal names the day and the way forward.
@Test func closedDayTasksRefuseChangesWithAWayForward() throws {
    let store = try lookupStore()
    let day = DayKey("2026-10-20")!
    let past = try store.addTask(work("Closed"), day: day, source: .cli)
    try store.commit(day: day)
    guard case .closed = try store.closeDay(day, now: day.startDate.addingTimeInterval(22 * 3600)) else {
        Issue.record("Expected the day to close"); return
    }
    do {
        try store.setTaskStatus(past.id, .done)
        Issue.record("A closed day's task should not change")
    } catch {
        let message = error.localizedDescription
        #expect(message.contains("2026-10-20"))
        #expect(message.contains("carry"))
    }
    #expect(try store.snapshot(for: day).tasks.first?.task.status == .todo)
}
