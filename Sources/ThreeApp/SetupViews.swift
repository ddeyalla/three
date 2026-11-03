import AppKit
import ServiceManagement
import SwiftUI

struct SetupIntroduction: View {
    @Environment(AppModel.self) private var model
    let openConnect: () -> Void
    var openSetup: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Make Three yours").font(Typo.heading)
            Text("No permissions are required to plan and focus. Notifications can remind you when a block ends. The menu-bar shortcut needs no Accessibility access.")
                .font(Typo.meta).foregroundStyle(.secondary)
            Text("The optional CLI install and Codex MCP instructions are in Connect. MCP uses the bundled helper, so CLI installation is optional.")
                .font(Typo.meta).foregroundStyle(.secondary)
            HStack(spacing: Space.sm) {
                Button("Connect tools…", action: openConnect)
                if let openSetup {
                    Button("Permissions…", action: {
                        model.settingsTab = .setup
                        openSetup()
                    })
                }
                Spacer(minLength: 0)
                Button("Skip setup", action: model.setup.dismissOnboarding)
            }
            .buttonStyle(.glass)
            .font(Typo.body)
        }
    }

}

struct NativeSetupSettings: View {
    @Environment(AppModel.self) private var model
    let openConnect: () -> Void

    var body: some View {
        Form {
            if !model.setup.onboardingDismissed {
                Section { SetupIntroduction(openConnect: openConnect) }
            } else {
                Section { Button("Show setup guide", action: model.setup.showOnboarding) }
            }
            Section("Notifications") {
                NotificationAccessControls(access: model.setup.notifications)
                if let error = model.notificationError {
                    Text(error).font(Typo.meta).foregroundStyle(Theme.overrun)
                    Button("Retry timer reminder") { model.retryTimerNotification() }
                }
            }
            Section("Launch at login") {
                Toggle("Open Three when I log in", isOn: Binding(
                    get: { model.setup.login.state.isRequested },
                    set: { enabled in Task { await model.setup.login.setEnabledFromUserAction(enabled) } }))
                    .disabled(model.setup.login.isChanging || model.setup.login.state == .unsupported)
                Text(model.setup.login.state.text).font(Typo.meta).foregroundStyle(.secondary)
                if model.setup.login.state == .requiresApproval {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let error = model.setup.login.error {
                    Text(error).font(Typo.meta).foregroundStyle(Theme.overrun)
                }
            }
            ShortcutSettings(shortcut: model.setup.shortcut)
        }
        .formStyle(.grouped)
        .task { await model.setup.refresh() }
    }
}

private struct NotificationAccessControls: View {
    @Environment(AppModel.self) private var model
    let access: NotificationAccess

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(access.state.text).font(Typo.meta).foregroundStyle(.secondary)
            if access.state == .notDetermined || access.state == .unknown {
                Button("Allow timer notifications") {
                    Task {
                        await access.requestFromUserAction()
                        if access.state == .authorized || access.state == .provisional { model.retryTimerNotification() }
                    }
                }
                    .disabled(access.isRequesting)
            } else if access.state == .denied || access.state == .provisional {
                Button("Open notification settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            if let error = access.error { Text(error).font(Typo.meta).foregroundStyle(Theme.overrun) }
        }
        .task { await access.refresh() }
    }
}

private struct ShortcutSettings: View {
    let shortcut: GlobalMenuShortcut
    @State private var draft = MenuShortcut()
    @State private var enabled = true

    var body: some View {
        Section("Global menu-bar shortcut") {
            Toggle("Enable shortcut", isOn: $enabled)
            Picker("Key", selection: $draft.key) {
                ForEach(MenuShortcut.Key.allCases, id: \.self) { key in Text(key.title).tag(key) }
            }
            HStack(spacing: Space.md) {
                Toggle("⌘", isOn: $draft.command).accessibilityLabel("Command modifier")
                Toggle("⌥", isOn: $draft.option).accessibilityLabel("Option modifier")
                Toggle("⌃", isOn: $draft.control).accessibilityLabel("Control modifier")
                Toggle("⇧", isOn: $draft.shift).accessibilityLabel("Shift modifier")
            }
            .toggleStyle(.checkbox)
            Button("Apply \(draft.title)") { shortcut.apply(draft, enabled: enabled) }
                .disabled(!draft.isValid)
            Text("Default ⌥⌘Space. Letter keys use their physical US keyboard positions. Choose another combination if macOS or another app uses it.")
                .font(Typo.meta).foregroundStyle(.secondary)
            switch shortcut.status {
            case .registered:
                Text("\(shortcut.shortcut.title) opens Three's menu-bar controls from any app.")
                    .font(Typo.meta).foregroundStyle(.secondary)
            case .stopped:
                Text("Shortcut is off.").font(Typo.meta).foregroundStyle(.secondary)
            case .failed(let error):
                Text(error).font(Typo.meta).foregroundStyle(Theme.overrun)
                Button("Retry registration", action: shortcut.retry)
            }
        }
        .onAppear { draft = shortcut.shortcut; enabled = shortcut.isEnabled }
    }
}
