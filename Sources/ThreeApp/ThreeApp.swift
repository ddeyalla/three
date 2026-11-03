import AppKit
import SwiftUI
import ThreeCore
import UserNotifications

@main
struct ThreeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()
    @State private var workspace = WorkspaceLayout()
    @State private var notch: NotchController?
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
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
                Button("Show Focus Controls") { notch?.showControls() }
                    .disabled(notch?.preference.isEnabled != true || notch?.placement == nil
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
            SettingsView(notch: notch)
                .environment(model)
        }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            MenuBarLabel().environment(model)
                .onAppear(perform: startControllers)
        }
        .menuBarExtraStyle(.window)
    }

    private func startControllers() {
        delegate.planning = model.planning
        guard notch == nil else { return }
        let open = openWindow
        let controller = NotchController(model: model, openMain: {
            open(id: "main")
            NSApp.activate()
        })
        notch = controller
        delegate.notch = controller
        controller.start()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var planning: PlanningController?
    var notch: NotchController?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        notch?.stop()
        guard let planning else { return .terminateNow }
        Task {
            await planning.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    /// The menu bar keeps running the timer after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}
