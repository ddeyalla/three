import Foundation
import Testing
import ThreeCore
@testable import ThreeApp

@MainActor
struct NotchControllerTests {
    private func withStore(_ body: (Store) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("three-notch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(Store(url: directory.appendingPathComponent("db.sqlite")))
    }

    @Test func preferenceDefaultsOffAndPersistsOnlyInInjectedDomain() {
        let name = "ThreeNotchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = NotchPreference(defaults: defaults)
        #expect(!preference.isEnabled)
        preference.isEnabled = true
        #expect(NotchPreference(defaults: defaults).isEnabled)
        preference.isEnabled = false
        #expect(!NotchPreference(defaults: defaults).isEnabled)
        defaults.set("invalid", forKey: NotchPreference.key)
        #expect(!NotchPreference(defaults: defaults).isEnabled)
    }

    @Test func escapeStaysDismissedAcrossRefreshAndNewSessionCanPresent() throws {
        try withStore { store in
            let task = try store.addTask(NewTask(title: "First block", category: "Coding", blockMinutes: 60), source: .app)
            let session = try store.startFocus(taskId: task.id)
            var state = NotchPresentation()
            #expect(state.shouldShow(enabled: true, session: session, reflecting: false, supported: true))
            state.dismiss(sessionID: session.id)
            for _ in 0..<3 {
                #expect(!state.shouldShow(enabled: true, session: session, reflecting: false, supported: true))
            }
            state.reveal()
            #expect(state.shouldShow(enabled: true, session: session, reflecting: false, supported: true))
            state.dismiss(sessionID: session.id)
            try store.stop()
            let next = try store.startFocus(taskId: task.id)
            #expect(next.id != session.id)
            #expect(state.shouldShow(enabled: true, session: next, reflecting: false, supported: true))
        }
    }

    @Test func disabledDisconnectedReflectionBreakAndNoSessionStayHidden() throws {
        try withStore { store in
            let task = try store.addTask(NewTask(title: "Block", category: "Coding", blockMinutes: 60), source: .app)
            let session = try store.startFocus(taskId: task.id)
            var state = NotchPresentation()
            #expect(!state.shouldShow(enabled: false, session: session, reflecting: false, supported: true))
            #expect(!state.shouldShow(enabled: true, session: session, reflecting: false, supported: false))
            #expect(!state.shouldShow(enabled: true, session: session, reflecting: true, supported: true))
            #expect(!state.shouldShow(enabled: true, session: nil, reflecting: false, supported: true))
            #expect(state.shouldShow(enabled: true, session: session, reflecting: false, supported: true))
            try store.stop()
            let ended = try #require(store.history(from: DayKey(Date()), through: DayKey(Date())).first)
            #expect(!state.shouldShow(enabled: true, session: ended, reflecting: false, supported: true))
            let rest = try store.startBreak()
            #expect(!state.shouldShow(enabled: true, session: rest, reflecting: false, supported: true))
        }
    }

    @Test func controlsUseSameStoreSessionAndDispatchFinishAndOpenExactlyOnce() throws {
        try withStore { store in
            let task = try store.addTask(NewTask(title: "One timer", category: "Coding", blockMinutes: 60), source: .app)
            let session = try store.startFocus(taskId: task.id)
            var finishRequests = 0
            var openRequests = 0
            let commands = NotchCommands(currentSession: { try? store.snapshot().running }, togglePause: { session in
                if session.isPaused { try! store.resume(expectedSessionID: session.id) }
                else { try! store.pause(expectedSessionID: session.id) }
            }, finishEarly: { finishRequests += 1 }, openMain: { openRequests += 1 })
            commands.perform(.pauseResume, sessionID: session.id)
            #expect(try store.snapshot().running?.isPaused == true)
            #expect(try store.snapshot().running?.id == session.id)
            commands.perform(.pauseResume, sessionID: session.id)
            #expect(try store.snapshot().running?.isPaused == false)
            #expect(try store.snapshot().running?.id == session.id)
            commands.perform(.finish, sessionID: session.id)
            #expect(finishRequests == 1)
            #expect(try store.snapshot().running?.id == session.id)
            commands.perform(.openMain, sessionID: session.id)
            #expect(openRequests == 1)
            try store.stop()
            let next = try store.startFocus(taskId: task.id)
            commands.perform(.pauseResume, sessionID: session.id)
            commands.perform(.finish, sessionID: session.id)
            #expect(try store.snapshot().running?.id == next.id)
            #expect(try store.snapshot().running?.isPaused == false)
            #expect(finishRequests == 1)
            try store.stop()
            commands.perform(.pauseResume, sessionID: next.id)
            #expect(try store.snapshot().running == nil)
            let rest = try store.startBreak()
            commands.perform(.pauseResume, sessionID: rest.id)
            commands.perform(.finish, sessionID: rest.id)
            #expect(try store.snapshot().running?.isPaused == false)
            #expect(finishRequests == 1)
            commands.perform(.openMain, sessionID: session.id)
            #expect(openRequests == 2)
        }
    }

    @Test(arguments: [false, true], [SessionKind.focus, .break])
    func aReplacementBetweenReadAndActionCannotBePausedOrResumed(resuming: Bool, kind: SessionKind) throws {
        try withStore { store in
            let peer = try Store(url: URL(fileURLWithPath: store.db.path))
            let task = try store.addTask(NewTask(title: "Displayed focus", category: "Coding", blockMinutes: 60), source: .app)
            let displayed = try store.startFocus(taskId: task.id)
            if resuming { try store.pause() }
            var replacement: Session?
            var refused = false
            let commands = NotchCommands(currentSession: {
                let captured = try! store.snapshot().running
                try! peer.stop()
                if kind == .focus { _ = try! peer.startFocus(taskId: task.id) }
                else { _ = try! peer.startBreak() }
                if resuming { try! peer.pause() }
                replacement = try! peer.snapshot().running
                return captured
            }, togglePause: { session in
                do {
                    if session.isPaused { try store.resume(expectedSessionID: session.id) }
                    else { try store.pause(expectedSessionID: session.id) }
                } catch { refused = true }
            }, finishEarly: {}, openMain: {})
            commands.perform(.pauseResume, sessionID: displayed.id)
            #expect(refused)
            #expect(replacement?.id != displayed.id)
            #expect(try store.snapshot().running == replacement)
        }
    }
}
