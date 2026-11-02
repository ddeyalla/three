import Foundation
import GRDB
import Testing
@testable import ThreeCore

private func freshURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("three-\(UUID().uuidString).sqlite")
}

private func task(_ title: String, tags: [String] = []) -> NewTask {
    NewTask(title: title, category: "Coding", blockMinutes: 90, tags: tags)
}

/// A finished focus block of `minutes` on `taskId`, ending now.
private func work(_ store: Store, _ taskId: String, minutes: Int, now: Date = Date()) throws {
    let start = now.addingTimeInterval(-Double(minutes * 60))
    try store.startFocus(taskId: taskId, minutes: minutes, now: start)
    try store.finishFocus(outcome: .progress, rating: .okay, note: nil, markTaskDone: false, now: now)
}

@Test func quickAddReadsTagsAnywhere() {
    let a = QuickAdd.parse("Ship it 90m @three", categories: ["Coding"])
    #expect(a.title == "Ship it")
    #expect(a.minutes == 90)
    #expect(a.tags == ["three"])

    let b = QuickAdd.parse("Email tom@example.com about @launch copy #coding", categories: ["Coding"])
    #expect(b.title == "Email tom@example.com about copy")
    #expect(b.tags == ["launch"])
    #expect(b.category == "Coding")

    let c = QuickAdd.parse("@onboarding Fix login @Onboarding @auth tomorrow", categories: [])
    #expect(c.title == "Fix login")
    #expect(c.tags == ["onboarding", "auth"])
    #expect(c.when != nil)

    #expect(QuickAdd.parse("Reply to @", categories: []).title == "Reply to @")
}

@Test func tagTimeFollowsATaskAcrossDays() throws {
    let store = try Store(url: freshURL())
    let first = try store.addTask(task("Build onboarding", tags: ["Onboarding"]), source: .cli)
    try work(store, first.id, minutes: 25)
    let carried = try store.pushToTomorrow(first.id)
    try store.schedule(carried.id, on: .today)
    try work(store, carried.id, minutes: 30)
    let other = try store.addTask(task("Write release notes", tags: ["onboarding", "launch"]), source: .cli)
    try work(store, other.id, minutes: 10)

    let summaries = try store.tagSummaries()
    let onboarding = try #require(summaries.first { $0.tag.name == "Onboarding" })
    #expect(onboarding.seconds == 65 * 60)
    #expect(onboarding.recentSeconds == 65 * 60)
    // The carried copy folds into one line with the original.
    #expect(onboarding.work.map(\.title).sorted() == ["Build onboarding", "Write release notes"])
    let build = try #require(onboarding.work.first(where: { $0.title == "Build onboarding" }))
    #expect(build.seconds == 55 * 60)
    let launch = try #require(summaries.first(where: { $0.tag.name == "launch" }))
    #expect(launch.seconds == 10 * 60)
    #expect(try store.snapshot().tasks.first { $0.id == carried.id }?.tags.map(\.name) == ["Onboarding"])
}

@Test func tagNamesIgnoreCaseAndArchivingKeepsTime() throws {
    let store = try Store(url: freshURL())
    let t = try store.addTask(task("Polish settings"), source: .cli)
    try store.addTag("Settings", to: t.id)
    try store.addTag("@settings", to: t.id)
    #expect(try store.tags().map(\.name) == ["Settings"])
    try work(store, t.id, minutes: 15)

    let id = try store.tags()[0].id
    try store.updateTag(id, archived: true)
    #expect(try store.tagSummaries().isEmpty)
    #expect(try store.tagSummaries(includeArchived: true).first?.seconds == 15 * 60)
    // Using an archived tag again brings it back.
    try store.addToInbox(task("Settings search", tags: ["settings"]), source: .cli)
    #expect(try store.tags().map(\.name) == ["Settings"])

    try store.removeTag(id, from: t.id)
    #expect(try store.snapshot().tasks.first?.tags.isEmpty == true)
}

@Test func tagsMigrationKeepsAnOldDatabase() throws {
    let url = freshURL()
    do {
        let old = try Store(url: url, upTo: "v4-close-orphaned-sessions")
        try old.addTask(NewTask(title: "Old task", category: "Coding", blockMinutes: 60), source: .cli)
    }
    let store = try Store(url: url)
    let row = try #require(try store.snapshot().tasks.first)
    #expect(row.task.title == "Old task")
    #expect(row.tags.isEmpty)
    try store.setTags(row.id, ["Legacy", "Cleanup"])
    #expect(try store.snapshot().tasks.first?.tags.map(\.name) == ["Cleanup", "Legacy"])
    #expect(try store.db.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }.isEmpty)
}

@Test func logbookListsFinishedTasksNewestFirst() throws {
    let store = try Store(url: freshURL())
    let a = try store.addTask(task("Done today", tags: ["x"]), source: .cli)
    let b = try store.addTask(task("Still open"), source: .cli)
    try store.setTaskStatus(a.id, .done)
    let log = try store.logbook()
    #expect(log.map(\.day) == [DayKey.today])
    #expect(log[0].tasks.map(\.task.title) == ["Done today"])
    #expect(log[0].tasks[0].tags.map(\.name) == ["x"])
    #expect(!log.flatMap(\.tasks).contains { $0.id == b.id })
}

@Test func doneTasksStayOnTheDayTheyWereFinished() throws {
    let store = try Store(url: freshURL())
    let t = try store.addTask(task("Finished on Friday"), source: .cli)
    try store.setTaskStatus(t.id, .done)
    let friday = DayKey.today.adding(days: -3)
    try store.db.write { try $0.execute(sql: "UPDATE task SET doneAt = ? WHERE id = ?", arguments: [friday.startDate.addingTimeInterval(3600), t.id]) }
    try store.updateTask(t.id, notes: "Shipped behind a flag")
    try store.setTaskStatus(t.id, .done)
    #expect(try store.logbook().map(\.day) == [friday])
    try store.setTaskStatus(t.id, .todo)
    #expect(try store.logbook().isEmpty)
}
