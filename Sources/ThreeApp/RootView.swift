import AppKit
import SwiftUI
import ThreeCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .background(Backdrop())
                .toolbar(removing: .sidebarToggle)
        }
        .toolbar(removing: .title)
        .background(InitialFocusSink())
        .onAppear { if ProcessInfo.processInfo.environment["THREE_OPEN"] == "settings" { openSettings() } }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1040, minHeight: 700)
    }

    @ViewBuilder private var detail: some View {
        switch model.destination {
        case .today: TodayView()
        case .inbox: InboxView()
        case .upcoming: UpcomingView()
        case .category(let id): CategoryView(categoryId: id)
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: Binding<Destination?>(get: { model.destination }, set: { if let d = $0 { model.destination = d } })) {
            Section {
                Label("Today", systemImage: "sun.max")
                    .badge(model.snapshot.tasks.filter { $0.task.status.isOpen }.count)
                    .tag(Destination.today)
                Label("Inbox", systemImage: "tray")
                    .badge(model.inbox.count)
                    .tag(Destination.inbox)
                Label("Upcoming", systemImage: "calendar")
                    .tag(Destination.upcoming)
            }
            Section("Categories") {
                ForEach(model.liveCategories) { c in
                    Label {
                        Text(c.name)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(c.color)
                            .imageScale(.small)
                    }
                    .tag(Destination.category(c.id))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }
}

/// AppKit and SwiftUI give the first text field the cursor when the window first becomes key.
/// This takes that focus back once, so the window opens calm and a field only focuses when you
/// click it or press ⌘N. Later activations keep whatever you were typing in.
private struct InitialFocusSink: NSViewRepresentable {
    final class SinkView: NSView {
        private var observer: NSObjectProtocol?
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, observer == nil else { return }
            window.initialFirstResponder = self
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reclaimOnce() }
            }
        }

        private func reclaimOnce() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, window.firstResponder is NSTextView else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    func makeNSView(context: Context) -> SinkView { SinkView() }
    func updateNSView(_ nsView: SinkView, context: Context) {}
}
