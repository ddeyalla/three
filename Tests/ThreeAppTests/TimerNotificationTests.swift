import Foundation
import Testing
import ThreeCore
import UserNotifications
@testable import ThreeApp

struct TimerNotificationTests {
    @Test func prepareNativeSetupFixture() throws {
        func seed(_ store: Store) throws {
            let task = try store.addTask(NewTask(title: "405 Native setup focus", category: "Coding", blockMinutes: 30), source: .app)
            try store.addTask(NewTask(title: "405 Newer timer stays unchanged", category: "Writing", blockMinutes: 30), source: .app)
            try store.startFocus(taskId: task.id, minutes: 5, now: Date().addingTimeInterval(-285))
            #expect(try store.snapshot().running?.taskId == task.id)
            #expect(try !store.planningSettings().enabled)
        }
        if let path = ProcessInfo.processInfo.environment["THREE_SETUP_FIXTURE_DB"] {
            guard !FileManager.default.fileExists(atPath: path) else {
                throw ThreeError.invalid("Native setup fixtures require a new database path.")
            }
            try seed(Store(url: URL(fileURLWithPath: path)))
        } else { try withStore(seed) }
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("three-notifications-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(Store(url: directory.appendingPathComponent("db.sqlite")))
    }

    @Test func currentOverrunRoutesReviewAndExtensionWithoutChangingIdentity() throws {
        try withStore { store in
            let start = Date()
            let task = try store.addTask(NewTask(title: "Notification", category: "Coding", blockMinutes: 30), source: .app)
            try store.startFocus(taskId: task.id, minutes: 5, now: start)
            let session = try #require(store.snapshot().running)
            let identity = TimerNotificationIdentity(session: session)
            let delivered = try #require(TimerNotificationIdentity(userInfo: identity.userInfo))
            #expect(delivered == identity)
            let data = try PropertyListSerialization.data(fromPropertyList: identity.userInfo, format: .binary, options: 0)
            let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [AnyHashable: Any])
            #expect(TimerNotificationIdentity(userInfo: plist) == identity)
            let at = session.startedAt.addingTimeInterval(301)
            let fresh = try store.snapshot().running
            #expect(TimerNotificationRoute.resolve(action: TimerNotificationRoute.reviewAction,
                identity: delivered, current: fresh, saved: [], now: at) == .liveReflection)
            #expect(try store.snapshot().running == session)
            let route = TimerNotificationRoute.resolve(action: TimerNotificationRoute.extendAction,
                identity: delivered, current: fresh, saved: [], now: at)
            guard case .extendTimer(let expected) = route else { Issue.record("Expected guarded extension"); return }
            try store.extend(minutes: 5, expectedSession: expected, now: at)
            let extended = try #require(store.snapshot().running)
            #expect(extended.id == session.id)
            #expect(extended.remaining(at: at) == 300)
            #expect(TimerNotificationRoute.resolve(action: TimerNotificationRoute.reviewAction,
                identity: delivered, current: extended, saved: [], now: at) == .stale)
        }
    }

    @Test func pauseResumeAndNewTimerInvalidateDeliveredActionsIncludingWriteTimeRace() throws {
        try withStore { store in
            let start = Date()
            let task = try store.addTask(NewTask(title: "Stale reminder", category: "Coding", blockMinutes: 30), source: .app)
            try store.startFocus(taskId: task.id, minutes: 5, now: start)
            let session = try #require(store.snapshot().running)
            let identity = TimerNotificationIdentity(session: session)
            let at = start.addingTimeInterval(301)
            #expect(TimerNotificationRoute.resolve(action: TimerNotificationRoute.reviewAction,
                identity: identity, current: session, saved: [], now: start) == .stale)
            try store.pause(now: start.addingTimeInterval(20))
            #expect(TimerNotificationRoute.resolve(action: TimerNotificationRoute.extendAction,
                identity: identity, current: try store.snapshot().running, saved: [], now: at) == .stale)
            try store.resume(now: start.addingTimeInterval(60))
            #expect(TimerNotificationRoute.resolve(action: TimerNotificationRoute.reviewAction,
                identity: identity, current: try store.snapshot().running, saved: [], now: at) == .stale)
            try store.stop(now: at)
            try store.startFocus(taskId: task.id, minutes: 30, now: at)
            let next = try #require(store.snapshot().running)
            #expect(TimerNotificationRoute.resolve(action: TimerNotificationRoute.extendAction,
                identity: identity, current: next, saved: [], now: at) == .stale)
            #expect(throws: (any Error).self) { try store.extend(minutes: 5, expectedSession: session, now: at) }
            #expect(try store.snapshot().running == next)
        }
    }

    @Test func savedReflectionRoutesOnlyItsOwnSessionWhileNewTimerStaysUntouched() throws {
        try withStore { store in
            let start = Date()
            let task = try store.addTask(NewTask(title: "Saved review", category: "Coding", blockMinutes: 30), source: .app)
            try store.startFocus(taskId: task.id, minutes: 5, now: start)
            let session = try #require(store.snapshot().running)
            let identity = TimerNotificationIdentity(session: session)
            let expiry = start.addingTimeInterval(300)
            let prompt = ReflectionPrompt(session: session, openedAt: expiry)
            #expect(try store.deferReflection(prompt, now: prompt.deadline))
            try store.startFocus(taskId: task.id, now: prompt.deadline)
            let next = try #require(store.snapshot().running)
            let saved = try store.deferredReflections()
            #expect(TimerNotificationRoute.resolve(action: TimerNotificationRoute.reviewAction,
                identity: identity, current: next, saved: saved, now: prompt.deadline) == .savedReflection(session.id))
            #expect(TimerNotificationRoute.resolve(action: TimerNotificationRoute.extendAction,
                identity: identity, current: next, saved: saved, now: prompt.deadline) == .stale)
            #expect(try store.snapshot().running == next)
            try store.dismissDeferredReflection(session.id)
            #expect(TimerNotificationRoute.resolve(action: TimerNotificationRoute.reviewAction,
                identity: identity, current: next, saved: try store.deferredReflections(), now: prompt.deadline) == .stale)
        }
    }

    @Test func endedBreakOpensMainAndLegacyMalformedOrUnknownActionsCannotMutate() throws {
        try withStore { store in
            let start = Date()
            let rest = try store.startBreak(minutes: 1, now: start)
            let identity = TimerNotificationIdentity(session: rest)
            let at = start.addingTimeInterval(61)
            try store.finishBreakIfDue(now: at)
            #expect(try store.snapshot().running == nil)
            #expect(TimerNotificationRoute.resolve(action: UNNotificationDefaultActionIdentifier,
                identity: identity, current: nil, saved: [], now: at) == .openMain)
            for action in [TimerNotificationRoute.reviewAction, TimerNotificationRoute.extendAction, "unknown"] {
                #expect(TimerNotificationRoute.resolve(action: action, identity: identity,
                    current: nil, saved: [], now: at) == .stale)
                #expect(TimerNotificationRoute.resolve(action: action, identity: nil,
                    current: nil, saved: [], now: at) == .stale)
            }
            #expect(TimerNotificationIdentity(userInfo: [:]) == nil)
            var malformed = identity.userInfo
            malformed["threePlannedEndReference"] = Double.infinity
            #expect(TimerNotificationIdentity(userInfo: malformed) == nil)
            #expect(try store.snapshot().running == nil)
        }
    }
}
