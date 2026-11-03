import Foundation
import Testing
@testable import ThreeCore

// The CLI resolves every task argument through `Store.resolveTask`, so these tests cover
// `three done|drop|remove|tomorrow|start|schedule <ref>` without a ThreeCLI test target.

private func lookupStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-lookup-\(UUID().uuidString)/db.sqlite"))
}

private func work(_ title: String) -> NewTask { NewTask(title: title, category: "Coding", blockMinutes: 30) }

/// Gives a fresh task a chosen id so prefix collisions are deterministic.
private func rekey(_ store: Store, _ task: FocusTask, to id: String) throws -> String {
    try store.db.write { try $0.execute(sql: "UPDATE task SET id = ? WHERE id = ?", arguments: [id, task.id]) }
    return id
}

private let today = DayKey("2026-11-03")!

@Test func tasksResolveByIdOrPrefixOnAnyDay() throws {
    let store = try lookupStore()
    let past = try store.addTask(work("Past"), day: today.adding(days: -2), source: .cli)
    let later = try store.addTask(work("Later"), day: today.adding(days: 3), source: .cli)
    let undated = try store.addToInbox(work("Someday"), source: .cli)
    #expect(try store.resolveTask(past.id, today: today).id == past.id)
    #expect(try store.resolveTask(String(past.id.prefix(8)).lowercased(), today: today).id == past.id)
    #expect(try store.resolveTask(later.id, today: today).id == later.id)
    #expect(try store.resolveTask(undated.id, today: today).id == undated.id)
    #expect(throws: ThreeError.noSuchTask("zz-no-such-task")) { try store.resolveTask("zz-no-such-task", today: today) }
    #expect(throws: ThreeError.self) { try store.resolveTask("", today: today) }
    try store.removeTask(undated.id)
    #expect(throws: ThreeError.self) { try store.resolveTask(undated.id, today: today) }
}

/// Positions come first: "1" is today's first task and "i1" the inbox's, even when another
/// task's id starts with those characters.
@Test func positionsResolveBeforeIdPrefixes() throws {
    let store = try lookupStore()
    let first = try store.addTask(work("First"), day: today, source: .cli)
    let second = try store.addTask(work("Second"), day: today, source: .cli)
    let inboxed = try store.addToInbox(work("Inboxed"), source: .cli)
    _ = try rekey(store, try store.addTask(work("Decoy"), day: today.adding(days: -1), source: .cli),
                  to: "1AAAAAAA-0000-0000-0000-000000000000")
    #expect(try store.resolveTask("1", today: today).id == first.id)
    #expect(try store.resolveTask("2", today: today).id == second.id)
    #expect(try store.resolveTask("i1", today: today).id == inboxed.id)
    #expect(try store.resolveTask("I1", today: today).id == inboxed.id)
}

/// A short out-of-range number is a position, never an id prefix on another day; a longer
/// all-digit ref is an id prefix.
@Test func shortNumbersNeverFallThroughToIdPrefixes() throws {
    let store = try lookupStore()
    try store.addTask(work("Only"), day: today, source: .cli)
    let decoy = try rekey(store, try store.addTask(work("Decoy"), day: today.adding(days: -1), source: .cli),
                          to: "40000000-0000-0000-0000-000000000000")
    let digits = try rekey(store, try store.addTask(work("Digits"), day: today.adding(days: -2), source: .cli),
                           to: "12345678-0000-0000-0000-000000000000")
    #expect(throws: ThreeError.noSuchTask("4")) { try store.resolveTask("4", today: today) }
    #expect(throws: ThreeError.noSuchTask("400")) { try store.resolveTask("400", today: today) }
    #expect(throws: ThreeError.noSuchTask("i4")) { try store.resolveTask("i4", today: today) }
    #expect(try store.resolveTask("4000", today: today).id == decoy)
    #expect(try store.resolveTask("12345678", today: today).id == digits)
}

/// A prefix that is unique among today's tasks but shared with a task on another day is refused,
/// so `three drop 3f` can't delete the wrong one. Full ids always resolve.
@Test func prefixesSharedAcrossDaysAreRefused() throws {
    let store = try lookupStore()
    let visible = try rekey(store, try store.addTask(work("Today"), day: today, source: .cli),
                            to: "3F000000-0000-0000-0000-000000000000")
    let hidden = try rekey(store, try store.addTask(work("Last week"), day: today.adding(days: -7), source: .cli),
                           to: "3F111111-0000-0000-0000-000000000000")
    #expect(throws: ThreeError.invalid("\"3f\" matches more than one task. Use more of the id.")) {
        try store.resolveTask("3f", today: today)
    }
    #expect(try store.resolveTask("3f0", today: today).id == visible)
    #expect(try store.resolveTask(visible.lowercased(), today: today).id == visible)
    #expect(try store.resolveTask(hidden, today: today).id == hidden)
    // A deleted task no longer competes for the prefix.
    try store.removeTask(hidden)
    #expect(try store.resolveTask("3f", today: today).id == visible)
}

/// Guard: an open (not yet closed) earlier day still accepts `three done`.
@Test func openPastDayTasksCanBeMarkedDone() throws {
    let store = try lookupStore()
    let day = DayKey.today.adding(days: -1)
    let past = try store.addTask(work("Yesterday"), day: day, source: .cli)
    try store.setTaskStatus(store.resolveTask(past.id, requireOpen: true).id, .done)
    #expect(try store.snapshot(for: day).tasks.first?.task.status == .done)
}

/// `three done` on a closed day: resolution succeeds, the closed-day rule refuses with a way forward.
@Test func closedDayTasksRefuseChangesWithAWayForward() throws {
    let store = try lookupStore()
    let day = DayKey("2026-10-20")!
    let past = try store.addTask(work("Closed"), day: day, source: .cli)
    try store.commit(day: day)
    guard case .closed = try store.closeDay(day, now: day.startDate.addingTimeInterval(22 * 3600)) else {
        Issue.record("Expected the day to close"); return
    }
    let row = try store.resolveTask(past.id, requireOpen: true)
    do {
        try store.setTaskStatus(row.id, .done)
        Issue.record("A closed day's task should not change")
    } catch {
        let message = error.localizedDescription
        #expect(message.contains("2026-10-20"))
        #expect(message.contains("carry"))
    }
    #expect(try store.snapshot(for: day).tasks.first?.task.status == .todo)
}

/// `three done` never flips dropped or carried work; it says where the work went instead.
@Test func doneRefusesDroppedAndCarriedTasksWithAWayForward() throws {
    let store = try lookupStore()
    let day = DayKey.today.adding(days: -1)
    let dropped = try store.addTask(work("Dropped"), day: day, source: .cli)
    try store.setTaskStatus(dropped.id, .dropped)
    let carried = try store.addTask(work("Carried"), day: day, source: .cli)
    let copy = try store.carryTask(carried.id, to: .today)
    #expect(throws: ThreeError.invalid("\"Dropped\" was dropped. Schedule it on a day to reopen it first.")) {
        try store.resolveTask(dropped.id, requireOpen: true)
    }
    #expect(throws: ThreeError.invalid("\"Carried\" moved to \(DayKey.today). Use its copy there: \(copy.id).")) {
        try store.resolveTask(carried.id, requireOpen: true)
    }
    #expect(try store.resolveTask(dropped.id).id == dropped.id)
    #expect(try store.snapshot(for: day).tasks.first { $0.id == dropped.id }?.task.status == .dropped)
}

/// `three tomorrow` on an earlier day's task lands on today + 1, not on a day that already passed.
@Test func tomorrowFromAnEarlierDayLandsAfterToday() throws {
    let store = try lookupStore()
    let past = try store.addTask(work("Old"), day: today.adding(days: -3), source: .cli)
    let current = try store.addTask(work("Now"), day: today, source: .cli)
    let future = try store.addTask(work("Later"), day: today.adding(days: 4), source: .cli)
    let tomorrow = today.adding(days: 1)
    let pastCopy = try store.carryForward(past.id, today: today)
    let currentCopy = try store.carryForward(current.id, today: today)
    let futureCopy = try store.carryForward(future.id, today: today)
    let tomorrowIds = try store.snapshot(for: tomorrow).tasks.map(\.id)
    #expect(tomorrowIds.contains(pastCopy.id))
    #expect(tomorrowIds.contains(currentCopy.id))
    #expect(try store.snapshot(for: today.adding(days: 5)).tasks.map(\.id) == [futureCopy.id])
    #expect(try store.snapshot(for: today.adding(days: -3)).tasks.first?.task.status == .carried)
    #expect(try store.carryForward(past.id, today: today).id == pastCopy.id)
}
