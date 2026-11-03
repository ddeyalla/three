import AppKit
import Observation
import ServiceManagement
import UserNotifications

enum NotificationAccessState: Equatable {
    case unknown, notDetermined, denied, authorized, provisional, unsupported

    var text: String {
        switch self {
        case .unknown: "Checking notification access…"
        case .notDetermined: "Not requested. Timer and reflection controls work without notifications."
        case .denied: "Notifications are off in System Settings. The timer still works in Three."
        case .authorized: "Notifications are allowed."
        case .provisional: "Notifications are delivered quietly."
        case .unsupported: "Notification authorization is unavailable for this app."
        }
    }
}

@MainActor @Observable
final class NotificationAccess {
    private(set) var state: NotificationAccessState = .unknown
    private(set) var error: String?
    private(set) var isRequesting = false
    @ObservationIgnored private let read: () async -> NotificationAccessState
    @ObservationIgnored private let request: () async throws -> Void
    @ObservationIgnored private var revision = 0

    convenience init() {
        self.init(read: {
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .notDetermined: .notDetermined
            case .denied: .denied
            case .authorized: .authorized
            case .provisional: .provisional
            case .ephemeral: .provisional
            @unknown default: .unsupported
            }
        }, request: {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        })
    }

    init(read: @escaping () async -> NotificationAccessState, request: @escaping () async throws -> Void) {
        self.read = read
        self.request = request
    }

    func refresh() async {
        revision += 1
        let expected = revision
        let result = await read()
        if revision == expected { state = result }
    }

    func requestFromUserAction() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        error = nil
        do { try await request() }
        catch { self.error = String(error.localizedDescription.prefix(400)) }
        await refresh()
    }
}

enum LoginItemState: Equatable {
    case enabled, requiresApproval, notRegistered, unsupported

    var text: String {
        switch self {
        case .enabled: "Enabled by macOS."
        case .requiresApproval: "Waiting for approval in System Settings → General → Login Items."
        case .notRegistered: "Off. Three starts only when you open it."
        case .unsupported: "Unavailable. Run Three from a complete app bundle in Applications."
        }
    }

    var isRequested: Bool { self == .enabled || self == .requiresApproval }
}

@MainActor @Observable
final class LoginItemControl {
    private(set) var state: LoginItemState
    private(set) var error: String?
    private(set) var isChanging = false
    @ObservationIgnored private let read: () -> LoginItemState
    @ObservationIgnored private let change: (Bool) async throws -> Void

    convenience init() {
        self.init(read: {
            guard Bundle.main.bundleURL.pathExtension == "app" else { return .unsupported }
            return switch SMAppService.mainApp.status {
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            case .notRegistered: .notRegistered
            case .notFound: .unsupported
            @unknown default: .unsupported
            }
        }, change: { enabled in
            if enabled { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
        })
    }

    init(read: @escaping () -> LoginItemState, change: @escaping (Bool) async throws -> Void) {
        self.read = read
        self.change = change
        state = read()
    }

    func refresh() { state = read() }

    func setEnabledFromUserAction(_ enabled: Bool) async {
        guard !isChanging else { return }
        refresh()
        guard state != .unsupported, enabled != state.isRequested else { return }
        isChanging = true
        defer { isChanging = false }
        error = nil
        do { try await change(enabled) }
        catch { self.error = String(error.localizedDescription.prefix(400)) }
        refresh()
    }
}

@MainActor @Observable
final class NativeSetup {
    let shortcut: GlobalMenuShortcut
    let notifications: NotificationAccess
    let login: LoginItemControl
    private(set) var onboardingDismissed: Bool
    @ObservationIgnored private let defaults: UserDefaults
    static let onboardingKey = "nativeSetupDismissed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = GlobalMenuShortcut(defaults: defaults)
        notifications = NotificationAccess()
        login = LoginItemControl()
        onboardingDismissed = defaults.object(forKey: Self.onboardingKey) as? Bool ?? false
    }

    func dismissOnboarding() {
        onboardingDismissed = true
        defaults.set(true, forKey: Self.onboardingKey)
    }

    func showOnboarding() { onboardingDismissed = false }

    func refresh() async {
        login.refresh()
        await notifications.refresh()
    }
}
