import AppKit
import Foundation
import Testing
import ThreeCore
@testable import ThreeApp

private func controllerStore() throws -> Store {
    try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-recovery-controller-\(UUID().uuidString)/db.sqlite"))
}

private func controllerInstant(_ seconds: TimeInterval) -> RecoveryInstant {
    RecoveryInstant(date: Date(timeIntervalSince1970: 1_793_000_000 + seconds), continuousSeconds: 10000 + seconds, clockID: "test-boot")
}

@discardableResult
private func controllerFocus(_ store: Store, at date: Date) throws -> Session {
    let task = try store.addTask(NewTask(title: "Interrupted task", category: "Coding", blockMinutes: 45), day: DayKey(date), source: .app)
    return try store.startFocus(taskId: task.id, minutes: 5, now: date)
}

@Suite @MainActor struct SleepRecoveryControllerTests {
    @Test func observerCommitsBeforeReconciliationAndDoesNotDecideAutomatically() throws {
        let store = try controllerStore()
        let focus = try controllerFocus(store, at: controllerInstant(0).date)
        var now = controllerInstant(100)
        let controller = SleepRecoveryController(store: store, clock: { now })
        let workspace = NotificationCenter(), local = NotificationCenter(), screen = NotificationCenter()
        var callbacks = 0
        controller.didChange = { affected in
            callbacks += 1
            if callbacks > 1 { #expect(affected.contains(focus.id)) }
            do {
                let durable = try store.recoveryStatus()
                #expect(durable.observing?.id == controller.status?.observing?.id)
                #expect(durable.reviews.map(\.id) == controller.reviews.map(\.id))
                #expect(durable.unresolvedSessionIDs == controller.status?.unresolvedSessionIDs)
            } catch { Issue.record(error) }
        }
        controller.start(workspace: workspace, local: local, screen: screen)
        #expect(callbacks == 1 && controller.reviews.isEmpty)
        screen.post(name: RecoverySystemEvent.screenLocked, object: nil)
        #expect(controller.suspendsReconciliation(for: focus))
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        now = controllerInstant(1000)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(controller.status?.observing != nil && controller.reviews.isEmpty)
        screen.post(name: RecoverySystemEvent.screenUnlocked, object: nil)
        #expect(controller.status?.observing == nil && controller.reviews.count == 1)
        #expect(controller.reviews.first?.eligibleSeconds == 900)
        #expect(controller.suspendsReconciliation(for: focus))
        #expect(try store.snapshot(for: DayKey(now.date)).running?.recoveryTrimSeconds == 0)
        controller.stop()
        now = controllerInstant(2000)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(controller.status?.observing == nil)
        #expect(callbacks == 5)
    }

    @Test func trimRearmsSharedTimerAndHistoricalDecisionLeavesNewFocusAlone() throws {
        let store = try controllerStore()
        let focus = try controllerFocus(store, at: controllerInstant(0).date)
        var now = controllerInstant(100)
        let controller = SleepRecoveryController(store: store, clock: { now })
        var invalidated = Set<String>()
        controller.didChange = { invalidated = $0 }
        #expect(controller.receive(.began(.sleep)))
        now = controllerInstant(1000)
        #expect(controller.receive(.ended(.sleep)))
        let review = try #require(controller.reviews.first)
        #expect(controller.decide(review.id, .trim))
        #expect(invalidated == [focus.id])
        let trimmed = try #require(try store.snapshot(for: DayKey(now.date)).running)
        #expect(trimmed.id == focus.id && trimmed.remaining(at: now.date) == 200)
        #expect(!controller.suspendsReconciliation(for: trimmed))
        now = controllerInstant(1100)
        controller.receive(.began(.lock))
        try store.stop(now: controllerInstant(1200).date)
        now = controllerInstant(2000)
        controller.receive(.ended(.lock))
        let historical = try #require(controller.reviews.first)
        let next = try store.startFocus(taskId: focus.taskId, now: now.date)
        controller.refresh()
        #expect(!controller.suspendsReconciliation(for: next))
        #expect(controller.decide(historical.id, .trim))
        #expect(invalidated == [focus.id] && !invalidated.contains(next.id))
        #expect(try store.snapshot(for: DayKey(now.date)).running == next)
    }

    @Test func restartingObserverRecoversDurableBeginBeforeItsFirstCallback() throws {
        let store = try controllerStore()
        let focus = try controllerFocus(store, at: controllerInstant(0).date)
        try store.observeRecovery(.began(.sleep), at: controllerInstant(100))
        let reopened = try Store(url: URL(fileURLWithPath: store.db.path))
        let controller = SleepRecoveryController(store: reopened, clock: { controllerInstant(1000) })
        var callbackCount = 0
        controller.didChange = { _ in
            callbackCount += 1
            #expect(controller.status?.observing == nil)
            #expect(controller.reviews.count == 1)
            #expect(controller.suspendsReconciliation(for: focus))
        }
        let workspace = NotificationCenter(), local = NotificationCenter(), screen = NotificationCenter()
        controller.start(workspace: workspace, local: local, screen: screen)
        controller.start(workspace: workspace, local: local, screen: screen)
        #expect(callbackCount == 1)
        controller.stop()
        controller.didChange = { _ in }
    }

    @Test func clockNotificationKeepsDecisionExplicitAndTrimUnavailable() throws {
        let store = try controllerStore()
        try controllerFocus(store, at: controllerInstant(0).date)
        var now = controllerInstant(100)
        let controller = SleepRecoveryController(store: store, clock: { now })
        let workspace = NotificationCenter(), local = NotificationCenter(), screen = NotificationCenter()
        controller.start(workspace: workspace, local: local, screen: screen)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        local.post(name: .NSSystemClockDidChange, object: nil)
        now = controllerInstant(1000)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        let review = try #require(controller.reviews.first)
        #expect(!review.gap.clockReliable && review.eligibleSeconds == 0)
        #expect(!controller.decide(review.id, .trim) && controller.error != nil)
        #expect(controller.reviews.count == 1)
        #expect(controller.decide(review.id, .keep))
        #expect(controller.reviews.isEmpty && controller.error == nil)
        controller.stop()
    }

    @Test func writeFailureRetainsOriginalEventOrderAndCanRetryWithoutInventingTime() throws {
        let store = try controllerStore()
        let focus = try controllerFocus(store, at: controllerInstant(0).date)
        let controller = SleepRecoveryController(store: store, clock: { controllerInstant(2000) })
        try store.db.write { try $0.execute(sql: "CREATE TRIGGER reject_begin BEFORE INSERT ON recoveryGap BEGIN SELECT RAISE(ABORT, 'failed begin'); END") }
        #expect(!controller.receive(.began(.sleep), at: controllerInstant(100)))
        #expect(controller.error != nil && controller.suspendsReconciliation(for: focus))
        #expect(!controller.receive(.ended(.sleep), at: controllerInstant(1000)))
        try store.db.write { try $0.execute(sql: "DROP TRIGGER reject_begin") }
        #expect(controller.refresh())
        let review = try #require(controller.reviews.first)
        #expect(review.gap.startedAt == controllerInstant(100).date && review.gap.endedAt == controllerInstant(1000).date)
        #expect(review.eligibleSeconds == 900 && controller.error == nil)
    }

    @Test func unrelatedNativeNotificationDoesNotFabricateAGap() throws {
        #expect(RecoverySystemEvent.event(for: NSWorkspace.screensDidSleepNotification) == nil)
        #expect(RecoverySystemEvent.event(for: NSApplication.didBecomeActiveNotification) == nil)
        let first = RecoverySystemClock.now(), second = RecoverySystemClock.now()
        #expect(first.clockID?.isEmpty == false && first.clockID == second.clockID)
        #expect(try #require(second.continuousSeconds) >= #require(first.continuousSeconds))
    }

    @Test func historicalDecisionErrorDoesNotSuspendANewerFocusTimer() throws {
        let store = try controllerStore()
        let focus = try controllerFocus(store, at: controllerInstant(0).date)
        let controller = SleepRecoveryController(store: store, clock: { controllerInstant(1200) })
        controller.receive(.began(.sleep), at: controllerInstant(100))
        controller.receive(.clockChanged, at: controllerInstant(500))
        controller.receive(.ended(.sleep), at: controllerInstant(1000))
        let review = try #require(controller.reviews.first)
        try store.stop(now: controllerInstant(1100).date)
        let newer = try store.startFocus(taskId: focus.taskId, now: controllerInstant(1200).date)
        #expect(!controller.decide(review.id, .trim))
        #expect(controller.error != nil && !controller.suspendsReconciliation(for: newer))
        #expect(try store.snapshot(for: DayKey(controllerInstant(1200).date)).running == newer)
    }
}
