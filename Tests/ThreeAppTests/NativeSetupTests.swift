import Carbon
import Foundation
import Testing
@testable import ThreeApp

@MainActor
struct NativeSetupTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "ThreeNativeSetupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func shortcutDefaultsPersistAndDispatchOnceWithIdempotentStartAndCleanup() {
        withDefaults { defaults in
            var registrations: [MenuShortcut] = []
            var callback: (() -> Void)?
            var unregisters = 0
            var opens = 0
            let shortcut = GlobalMenuShortcut(defaults: defaults, register: { value, action in
                registrations.append(value)
                callback = action
            }, unregister: { unregisters += 1; callback = nil })
            #expect(shortcut.shortcut == MenuShortcut())
            #expect(shortcut.shortcut.title == "⌥⌘Space")
            #expect(shortcut.isEnabled)
            #expect(registrations.isEmpty)
            shortcut.start { opens += 1 }
            shortcut.start { opens += 100 }
            #expect(registrations == [MenuShortcut()])
            callback?()
            #expect(opens == 1)
            var changed = MenuShortcut()
            changed.key = .k
            changed.control = true
            shortcut.apply(changed, enabled: true)
            #expect(registrations == [MenuShortcut(), changed])
            #expect(shortcut.status == .registered)
            callback?()
            #expect(opens == 2)
            let restored = GlobalMenuShortcut(defaults: defaults, register: { _, _ in }, unregister: {})
            #expect(restored.shortcut == changed)
            shortcut.apply(changed, enabled: false)
            #expect(shortcut.status == .stopped)
            #expect(callback == nil)
            #expect(!GlobalMenuShortcut(defaults: defaults, register: { _, _ in }, unregister: {}).isEnabled)
            shortcut.stop()
            shortcut.stop()
            #expect(callback == nil)
            #expect(unregisters >= 3)
        }
    }

    @Test func shortcutConflictAndFailureAreVisibleAndRetryDoesNotSteal() {
        withDefaults { defaults in
            var fail = true
            var attempts = 0
            let shortcut = GlobalMenuShortcut(defaults: defaults, register: { _, _ in
                attempts += 1
                if fail { throw ShortcutFailure.registration(OSStatus(eventHotKeyExistsErr)) }
            }, unregister: {})
            shortcut.start {}
            guard case .failed(let message) = shortcut.status else { Issue.record("Conflict must be visible"); return }
            #expect(message.contains("already in use"))
            #expect(attempts == 1)
            fail = false
            shortcut.retry()
            #expect(shortcut.status == .registered)
            #expect(attempts == 2)
            var invalid = MenuShortcut()
            invalid.command = false
            invalid.option = false
            shortcut.apply(invalid, enabled: true)
            #expect(shortcut.shortcut == MenuShortcut())
            #expect(attempts == 2)
            defaults.set(Data("invalid".utf8), forKey: GlobalMenuShortcut.shortcutKey)
            #expect(GlobalMenuShortcut(defaults: defaults, register: { _, _ in }, unregister: {}).shortcut == MenuShortcut())
        }
    }

    @Test func enabledSystemShortcutIsAConflictAndDifferentOrDisabledKeysAreNot() {
        let shortcut = MenuShortcut()
        let key = kHISymbolicHotKeyCode as String
        let modifiers = kHISymbolicHotKeyModifiers as String
        let enabled = kHISymbolicHotKeyEnabled as String
        let system: [String: Any] = [key: shortcut.key.code, modifiers: shortcut.modifiers, enabled: true]
        #expect(CarbonMenuShortcut.conflicts(shortcut, symbolicKeys: [system]))
        var disabled = system
        disabled[enabled] = false
        #expect(!CarbonMenuShortcut.conflicts(shortcut, symbolicKeys: [disabled]))
        var other = system
        other[key] = MenuShortcut.Key.k.code
        #expect(!CarbonMenuShortcut.conflicts(shortcut, symbolicKeys: [other]))
        other = system
        other[modifiers] = UInt32(cmdKey)
        #expect(!CarbonMenuShortcut.conflicts(shortcut, symbolicKeys: [other]))
    }

    @Test func skippingOnboardingPersistsAndDoesNotRegisterShortcutOrLogin() {
        withDefaults { defaults in
            let setup = NativeSetup(defaults: defaults)
            #expect(!setup.onboardingDismissed)
            #expect(setup.shortcut.status == .stopped)
            #expect(setup.notifications.state == .unknown)
            setup.dismissOnboarding()
            #expect(NativeSetup(defaults: defaults).onboardingDismissed)
            setup.showOnboarding()
            #expect(!setup.onboardingDismissed)
            #expect(setup.shortcut.status == .stopped)
            #expect(setup.notifications.state == .unknown)
        }
    }

    @Test func notificationPermissionIsRequestedOnlyByExplicitActionAndDenialIsRealState() async {
        var permission: NotificationAccessState = .notDetermined
        var requests = 0
        let access = NotificationAccess(read: { permission }, request: { requests += 1; permission = .denied })
        #expect(requests == 0)
        await access.refresh()
        #expect(access.state == .notDetermined)
        #expect(requests == 0)
        await access.requestFromUserAction()
        #expect(requests == 1)
        #expect(access.state == .denied)
        #expect(access.state.text.contains("still works"))
        #expect(!access.isRequesting)
        permission = .authorized
        await access.refresh()
        #expect(access.state == .authorized)
        #expect(requests == 1)
    }

    @Test func notificationRequestFailureIsBoundedAndUnsupportedRemainsVisible() async {
        struct Failure: LocalizedError {
            var errorDescription: String? { String(repeating: "x", count: 900) }
        }
        let access = NotificationAccess(read: { .unsupported }, request: { throw Failure() })
        await access.requestFromUserAction()
        #expect(access.state == .unsupported)
        #expect(access.error?.count == 400)
        #expect(!access.isRequesting)
    }

    @Test func loginUsesOSStateAndRequiresExplicitOptInWithApprovalAndFailure() async {
        var state: LoginItemState = .notRegistered
        var changes: [Bool] = []
        var failure = false
        let login = LoginItemControl(read: { state }, change: { enabled in
            changes.append(enabled)
            if failure { throw ShortcutFailure.registration(-1) }
            state = enabled ? .requiresApproval : .notRegistered
        })
        #expect(changes.isEmpty)
        login.refresh()
        #expect(changes.isEmpty)
        await login.setEnabledFromUserAction(true)
        #expect(changes == [true])
        #expect(login.state == .requiresApproval)
        await login.setEnabledFromUserAction(true)
        #expect(changes == [true])
        state = .enabled
        login.refresh()
        #expect(login.state == .enabled)
        failure = true
        await login.setEnabledFromUserAction(false)
        #expect(login.state == .enabled)
        #expect(login.error != nil)
        failure = false
        await login.setEnabledFromUserAction(false)
        #expect(login.state == .notRegistered)
        #expect(login.error == nil)
        state = .unsupported
        login.refresh()
        let before = changes
        await login.setEnabledFromUserAction(true)
        #expect(login.state == .unsupported)
        #expect(changes == before)
    }
}
