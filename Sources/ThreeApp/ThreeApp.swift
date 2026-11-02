import AppKit
import SwiftUI
import UserNotifications

@main
struct ThreeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Three", id: "main") {
            TodayView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 800)

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

/// `THREE_SNAPSHOT=/dir` renders the Today screen, reflection panel and menu popover to PNGs
/// with `ImageRenderer`, so layout can be checked without screen-recording rights.
/// Glass materials don't render offscreen; judge layout and type, not materials.
@MainActor
enum Snapshotter {
    static func scheduleIfRequested(model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["THREE_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let url = URL(fileURLWithPath: dir)
            write(TodayView().environment(model).frame(width: 1120, height: 800), to: url.appendingPathComponent("today.png"))
            write(ReflectionView(dismiss: {}).environment(model).padding(20).background(Theme.canvas),
                  to: url.appendingPathComponent("reflection.png"))
            write(DayTimelineGrid().environment(model).frame(width: 620).background(Theme.canvas),
                  to: url.appendingPathComponent("timeline.png"))
            write(MenuBarView().environment(model).background(Color(white: 0.12)), to: url.appendingPathComponent("menubar.png"))
            NSApp.terminate(nil)
        }
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
