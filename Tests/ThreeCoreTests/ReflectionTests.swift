import Foundation
import GRDB
import Testing
@testable import ThreeCore

private func reflectionStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-reflection-\(UUID()).sqlite"))
}

private func overduePrompt(in store: Store) throws -> ReflectionPrompt {
    let task = try store.addTask(NewTask(title: "Write spec", category: "Coding", blockMinutes: 60), source: .app)
    let start = DayKey.today.startDate.addingTimeInterval(9 * 3600)
    let session = try store.startFocus(taskId: task.id, minutes: 45, now: start)
    return ReflectionPrompt(session: session, openedAt: session.plannedEnd)
}

@Test func reflectionTimeoutSavesDefaultsOnceAtTwoMinutes() throws {
    let store = try reflectionStore()
    let prompt = try overduePrompt(in: store)
    #expect(try !store.deferReflection(prompt, now: prompt.deadline.addingTimeInterval(-1)))
    #expect(try store.snapshot().running?.id == prompt.session.id)
    #expect(try store.deferredReflections().isEmpty)

    #expect(try store.deferReflection(prompt, now: prompt.deadline))
    let snapshot = try store.snapshot()
    let saved = try #require(try store.deferredReflections().first)
    #expect(snapshot.running == nil)
    #expect(snapshot.sessions.count == 1)
    #expect(snapshot.tasks.first?.task.status == .partial)
    #expect(saved.session.outcome == .progress)
    #expect(saved.session.focusRating == .okay)
    #expect(saved.session.endedAt == prompt.deadline)
    #expect(saved.session.elapsed(at: prompt.deadline) == 47 * 60)
    #expect(saved.session.endReason == .completed)
    #expect(try !store.deferReflection(prompt, now: prompt.deadline.addingTimeInterval(10)))
    #expect(try store.deferredReflections().count == 1)

    let reopened = try Store(url: URL(fileURLWithPath: store.db.path))
    #expect(try reopened.deferredReflections().first?.id == saved.id)
}

@Test(arguments: ["extend", "pause", "stop", "replace"])
func changedFocusCannotBeEndedByOldReflection(change: String) throws {
    let store = try reflectionStore()
    let prompt = try overduePrompt(in: store)
    let at = prompt.openedAt.addingTimeInterval(30)
    switch change {
    case "extend": try store.extend(minutes: 15, now: at)
    case "pause": try store.pause(now: at)
    case "stop": try store.stop(now: at)
    default:
        try store.stop(now: at)
        try store.startFocus(taskId: prompt.session.taskId, now: at)
    }
    let before = try store.snapshot()
    #expect(try !store.deferReflection(prompt, now: prompt.deadline))
    #expect(try store.snapshot().running == before.running)
    #expect(try store.snapshot().sessions == before.sessions)
    #expect(try store.deferredReflections().isEmpty)
    let expectedError: ThreeError = change == "stop" ? .noRunningSession
        : .invalid("This focus block changed. Open its reflection again.")
    #expect(throws: expectedError) {
        try store.finishFocus(outcome: .done, rating: .focused, note: nil, markTaskDone: true,
                              expectedSession: prompt.session, now: prompt.deadline)
    }
    #expect(try store.snapshot().running == before.running)
    #expect(throws: expectedError) {
        try store.extend(minutes: 15, expectedSession: prompt.session, now: prompt.deadline)
    }
    #expect(try store.snapshot().running == before.running)
}

@Test func editingSavedReflectionLeavesNewerFocusAndTaskAlone() throws {
    let store = try reflectionStore()
    let prompt = try overduePrompt(in: store)
    try store.deferReflection(prompt, now: prompt.deadline)
    let next = try store.startFocus(taskId: prompt.session.taskId, now: prompt.deadline.addingTimeInterval(30))
    try store.saveDeferredReflection(prompt.session.id, outcome: .done, rating: .focused, note: "Finished the draft")
    let snapshot = try store.snapshot()
    #expect(snapshot.running == next)
    #expect(snapshot.tasks.first?.task.status == .active)
    #expect(try store.logbook().isEmpty)
    #expect(try store.deferredReflections().isEmpty)
    let saved = try #require(snapshot.sessions.first { $0.id == prompt.session.id })
    #expect(saved.endedAt == prompt.deadline)
    #expect(saved.startedAt == prompt.session.startedAt)
    #expect(saved.outcome == .done)
    #expect(saved.focusRating == .focused)
    #expect(saved.note == "Finished the draft")
    #expect(throws: ThreeError.invalid("This reflection has already been answered or dismissed.")) {
        try store.saveDeferredReflection(saved.id, outcome: .stuck, rating: .scattered, note: nil)
    }
}

@Test func automaticReflectionKeepsAnUnsubmittedNote() throws {
    let store = try reflectionStore()
    let prompt = try overduePrompt(in: store)
    try store.deferReflection(prompt, note: "Waiting for the API key", now: prompt.deadline)
    let saved = try #require(try store.deferredReflections().first)
    #expect(saved.session.note == "Waiting for the API key")
    #expect(saved.session.outcome == .progress)
    #expect(saved.session.focusRating == .okay)
}

@Test func reflectionAcceptsTheSessionReturnedByStartFocus() throws {
    let store = try reflectionStore()
    try store.addTask(NewTask(title: "Review the draft", category: "Coding", blockMinutes: 30), source: .app)
    let session = try store.startFocus(now: Date(timeIntervalSince1970: 1_793_619_000.123456))
    let prompt = ReflectionPrompt(session: session, openedAt: session.plannedEnd)
    #expect(try store.deferReflection(prompt, now: prompt.deadline))
    #expect(try store.deferredReflections().first?.id == session.id)
}

@Test func dismissingSavedReflectionKeepsDefaultsAndOtherReminders() throws {
    let store = try reflectionStore()
    let first = try overduePrompt(in: store)
    try store.deferReflection(first, now: first.deadline)
    let session = try store.startFocus(taskId: first.session.taskId, minutes: 5, now: first.deadline.addingTimeInterval(30))
    let second = ReflectionPrompt(session: session, openedAt: session.plannedEnd)
    try store.deferReflection(second, now: second.deadline)
    #expect(try store.deferredReflections().map(\.id) == [first.session.id, second.session.id])
    try store.dismissDeferredReflection(first.session.id)
    try store.dismissDeferredReflection(first.session.id)
    #expect(try store.deferredReflections().map(\.id) == [second.session.id])
    let saved = try #require(try store.snapshot().sessions.first { $0.id == first.session.id })
    #expect(saved.outcome == .progress)
    #expect(saved.focusRating == .okay)
    #expect(saved.endedAt == first.deadline)
}

@Test func reflectionMigrationKeepsExistingSessionsAnswered() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("three-v5-\(UUID()).sqlite")
    let old = try Store(url: url, upTo: "v5-tags")
    try old.db.write { db in
        try db.execute(sql: """
            INSERT INTO session(id, kind, plannedSeconds, startedAt, pausedSeconds, endedAt, endReason, outcome, focusRating, updatedAt)
            VALUES('old', 'focus', 300, datetime('now','-10 minutes'), 0, datetime('now','-5 minutes'), 'completed', 'done', 3, datetime('now'))
            """)
    }
    let migrated = try Store(url: url)
    let session = try #require(try migrated.snapshot().sessions.first { $0.id == "old" })
    #expect(!session.reflectionPending)
    #expect(session.outcome == .done)
    #expect(try migrated.deferredReflections().isEmpty)
}
