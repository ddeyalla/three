import Foundation
import GRDB
import Testing
@testable import ThreeCore

@Suite struct RecoveryReportTests {
    private let day = DayKey("2026-11-02")!
    private var start: Date { day.startDate.addingTimeInterval(9 * 3600) }

    private func instant(_ seconds: TimeInterval) -> RecoveryInstant {
        RecoveryInstant(date: start.addingTimeInterval(seconds), continuousSeconds: seconds + 10000, clockID: "report-fixture")
    }

    @Test(arguments: [false, true])
    func recoveryChangesOnlyActualsAcrossHistoryAndStats(trim: Bool) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("three-recovery-report-\(UUID().uuidString)/db.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try Store(url: url)
        let task = try store.addTask(NewTask(title: "Recovery reports", category: "Coding", blockMinutes: 45,
                                             tags: ["Three", "Client"]), day: day, source: .cli)
        let session = try store.startFocus(taskId: task.id, now: start)
        try store.pause(now: instant(300).date)
        try store.resume(now: instant(600).date)
        try store.observeRecovery(.began(.lock), at: instant(900))
        try store.observeRecovery(.began(.lock), at: instant(910))
        try store.observeRecovery(.began(.sleep), at: instant(1000))
        try store.observeRecovery(.ended(.sleep), at: instant(1700))
        let review = try #require(try store.observeRecovery(.ended(.lock), at: instant(1800)).reviews.first)
        let encoded = try JSONEncoder().encode(try store.recoveryStatus())
        let decoded = try JSONDecoder().decode(RecoveryStatus.self, from: encoded)
        #expect(decoded.reviews.first?.gap == review.gap)
        #expect(decoded.reviews.first?.sessions.first?.session.id == session.id)
        #expect(decoded.reviews.first?.sessions.first?.eligibleSeconds == 900)
        try store.observeRecovery(.ended(.lock), at: instant(1800))
        #expect(review.eligibleSeconds == 900)
        try store.finishFocus(outcome: .progress, rating: .focused, note: "Keep reflection", markTaskDone: false,
                              breakDecision: .skipped, now: instant(1800).date)
        let newer = try store.startBreak(minutes: 5, now: instant(1900).date)
        let rule = try store.addBlockRule(.domain(BlockDomain(parsing: "example.com")))
        try store.db.write { db in
            for action in ["blocked", "blocked", "unblocked"] {
                try db.execute(sql: "INSERT INTO blockEvent(id, at, ruleId, sessionId, action) VALUES(?, ?, ?, ?, ?)",
                               arguments: [UUID().uuidString, instant(100).date, rule.id, session.id, action])
            }
        }
        let now = instant(2000).date
        let before = try store.stats(from: day.adding(days: -6), through: day, now: now)
        #expect(before.metrics.focusSeconds == 1500)
        #expect(before.days.last?.sevenDayAverageMinutes == 25.0 / 7)
        #expect(before.metrics.actualToPlanned.numerator == 1500)
        #expect(before.metrics.blocks.hitsPerFocusHour.denominator == 1500.0 / 3600)
        #expect(try store.closeDay(day, now: instant(14 * 3600).date) == .deferred(.recovery))
        let reopened = try Store(url: url)
        #expect(try reopened.recoveryStatus().reviews.first?.id == review.id)
        let choice: RecoveryDecision = trim ? .trim : .keep
        let decided = try reopened.decideRecovery(review.id, decision: choice, now: now)
        #expect(try store.decideRecovery(review.id, decision: choice) == decided)
        #expect(try store.decideRecovery(review.id, decision: trim ? .keep : .trim) == decided)
        #expect(try Store(url: url).decideRecovery(review.id, decision: .keep) == decided)
        let expected = trim ? 600.0 : 1500.0
        let history = try store.historyReport(from: day.adding(days: -6), through: day, now: now)
        let after = try store.stats(from: history.from, through: day, now: now)
        #expect(history.totals.focusSeconds == expected)
        #expect(history.days.last?.tasks.first?.focusSeconds == expected)
        #expect(history.months.last?.totals.focusSeconds == expected)
        #expect(after.metrics.focusSeconds == expected)
        #expect(after.days.last?.sevenDayAverageMinutes == (trim ? 10.0 / 7 : 25.0 / 7))
        #expect(after.metrics.actualToPlanned.numerator == expected)
        #expect(after.metrics.actualToPlanned.denominator == 2700)
        #expect(after.metrics.completion == before.metrics.completion)
        #expect(after.metrics.committedPlannedTaskCount == 1)
        #expect(after.metrics.committedPlannedSeconds == 2700)
        #expect(after.metrics.derivedPlannedSeconds == 2700)
        #expect(after.metrics.quality == before.metrics.quality)
        #expect(after.metrics.quality.focusedShare.value == 1)
        #expect(after.metrics.breaks == before.metrics.breaks)
        #expect(after.metrics.blocks.associatedHits == 2)
        #expect(after.metrics.blocks.associatedUnblocks == 1)
        #expect(after.metrics.blocks.hitsPerFocusHour.numerator == 2)
        #expect(after.metrics.blocks.hitsPerFocusHour.denominator == expected / 3600)
        #expect(after.metrics.blocks.hitsPerFocusHour.value == (trim ? 12 : 4.8))
        #expect(after.tags.count == 2)
        for tag in after.tags {
            #expect(tag.metrics.focusSeconds == expected)
            #expect(tag.metrics.actualToPlanned.denominator == 2700)
            #expect(tag.metrics.blocks.associatedHits == 2)
        }
        let saved = try #require(history.days.last?.sessions.first { $0.id == session.id }?.session)
        #expect(saved.id == session.id && saved.endedAt == instant(1800).date)
        #expect(saved.outcome == .progress && saved.focusRating == .focused && saved.note == "Keep reflection")
        #expect(saved.recoveryTrimSeconds == (trim ? 900 : 0))
        #expect(try store.snapshot(for: day).running == newer)
        #expect(try store.recoveryStatus().reviews.isEmpty)
    }

    @Test func pauseOverlapAndDuplicateObservationsReachReportsOnce() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("three-recovery-overlap-\(UUID().uuidString)/db.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try Store(url: url)
        let task = try store.addTask(NewTask(title: "Paused absence", category: "Coding", blockMinutes: 30), day: day, source: .cli)
        try store.startFocus(taskId: task.id, now: start)
        try store.observeRecovery(.began(.sleep), at: instant(100))
        try store.observeRecovery(.began(.sleep), at: instant(200))
        try store.pause(now: instant(300).date)
        try store.resume(now: instant(800).date)
        let review = try #require(try store.observeRecovery(.ended(.sleep), at: instant(1100)).reviews.first)
        #expect(review.eligibleSeconds == 500)
        try store.observeRecovery(.ended(.sleep), at: instant(1100))
        try store.stop(now: instant(1200).date)
        #expect(try store.historyReport(from: day, through: day).totals.focusSeconds == 700)
        try store.decideRecovery(review.id, decision: .trim)
        try store.decideRecovery(review.id, decision: .trim)
        #expect(try store.historyReport(from: day, through: day).totals.focusSeconds == 200)
        #expect(try store.stats(from: day, through: day).metrics.focusSeconds == 200)
    }

    @Test func recoveryCodableRoundTripKeepsTypedStateAndStableIDOrder() throws {
        let status = RecoveryStatus(observing: nil, reviews: [], unresolvedSessionIDs: ["z", "a", "m"])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(status)
        #expect(String(decoding: encoded, as: UTF8.self) == #"{"reviews":[],"unresolvedSessionIDs":["a","m","z"]}"#)
        let decoded = try JSONDecoder().decode(RecoveryStatus.self, from: encoded)
        #expect(decoded.observing == nil && decoded.reviews.isEmpty)
        #expect(decoded.unresolvedSessionIDs == status.unresolvedSessionIDs)
    }
}
