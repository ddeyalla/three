import AppKit
import ThreeCore

/// Hides the apps the person chose to block while blocking is on. Hiding keeps every window and document: it never
/// quits anything. It runs only while Three runs, and touches only apps with a rule, never Three itself.
@MainActor
final class AppBlocker {
    private unowned let model: AppModel
    private var observers: [NSObjectProtocol] = []
    private(set) var failedRuleIDs: Set<String> = []
    /// The last app brought forward that isn't blocked or Three: where Back to work returns.
    private(set) var workApp: NSRunningApplication?

    init(model: AppModel) { self.model = model }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.noticed(app, launched: name == NSWorkspace.didLaunchApplicationNotification) }
            }
        }
    }

    /// An app came forward, launched or unhid. The cached state may be seconds old, so a match is checked against
    /// the Store before anything is hidden. A launch hides quietly; the overlay waits for the app to come forward.
    private func noticed(_ app: NSRunningApplication, launched: Bool) {
        guard !isThree(app) else { return }
        guard model.blocking.status.rules.contains(where: { $0.enabled && $0.bundleID?.matches(app.bundleIdentifier) == true }),
              let policy = try? model.store.blockPolicy(),
              let rule = policy.blocked.first(where: { $0.bundleID?.matches(app.bundleIdentifier) == true }) else {
            if app.isActive { workApp = app }
            model.blockOverlay.otherAppActivated(app)
            return
        }
        hide(app, rule: rule)
        guard app.isActive || !launched else { return }
        // Launching sends both an activation and a launch; count the attempt once.
        if !model.blockOverlay.isShowing(rule) { _ = try? model.store.recordBlockHit(ruleId: rule.id) }
        model.blockOverlay.present(.init(rule: rule, appName: app.localizedName ?? rule.name), mode: .blocked)
    }

    /// Hides every running app whose rule is in force: when blocking starts, a rule is added or an exception ends.
    func enforce(_ state: BlockingState) {
        let apps = state.blockedApps
        refreshFailures(state)
        guard !apps.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications where !app.isHidden && !isThree(app) {
            guard let rule = apps.first(where: { $0.bundleID?.matches(app.bundleIdentifier) == true }) else { continue }
            let wasActive = app.isActive
            hide(app, rule: rule)
            if wasActive {
                model.blockOverlay.present(.init(rule: rule, appName: app.localizedName ?? rule.name), mode: .blocked)
            }
        }
        refreshFailures(state)
    }

    /// `hide()` returns false even when the app hides a moment later, so look instead of trusting it. A launching
    /// app can take a second to accept; after three more tries the overlay says it couldn't be hidden.
    private func hide(_ app: NSRunningApplication, rule: BlockRule, tries: Int = 3) {
        app.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            refreshFailures(model.blocking)
            guard !app.isTerminated, !app.isHidden,
                  model.blocking.blockedApps.contains(where: { $0.id == rule.id }) else { return }
            if tries > 0 {
                hide(app, rule: rule, tries: tries - 1)
            } else {
                failedRuleIDs.insert(rule.id)
                model.updateAppBlockingFailures(failedRuleIDs)
                model.blockOverlay.setHidden(false, for: rule)
            }
        }
    }

    private func refreshFailures(_ state: BlockingState) {
        let failures = failedRuleIDs.filter { id in
            guard let rule = state.blockedApps.first(where: { $0.id == id }) else { return false }
            return NSWorkspace.shared.runningApplications.contains {
                !$0.isTerminated && !$0.isHidden && rule.bundleID?.matches($0.bundleIdentifier) == true
            }
        }
        guard failures != failedRuleIDs else { return }
        for rule in state.blockedApps where failedRuleIDs.contains(rule.id) && !failures.contains(rule.id) {
            model.blockOverlay.setHidden(true, for: rule)
        }
        failedRuleIDs = failures
        model.updateAppBlockingFailures(failures)
    }

    /// Shows an app again after the person opened its rule for five minutes.
    func release(_ rule: BlockRule) {
        for app in NSWorkspace.shared.runningApplications where rule.bundleID?.matches(app.bundleIdentifier) == true {
            app.unhide()
            app.activate()
        }
    }

    /// Brings back the app the person was working in, when macOS allows it. Never Three's own window.
    func returnToWork() {
        guard let app = workApp, !app.isTerminated, !app.isHidden, !isThree(app),
              let policy = try? model.store.blockPolicy(),
              !policy.blocked.contains(where: { $0.bundleID?.matches(app.bundleIdentifier) == true }) else { return }
        app.activate()
    }

    /// The running bundle, whatever its identifier: a relabelled copy must never hide itself either.
    private func isThree(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
            || (app.bundleIdentifier != nil && app.bundleIdentifier == Bundle.main.bundleIdentifier)
    }
}
