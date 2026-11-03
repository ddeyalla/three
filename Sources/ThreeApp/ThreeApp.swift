import AppKit
import SwiftUI
import ThreeCore
import UserNotifications

@main
struct ThreeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model: AppModel
    @State private var workspace = WorkspaceLayout()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        delegate.prepare(model: model)
    }

    var body: some Scene {
        let open = openWindow, settings = openSettings
        let _ = delegate.setWindowActions(openMain: {
            open(id: "main")
            NSApp.activate()
        }, openSettings: {
            settings()
            NSApp.activate()
        })
        Window("Three", id: "main") {
            RootView()
                .environment(model)
                .environment(workspace)
                .onAppear(perform: startControllers)
        }
        .defaultSize(width: 1240, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Quick Add") {
                    model.requestQuickAdd()
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .keyboardShortcut("n")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                TodayMoveCommands(model: model)
            }
            CommandMenu("Focus") {
                Button("Start Focus") { model.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.running?.kind == .focus || model.selectedTask == nil)
                Button(model.running?.isPaused == true ? "Resume" : "Pause") { model.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(model.running?.kind != .focus)
                Button("Add 5 Minutes") { model.extend(5) }
                    .keyboardShortcut("+")
                    .disabled(model.running?.kind != .focus)
                Button("Finish Block") { model.finishEarly() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(model.running?.kind != .focus)
                Divider()
                UnblockMenu(model: model)
                Divider()
                Button("Show Focus Controls") { delegate.notch?.showControls() }
                    .disabled(delegate.notch?.preference.isEnabled != true || delegate.notch?.placement == nil
                              || model.running?.kind != .focus || model.reflectionPresentation != nil)
            }
            CommandGroup(before: .toolbar) {
                Menu("Arrange Panes") {
                    ForEach(WorkspacePane.allCases) { pane in
                        Menu(pane.title) {
                            PaneMoveCommands(layout: workspace, pane: pane)
                        }
                    }
                    Divider()
                    Button("Reset Pane Order") { workspace.reset() }
                        .disabled(workspace.panes == WorkspacePane.allCases)
                }
                Divider()
            }
            CommandMenu("Go") {
                Button("Today") { model.destination = .today }.keyboardShortcut("1")
                Button("Inbox") { model.destination = .inbox }.keyboardShortcut("2")
                Button("Upcoming") { model.destination = .upcoming }.keyboardShortcut("3")
                Divider()
                Button("Done") { model.destination = .done }.keyboardShortcut("4")
                Button("Tags") { model.destination = .tags }.keyboardShortcut("5")
                Button("History") { model.destination = .history }.keyboardShortcut("6")
                Button("Trends") { model.destination = .trends }.keyboardShortcut("7")
                Button("Day Review") { model.reviewingDay = model.dayCloses.first?.day ?? model.snapshot.day }
                Divider()
                Button("Review Saved Reflection") {
                    if let saved = model.deferredReflections.first { model.reviewReflection(saved) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.deferredReflections.isEmpty || model.reflectionPresentation != nil)
            }
        }

        Settings {
            SettingsView(notch: delegate.notch)
                .environment(model)
        }
    }

    private func startControllers() {
        delegate.startControllers()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var planning: PlanningController?
    var notch: NotchController?
    private var menuBar: MenuBarController?
    private var model: AppModel?
    private var openMain: () -> Void = {}
    private var openSettings: () -> Void = {}
    private var activationObserver: NSObjectProtocol?

    func prepare(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        planning = model.planning
        notch = NotchController(model: model, openMain: { [weak self] in self?.openMain() })
        menuBar = MenuBarController(model: model, openMain: { [weak self] in self?.openMain() },
                                    openSettings: { [weak self] in self?.openSettings() })
    }

    func setWindowActions(openMain: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.openMain = openMain
        self.openSettings = openSettings
    }

    func startControllers() {
        menuBar?.start()
        notch?.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        notch?.stop()
        menuBar?.stop()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        guard let planning else { return .terminateNow }
        Task {
            await planning.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        TimerNotificationRoute.registerCategories()
        startControllers()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.model?.setup.refresh() }
        }
        Task { await model?.setup.refresh() }
    }

    /// The menu bar keeps running the timer after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let action = response.actionIdentifier
        let identity = TimerNotificationIdentity(userInfo: response.notification.request.content.userInfo)
        await receiveTimerNotification(action: action, identity: identity)
    }

    private func receiveTimerNotification(action: String, identity: TimerNotificationIdentity?) {
        openMain()
        model?.handleTimerNotification(action: action, identity: identity)
    }
}
