import Foundation
import GRDB
import Testing
@testable import ThreeCore

private let recoveryDay = DayKey("2026-10-21")!
private var origin: Date { recoveryDay.startDate.addingTimeInterval(9 * 3600) }

private func instant(_ seconds: TimeInterval, wall: TimeInterval? = nil, boot: String = "boot") -> RecoveryInstant {
    RecoveryInstant(date: origin.addingTimeInterval(wall ?? seconds), continuousSeconds: 10000 + seconds, clockID: boot)
}

private func recoveryStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-recovery-\(UUID().uuidString)/db.sqlite"))
}

@discardableResult
private func recoveryTask(_ store: Store, day: DayKey = recoveryDay) throws -> FocusTask {
    try store.addTask(NewTask(title: "Recovery work", category: "Coding", blockMinutes: 90), day: day, source: .cli)
}

private func savedSession(_ store: Store, _ id: String) throws -> Session {
    try store.db.read { try #require(try Session.fetchOne($0, key: id)) }
}

@Suite struct SleepRecoveryTests {
    @Test(arguments: [600.0, 600.001, 601.0])
    func tenMinuteBoundary(seconds: TimeInterval) throws {
        let store = try recoveryStore()
        let task = try recoveryTask(store)
        let session = try store.startFocus(taskId: task.id, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(100))
        let status = try store.observeRecovery(.ended(.sleep), at: instant(100 + seconds))
        #expect(status.observing == nil)
        #expect(status.reviews.count == (seconds > 600 ? 1 : 0))
        #expect(try savedSession(store, session.id).recoveryTrimSeconds == 0)
        if seconds > 600 {
            #expect(abs(status.reviews[0].eligibleSeconds - seconds) < 0.002)
        }
    }

    @Test func nestedLockAndSleepHaveOneReviewAndOneTrim() throws {
        let store = try recoveryStore()
        let task = try recoveryTask(store)
        let session = try store.startFocus(taskId: task.id, minutes: 45, now: origin)
        let gap = try #require(try store.observeRecovery(.began(.lock), at: instant(300)).observing)
        try store.observeRecovery(.began(.lock), at: instant(310))
        try store.observeRecovery(.began(.sleep), at: instant(400))
        #expect(try store.observeRecovery(.ended(.sleep), at: instant(1000)).observing?.id == gap.id)
        let status = try store.observeRecovery(.ended(.lock), at: instant(1200))
        #expect(status.reviews.count == 1 && status.reviews[0].id == gap.id)
        #expect(status.reviews[0].eligibleSeconds == 900)
        let decision = try store.decideRecovery(gap.id, decision: .trim, now: instant(1250).date)
        #expect(decision.state == .trimmed)
        #expect(try store.decideRecovery(gap.id, decision: .trim) == decision)
        #expect(try store.decideRecovery(gap.id, decision: .keep) == decision)
        #expect(try store.observeRecovery(.ended(.lock), at: instant(1300)).reviews.isEmpty)
        let running = try savedSession(store, session.id)
        #expect(running.id == session.id && running.isRunning && running.recoveryTrimSeconds == 900)
        #expect(running.elapsed(at: instant(1500).date) == 600)
        #expect(running.remaining(at: instant(1500).date) == 2100)
        #expect(running.plannedEnd == origin.addingTimeInterval(3600))
        try store.extend(minutes: 5, now: instant(1500).date)
        #expect(try savedSession(store, session.id).plannedEnd == origin.addingTimeInterval(3900))
    }

    @Test func keepRetainsRecordedWorkAndUnresolvedSurvivesReopen() throws {
        let store = try recoveryStore()
        let task = try recoveryTask(store)
        let session = try store.startFocus(taskId: task.id, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(200))
        try store.observeRecovery(.ended(.sleep), at: instant(1000))
        let peer = try Store(url: URL(fileURLWithPath: store.db.path))
        let status = try peer.recoveryStatus()
        let review = try #require(status.reviews.first)
        #expect(status.suspendsReconciliation(for: session.id))
        try peer.decideRecovery(review.id, decision: .keep, now: instant(1100).date)
        #expect(try store.recoveryStatus().unresolvedSessionIDs.isEmpty)
        #expect(try savedSession(store, session.id).elapsed(at: instant(1200).date) == 1200)
    }

    @Test func accumulatedAndActivePausesAreNeverSubtractedTwice() throws {
        let store = try recoveryStore()
        let task = try recoveryTask(store)
        let session = try store.startFocus(taskId: task.id, now: origin)
        try store.pause(now: instant(100).date)
        try store.resume(now: instant(200).date)
        try store.pause(now: instant(250).date)
        try store.observeRecovery(.began(.lock), at: instant(300))
        try store.resume(now: instant(500).date)
        try store.pause(now: instant(900).date)
        let review = try #require(try store.observeRecovery(.ended(.lock), at: instant(1300)).reviews.first)
        #expect(review.eligibleSeconds == 400)
        try store.decideRecovery(review.id, decision: .trim, now: instant(1350).date)
        let paused = try savedSession(store, session.id)
        #expect(paused.pausedSeconds == 350 && paused.pausedAt == instant(900).date)
        #expect(paused.elapsed(at: instant(1400).date) == 150)
        try store.resume(now: instant(1500).date)
        #expect(try savedSession(store, session.id).elapsed(at: instant(1600).date) == 250)
    }

    @Test func pauseStartingAndEndingWhileAwayUsesOnlyUnpausedAbsence() throws {
        let store = try recoveryStore()
        let session = try store.startFocus(taskId: recoveryTask(store).id, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(100))
        try store.pause(now: instant(300).date)
        try store.resume(now: instant(800).date)
        let review = try #require(try store.observeRecovery(.ended(.sleep), at: instant(1100)).reviews.first)
        #expect(review.eligibleSeconds == 500)
        try store.stop(now: instant(1200).date)
        try store.decideRecovery(review.id, decision: .trim)
        #expect(try savedSession(store, session.id).elapsed(at: instant(2000).date) == 200)
    }

    @Test func endingWhilePausedKeepsReflectionAndDoesNotTouchNewerTimer() throws {
        let store = try recoveryStore()
        let task = try recoveryTask(store)
        let session = try store.startFocus(taskId: task.id, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(100))
        try store.pause(now: instant(300).date)
        let prompt = ReflectionPrompt(session: try savedSession(store, session.id), openedAt: instant(300).date)
        #expect(try store.deferReflection(prompt, note: "Preserve this", now: instant(500).date))
        let newer = try store.startBreak(minutes: 5, now: instant(600).date)
        let review = try #require(try store.observeRecovery(.ended(.sleep), at: instant(1100)).reviews.first)
        #expect(review.eligibleSeconds == 200)
        try store.decideRecovery(review.id, decision: .trim)
        let old = try savedSession(store, session.id)
        #expect(!old.isRunning && old.reflectionPending && old.note == "Preserve this")
        #expect(old.elapsed(at: instant(1200).date) == 100)
        #expect(try store.snapshot(for: recoveryDay).running == newer)
    }

    @Test func anotherActorStartingFocusWhileAwayIsTrackedWithoutChangingIdentity() throws {
        let store = try recoveryStore()
        let peer = try Store(url: URL(fileURLWithPath: store.db.path))
        let task = try recoveryTask(store)
        let first = try store.startFocus(taskId: task.id, now: origin)
        try store.observeRecovery(.began(.lock), at: instant(100))
        try peer.finishFocus(outcome: .progress, rating: .focused, note: "First", markTaskDone: false, now: instant(400).date)
        let next = try peer.startFocus(taskId: task.id, now: instant(500).date)
        let review = try #require(try store.observeRecovery(.ended(.lock), at: instant(1100)).reviews.first)
        #expect(review.sessions.map(\.id) == [first.id, next.id])
        #expect(review.sessions.map(\.eligibleSeconds) == [300, 600])
        try peer.stop(now: instant(1200).date)
        let newest = try peer.startFocus(taskId: task.id, now: instant(1300).date)
        try store.decideRecovery(review.id, decision: .trim)
        #expect(try savedSession(store, first.id).elapsed(at: instant(1400).date) == 100)
        #expect(try savedSession(store, next.id).elapsed(at: instant(1400).date) == 100)
        #expect(try store.snapshot(for: recoveryDay).running == newest)
        #expect(throws: ThreeError.alreadyRunning) { try store.startFocus(taskId: task.id) }
    }

    @Test func relaunchClosesOnlyAnObservedGapAndRetainsPendingDecision() throws {
        let store = try recoveryStore()
        try store.startFocus(taskId: recoveryTask(store).id, now: origin)
        #expect(try store.observeRecovery(.relaunched, at: instant(100)).reviews.isEmpty)
        let gap = try #require(try store.observeRecovery(.began(.sleep), at: instant(200)).observing)
        let reopened = try Store(url: URL(fileURLWithPath: store.db.path))
        #expect(try reopened.recoveryStatus().observing?.id == gap.id)
        let review = try #require(try reopened.observeRecovery(.relaunched, at: instant(1200)).reviews.first)
        #expect(review.id == gap.id && review.eligibleSeconds == 1000)
        #expect(try reopened.observeRecovery(.relaunched, at: instant(1400)).reviews.count == 1)
    }

    @Test(arguments: ["rollback", "forward", "reboot", "notification", "transition"])
    func untrustworthyClockNeverTrims(kind: String) throws {
        let store = try recoveryStore()
        let session = try store.startFocus(taskId: recoveryTask(store).id, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(300))
        if kind == "notification" { try store.observeRecovery(.clockChanged, at: instant(400)) }
        if kind == "transition" { try store.pause(now: instant(200).date) }
        let end: RecoveryInstant = switch kind {
        case "rollback": instant(1200, wall: 100)
        case "forward": instant(1200, wall: 5000)
        case "reboot": instant(1200, boot: "another-boot")
        default: instant(1200)
        }
        let review = try #require(try store.observeRecovery(.ended(.sleep), at: end).reviews.first)
        #expect(!review.gap.clockReliable && review.eligibleSeconds == 0)
        #expect(throws: ThreeError.self) { try store.decideRecovery(review.id, decision: .trim) }
        try store.decideRecovery(review.id, decision: .keep)
        #expect(try savedSession(store, session.id).recoveryTrimSeconds == 0)
    }

    @Test func overlappingLateObservationCannotTrimAnAlreadyDecidedInterval() throws {
        let store = try recoveryStore()
        let session = try store.startFocus(taskId: recoveryTask(store).id, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(100))
        let first = try #require(try store.observeRecovery(.ended(.sleep), at: instant(1000)).reviews.first)
        try store.decideRecovery(first.id, decision: .trim)
        try store.observeRecovery(.began(.lock), at: instant(500))
        let overlap = try #require(try store.observeRecovery(.ended(.lock), at: instant(1400)).reviews.first)
        #expect(!overlap.gap.clockReliable && overlap.eligibleSeconds == 0)
        try store.decideRecovery(overlap.id, decision: .keep)
        try store.observeRecovery(.began(.sleep), at: instant(1500))
        let separate = try #require(try store.observeRecovery(.ended(.sleep), at: instant(2200)).reviews.first)
        #expect(separate.eligibleSeconds == 700)
        try store.decideRecovery(separate.id, decision: .trim)
        #expect(try savedSession(store, session.id).recoveryTrimSeconds == 1600)
        #expect(try savedSession(store, session.id).elapsed(at: instant(2300).date) == 700)
    }

    @Test func sleepDuringBreakNeedsNoFocusReviewOrTrimAndExpiryIsUnchanged() throws {
        let store = try recoveryStore()
        let rest = try store.startBreak(minutes: 5, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(100))
        #expect(try store.observeRecovery(.ended(.sleep), at: instant(1200)).reviews.isEmpty)
        try store.finishBreakIfDue(now: instant(1200).date)
        let ended = try savedSession(store, rest.id)
        #expect(ended.elapsed(at: instant(1200).date) == 300 && ended.recoveryTrimSeconds == 0)
        #expect(ended.endedAt == instant(300).date)
    }

    @Test func expiryDuringAbsenceWaitsForDecisionAndTrimMovesOnlyTheSharedDeadline() throws {
        let store = try recoveryStore()
        let session = try store.startFocus(taskId: recoveryTask(store).id, minutes: 5, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(100))
        let status = try store.observeRecovery(.ended(.sleep), at: instant(1200))
        let review = try #require(status.reviews.first)
        #expect(status.suspendsReconciliation(for: session.id))
        #expect(try savedSession(store, session.id).remaining(at: instant(1200).date) == -900)
        try store.decideRecovery(review.id, decision: .trim, now: instant(1200).date)
        let current = try savedSession(store, session.id)
        #expect(current.remaining(at: instant(1200).date) == 200)
        #expect(current.plannedEnd == instant(1400).date)
        #expect(try store.recoveryStatus().unresolvedSessionIDs.isEmpty)
    }

    @Test func defaultCloseGuardsBothAttributionAndTaskPlanEvenWithFalseCallback() throws {
        let store = try recoveryStore()
        let planDay = recoveryDay.adding(days: -1)
        let task = try recoveryTask(store, day: planDay)
        try store.commit(day: planDay)
        let localTask = try recoveryTask(store)
        try store.commit(day: recoveryDay)
        let session = try store.startFocus(taskId: task.id, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(100))
        try store.stop(now: instant(900).date)
        let due = recoveryDay.startDate.addingTimeInterval(23 * 3600)
        #expect(try store.closeDay(planDay, now: due) == .deferred(.recovery))
        let review = try #require(try store.observeRecovery(.ended(.sleep), at: instant(1100)).reviews.first)
        let reopened = try Store(url: URL(fileURLWithPath: store.db.path))
        for day in [planDay, recoveryDay] {
            #expect(try reopened.dayCloseStatus(for: day, now: due, pendingRecovery: { _, _ in false }) == .deferred(.recovery))
            #expect(try reopened.closeDay(day, now: due) == .deferred(.recovery))
            #expect(try reopened.dayCloseSummary(for: day) == nil)
        }
        #expect(try reopened.closeEligibleDays(now: due).attempts.allSatisfy { $0.result == .deferred(.recovery) })
        try reopened.decideRecovery(review.id, decision: .trim, now: due)
        #expect(try reopened.snapshot(for: planDay).tasks.first?.focusedSeconds == 100)
        #expect(try reopened.history(from: recoveryDay, through: recoveryDay).first?.elapsed(at: due) == 100)
        let detail = try reopened.historyReport(from: recoveryDay, through: recoveryDay, now: due)
        #expect(detail.totals.focusSeconds == 100)
        guard case .closed(let summary) = try reopened.closeDay(recoveryDay, now: due) else {
            Issue.record("Expected close after recovery decision"); return
        }
        #expect(summary.focusedSeconds == 100 && summary.focusSessions.first?.id == session.id)
        #expect(try reopened.snapshot(for: recoveryDay).tasks.first?.id == localTask.id)
    }

    @Test func concurrentWakeAndDecisionsConvergeAcrossDatabasePools() async throws {
        let store = try recoveryStore()
        let peer = try Store(url: URL(fileURLWithPath: store.db.path))
        let session = try store.startFocus(taskId: recoveryTask(store).id, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(100))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for writer in [store, peer] {
                group.addTask { try writer.observeRecovery(.ended(.sleep), at: instant(1100)); return () }
            }
            try await group.waitForAll()
        }
        let review = try #require(try store.recoveryStatus().reviews.first)
        let decisions = try await withThrowingTaskGroup(of: RecoveryGap.self) { group in
            group.addTask { try store.decideRecovery(review.id, decision: .trim, now: instant(1200).date) }
            group.addTask { try peer.decideRecovery(review.id, decision: .keep, now: instant(1200).date) }
            var results: [RecoveryGap] = []
            for try await result in group { results.append(result) }
            return results
        }
        #expect(decisions.count == 2 && decisions[0] == decisions[1])
        let current = try savedSession(store, session.id)
        #expect(current.recoveryTrimSeconds == (decisions[0].state == .trimmed ? 1000 : 0))
        #expect(try store.recoveryStatus().reviews.isEmpty)
    }

    @Test func failedTrimRollsBackSessionAndDecisionTogether() throws {
        let store = try recoveryStore()
        let session = try store.startFocus(taskId: recoveryTask(store).id, now: origin)
        try store.observeRecovery(.began(.sleep), at: instant(100))
        let review = try #require(try store.observeRecovery(.ended(.sleep), at: instant(1100)).reviews.first)
        try store.db.write { try $0.execute(sql: "CREATE TRIGGER reject_recovery BEFORE UPDATE OF state ON recoveryGap WHEN NEW.state = 'trimmed' BEGIN SELECT RAISE(ABORT, 'interrupted trim'); END") }
        #expect(throws: DatabaseError.self) { try store.decideRecovery(review.id, decision: .trim) }
        #expect(try savedSession(store, session.id).recoveryTrimSeconds == 0)
        #expect(try store.recoveryStatus().reviews.count == 1)
        try store.db.write { try $0.execute(sql: "DROP TRIGGER reject_recovery") }
        try store.decideRecovery(review.id, decision: .trim)
        #expect(try savedSession(store, session.id).recoveryTrimSeconds == 1000)
    }

    @Test(arguments: ["v10-planning-supervisor", "v11-day-close"])
    func oldSchemasUpgradeWithZeroTrimAndNoFabricatedGaps(migration: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("three-recovery-upgrade-\(UUID().uuidString)/db.sqlite")
        do {
            let old = try Store(url: url, upTo: migration)
            try old.db.write { db in
                try db.execute(sql: """
                    INSERT INTO session(id, kind, plannedSeconds, startedAt, pausedSeconds, endedAt, endReason, note, updatedAt)
                    VALUES('old-focus', 'focus', 1800, ?, 300, ?, 'stopped', 'Old reflection', ?)
                    """, arguments: [origin, instant(900).date, instant(900).date])
            }
        }
        let store = try Store(url: url)
        let session = try savedSession(store, "old-focus")
        #expect(session.elapsed(at: instant(1500).date) == 600)
        #expect(session.recoveryTrimSeconds == 0 && session.note == "Old reflection")
        #expect(try store.recoveryStatus().observing == nil)
        #expect(try store.recoveryStatus().reviews.isEmpty)
        #expect(try store.db.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") } == "ok")
        #expect(try store.db.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }.isEmpty)
    }

    @Test func oldSessionJSONDefaultsTrimToZeroAndInvalidInstantsDoNotWrite() throws {
        let store = try recoveryStore()
        let session = try store.startFocus(taskId: recoveryTask(store).id, now: origin)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        json.removeValue(forKey: "recoveryTrimSeconds")
        let decoded = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == session && decoded.recoveryTrimSeconds == 0)
        for value in [Double.nan, .infinity, -1] {
            #expect(throws: ThreeError.self) {
                try store.observeRecovery(.began(.sleep), at: RecoveryInstant(date: origin, continuousSeconds: value, clockID: "boot"))
            }
        }
        #expect(try store.recoveryStatus().observing == nil)
    }
}
