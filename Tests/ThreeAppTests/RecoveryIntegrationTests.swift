import Foundation
import Observation
import Testing
import ThreeCore
import UserNotifications
@testable import ThreeApp

@MainActor
private final class RecoveryIntegrationFixture {
    let directory: URL
    let store: Store
    let start: Date
    var seconds: TimeInterval = 100
    var pendingRemovals: [String] = []
    var deliveredRemovals: [String] = []
    var requests: [UNNotificationRequest] = []
    var completions: [@Sendable (String?) -> Void] = []
    var presentationChanges = 0

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("three-recovery-integration-\(UUID().uuidString)")
        store = try Store(url: directory.appendingPathComponent("db.sqlite"))
        start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 10))!
    }

    var instant: RecoveryInstant {
        RecoveryInstant(date: start.addingTimeInterval(seconds), continuousSeconds: 10000 + seconds, clockID: "integration-boot")
    }

    func instant(_ seconds: TimeInterval) -> RecoveryInstant {
        RecoveryInstant(date: start.addingTimeInterval(seconds), continuousSeconds: 10000 + seconds, clockID: "integration-boot")
    }

    @discardableResult
    func focus(minutes: Int = 5) throws -> Session {
        let row = try store.addTask(NewTask(title: "Recovery focus", category: "Coding", blockMinutes: 45), day: DayKey(start), source: .app)
        return try store.startFocus(taskId: row.id, minutes: minutes, now: start)
    }

    func model() -> AppModel {
        AppModel(store: store, clock: { self.instant }, notifications: TimerNotificationDelivery(
            removePending: { self.pendingRemovals += $0 },
            removeDelivered: { self.deliveredRemovals += $0 },
            add: { request, completion in self.requests.append(request); self.completions.append(completion) }
        ), runsSystemEffects: false)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@Suite @MainActor struct RecoveryIntegrationTests {
    @Test func unchangedRecoveryRefreshDoesNotInvalidateItsUIReaders() throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        try fixture.focus(minutes: 45)
        let model = fixture.model()
        defer { model.shutdown() }
        withObservationTracking {
            _ = model.recovery.reviews.count
        } onChange: {
            MainActor.assumeIsolated { fixture.presentationChanges += 1 }
        }
        fixture.seconds += 60
        model.tick()
        model.reload()
        #expect(fixture.presentationChanges == 0)
        model.recovery.receive(.began(.sleep))
        fixture.seconds += 900
        model.recovery.receive(.ended(.sleep))
        #expect(fixture.presentationChanges == 1 && model.hasRecoveryNotice)
    }

    @Test func aDueBreakReminderSurvivesAutomaticCompletionAndFocusRecoveryFailure() throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        let session = try fixture.store.startBreak(minutes: 5, now: fixture.start)
        let model = fixture.model()
        defer { model.shutdown() }
        let identity = TimerNotificationIdentity(session: session)
        try fixture.store.db.write { try $0.execute(sql: "CREATE TRIGGER reject_recovery BEFORE INSERT ON recoveryGap BEGIN SELECT RAISE(ABORT, 'retry recovery'); END") }
        #expect(!model.recovery.receive(.began(.sleep)))
        fixture.seconds = 301
        model.tick()
        #expect(model.recovery.needsRetry)
        #expect(model.shouldPresentTimerNotification(identity))
        #expect(model.running == nil)
        #expect(try fixture.store.snapshot(for: DayKey(fixture.start)).sessions.first?.endedAt != nil)
    }

    @Test func launchClosesObservedGapBeforeCatchUpAndNeverInventsABegin() throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        let session = try fixture.focus()
        try fixture.store.commit(day: DayKey(fixture.start))
        try fixture.store.observeRecovery(.began(.sleep), at: fixture.instant(100))
        try fixture.store.stop(now: fixture.instant(200).date)
        fixture.seconds = 13 * 3600
        let model = fixture.model()
        defer { model.shutdown() }
        #expect(model.recovery.status?.observing == nil)
        #expect(model.recovery.reviews.count == 1)
        #expect(model.snapshot.plan?.status == .committed)
        #expect(model.dayCloses.isEmpty)
        #expect(fixture.deliveredRemovals == [session.id])
        #expect(fixture.requests.isEmpty)
        let review = try #require(model.recovery.reviews.first)
        #expect(model.recovery.decide(review.id, .keep))
        #expect(model.snapshot.plan?.status == .closed)
        #expect(model.dayCloses.count == 1)
        let reopened = fixture.model()
        defer { reopened.shutdown() }
        #expect(reopened.recovery.status?.observing == nil && reopened.recovery.reviews.isEmpty)
        #expect(reopened.dayCloses.count == 1)
    }

    @Test func unresolvedRecoverySuppressesExpiryAndStaleActionsThenTrimRearmsTheSameTimer() throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        let session = try fixture.focus()
        let model = fixture.model()
        defer { model.shutdown() }
        #expect(fixture.requests.count == 1)
        let oldIdentity = TimerNotificationIdentity(session: session)
        model.recovery.receive(.began(.sleep))
        fixture.seconds = 1000
        model.recovery.receive(.ended(.sleep))
        model.tick()
        #expect(model.reflectionPresentation == nil)
        #expect(fixture.requests.count == 1)
        #expect(Set(fixture.pendingRemovals) == [session.id])
        #expect(Set(fixture.deliveredRemovals) == [session.id])
        model.handleTimerNotification(action: TimerNotificationRoute.extendAction, identity: oldIdentity)
        #expect(!model.shouldPresentTimerNotification(oldIdentity))
        #expect(model.reviewingRecovery)
        #expect(model.running == session)
        model.reviewingRecovery = false
        model.tick()
        #expect(model.recovery.reviews.count == 1)
        #expect(model.recovery.decide(try #require(model.recovery.reviews.first).id, .trim))
        let adjusted = try #require(model.running)
        #expect(adjusted.id == session.id && adjusted.recoveryTrimSeconds == 900)
        #expect(adjusted.remaining(at: fixture.instant.date) == 200)
        #expect(fixture.requests.count == 2)
        let request = try #require(fixture.requests.last)
        #expect(TimerNotificationIdentity(userInfo: request.content.userInfo)?.matches(adjusted) == true)
        #expect((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 200)
        model.handleTimerNotification(action: TimerNotificationRoute.extendAction, identity: oldIdentity)
        #expect(model.running == adjusted)
        #expect(model.notificationError != nil)
        #expect(!model.reviewingRecovery)
    }

    @Test func failedBeginRetainsItsTimestampSuspendsCatchUpAndRetryRestoresReconciliation() throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        let session = try fixture.focus()
        let model = fixture.model()
        defer { model.shutdown() }
        let nextDay = try #require(DayKey("2026-11-04"))
        try fixture.store.addTask(NewTask(title: "Catch up", category: "Coding", blockMinutes: 30), day: nextDay, source: .app)
        try fixture.store.commit(day: nextDay)
        try fixture.store.db.write { try $0.execute(sql: "CREATE TRIGGER reject_recovery BEFORE INSERT ON recoveryGap BEGIN SELECT RAISE(ABORT, 'retry recovery'); END") }
        #expect(!model.recovery.receive(.began(.sleep)))
        fixture.seconds = 1000
        #expect(!model.recovery.receive(.ended(.sleep)))
        fixture.seconds = 2 * 86400
        model.reload()
        model.tick()
        #expect(model.recovery.needsRetry && model.recovery.error != nil)
        #expect(model.reflectionPresentation == nil)
        #expect(try fixture.store.snapshot(for: nextDay).plan?.status == .committed)
        #expect(model.running?.id == session.id && model.running?.isPaused == false)
        #expect(Set(fixture.deliveredRemovals) == [session.id])
        #expect(fixture.requests.count == 1)
        try fixture.store.db.write { try $0.execute(sql: "DROP TRIGGER reject_recovery") }
        model.recovery.retry()
        #expect(!model.recovery.needsRetry && model.recovery.error == nil)
        let review = try #require(model.recovery.reviews.first)
        #expect(review.gap.startedAt == fixture.instant(100).date)
        #expect(review.gap.endedAt == fixture.instant(1000).date && review.eligibleSeconds == 900)
        #expect(try fixture.store.snapshot(for: nextDay).plan?.status == .closed)
        #expect(model.running?.id == session.id && model.reflectionPresentation == nil)
    }

    @Test func historicalDecisionAndActionErrorLeaveANewerTimerNotificationAlone() throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        let previous = try fixture.focus()
        try fixture.store.observeRecovery(.began(.sleep), at: fixture.instant(100))
        try fixture.store.observeRecovery(.clockChanged, at: fixture.instant(500))
        try fixture.store.stop(now: fixture.instant(700).date)
        try fixture.store.observeRecovery(.ended(.sleep), at: fixture.instant(1000))
        fixture.seconds = 1100
        let next = try fixture.store.startFocus(taskId: previous.taskId, minutes: 30, now: fixture.instant.date)
        let model = fixture.model()
        defer { model.shutdown() }
        fixture.pendingRemovals = []
        fixture.deliveredRemovals = []
        let count = fixture.requests.count
        let review = try #require(model.recovery.reviews.first)
        #expect(!model.recovery.decide(review.id, .trim))
        model.tick()
        #expect(model.recovery.error != nil && !model.recovery.needsRetry)
        #expect(!model.recovery.suspendsReconciliation(for: next))
        #expect(model.running == next && fixture.requests.count == count)
        #expect(Set(fixture.deliveredRemovals) == [previous.id])
        #expect(!fixture.pendingRemovals.contains(next.id))
        #expect(model.recovery.decide(review.id, .keep))
        #expect(model.running == next && fixture.requests.count == count)
    }

    @Test func externalTrimUpdatesNotificationDeadlineWithoutTheControllersDecisionCallback() throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        let session = try fixture.focus(minutes: 45)
        let model = fixture.model()
        defer { model.shutdown() }
        try fixture.store.observeRecovery(.began(.sleep), at: fixture.instant(100))
        try fixture.store.observeRecovery(.ended(.sleep), at: fixture.instant(1000))
        let review = try #require(fixture.store.recoveryStatus().reviews.first)
        try fixture.store.decideRecovery(review.id, decision: .trim, now: fixture.instant(1000).date)
        fixture.seconds = 1000
        model.reload()
        let adjusted = try #require(model.running)
        #expect(adjusted.id == session.id && adjusted.recoveryTrimSeconds == 900)
        #expect(Set(fixture.deliveredRemovals) == [session.id])
        #expect(fixture.requests.count == 2)
        let request = try #require(fixture.requests.last)
        let identity = try #require(TimerNotificationIdentity(userInfo: request.content.userInfo))
        #expect(identity.plannedEnd == session.plannedEnd.addingTimeInterval(900))
    }

    @Test func liveReflectionRetainsNoteAndReceivesFreshTimeoutAfterExplicitDecision() throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        let session = try fixture.focus()
        fixture.seconds = 301
        let model = fixture.model()
        defer { model.shutdown() }
        model.tick()
        guard case .live(let oldPrompt, _) = model.reflectionPresentation?.content else { Issue.record("Expected expiry reflection"); return }
        let presentation = try #require(model.reflectionPresentation)
        model.reflectionActivity(note: "Keep this draft")
        withObservationTracking {
            _ = presentation.session.recoveryTrimSeconds
        } onChange: {
            MainActor.assumeIsolated { fixture.presentationChanges += 1 }
        }
        model.recovery.receive(.began(.lock))
        fixture.seconds = 1201
        model.recovery.receive(.ended(.lock))
        model.tick()
        #expect(model.running?.id == session.id && model.running?.isRunning == true)
        #expect(fixture.instant.date > oldPrompt.deadline)
        #expect(model.recovery.decide(try #require(model.recovery.reviews.first).id, .trim))
        guard case .live(let rebound, _) = model.reflectionPresentation?.content else { Issue.record("Lost live draft"); return }
        #expect(model.reflectionPresentation === presentation)
        #expect(fixture.presentationChanges > 0)
        #expect(presentation.session.recoveryTrimSeconds == 900)
        #expect(rebound.session.recoveryTrimSeconds == 900)
        #expect(rebound.deadline == fixture.instant.date.addingTimeInterval(120))
        model.tick()
        #expect(model.running?.id == session.id)
        fixture.seconds += 119
        model.tick()
        #expect(model.running?.id == session.id)
        fixture.seconds += 1
        model.tick()
        #expect(model.running == nil)
        let saved = try #require(model.deferredReflections.first)
        #expect(saved.session.note == "Keep this draft" && saved.session.recoveryTrimSeconds == 900)
    }

    @Test func historicalTrimRefreshesTheOpenSavedPresentationWithoutLosingAnswersOrNewTimer() throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        let session = try fixture.focus()
        try fixture.store.observeRecovery(.began(.sleep), at: fixture.instant(100))
        let prompt = ReflectionPrompt(session: session, openedAt: fixture.instant(301).date)
        #expect(try fixture.store.deferReflection(prompt, note: "Saved note", now: fixture.instant(700).date))
        try fixture.store.observeRecovery(.ended(.sleep), at: fixture.instant(1000))
        fixture.seconds = 1100
        let newer = try fixture.store.startFocus(taskId: session.taskId, minutes: 30, now: fixture.instant.date)
        let model = fixture.model()
        defer { model.shutdown() }
        model.reviewReflection(try #require(model.deferredReflections.first))
        let presentation = try #require(model.reflectionPresentation)
        let before = presentation.session
        let requests = fixture.requests.count
        #expect(model.recovery.decide(try #require(model.recovery.reviews.first).id, .trim))
        #expect(model.reflectionPresentation === presentation)
        #expect(presentation.session.recoveryTrimSeconds == 600)
        #expect(presentation.session.note == before.note && presentation.session.outcome == before.outcome)
        #expect(presentation.session.focusRating == before.focusRating && presentation.isSaved)
        #expect(model.running == newer && fixture.requests.count == requests)
        #expect(!fixture.deliveredRemovals.contains(newer.id))
    }

    @Test func trimBeforeTimeoutReloadRejectsTheOldDeferAndPreservesTheLiveDraft() throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        let session = try fixture.focus()
        fixture.seconds = 301
        let model = fixture.model()
        defer { model.shutdown() }
        model.tick()
        model.reflectionActivity(note: "Keep through external trim")
        let presentation = try #require(model.reflectionPresentation)
        try fixture.store.observeRecovery(.began(.sleep), at: fixture.instant(310))
        try fixture.store.observeRecovery(.ended(.sleep), at: fixture.instant(1210))
        let review = try #require(fixture.store.recoveryStatus().reviews.first)
        try fixture.store.decideRecovery(review.id, decision: .trim, now: fixture.instant(1210).date)
        fixture.seconds = 1210
        model.tick()
        #expect(model.running?.id == session.id && model.running?.recoveryTrimSeconds == 900)
        #expect(model.deferredReflections.isEmpty)
        #expect(model.reflectionPresentation === presentation)
        guard case .live(let prompt, _) = presentation.content else { Issue.record("Lost live prompt"); return }
        #expect(prompt.deadline == fixture.instant.date.addingTimeInterval(120))
        fixture.seconds += 120
        model.tick()
        #expect(model.deferredReflections.first?.session.note == "Keep through external trim")
    }

    @Test func obsoleteNotificationCompletionCannotReplaceTheRearmedReminderState() async throws {
        let fixture = try RecoveryIntegrationFixture()
        defer { fixture.cleanup() }
        try fixture.focus()
        let model = fixture.model()
        defer { model.shutdown() }
        let oldCompletion = try #require(fixture.completions.first)
        model.recovery.receive(.began(.sleep))
        fixture.seconds = 1000
        model.recovery.receive(.ended(.sleep))
        #expect(model.recovery.decide(try #require(model.recovery.reviews.first).id, .trim))
        oldCompletion("Obsolete reminder failed")
        await Task.yield()
        #expect(model.notificationError == nil)
        let currentCompletion = try #require(fixture.completions.last)
        currentCompletion("Current reminder failed")
        await Task.yield()
        #expect(model.notificationError?.contains("Current reminder failed") == true)
    }
}
