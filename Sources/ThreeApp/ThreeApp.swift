import AppKit
import SwiftUI
import UserNotifications

@main
struct ThreeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Three", id: "main") {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1240, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Quick Add") {
                    if ![.today, .inbox, .upcoming].contains(model.destination) { model.destination = .inbox }
                    model.quickAddPending = true
                    model.quickAddRequest += 1
                }
                .keyboardShortcut("n")
            }
            CommandMenu("Go") {
                Button("Today") { model.destination = .today }.keyboardShortcut("1")
                Button("Inbox") { model.destination = .inbox }.keyboardShortcut("2")
                Button("Upcoming") { model.destination = .upcoming }.keyboardShortcut("3")
                Divider()
                Button("Done") { model.destination = .done }.keyboardShortcut("4")
                Button("Tags") { model.destination = .tags }.keyboardShortcut("5")
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    /// The menu bar keeps running the timer after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}
