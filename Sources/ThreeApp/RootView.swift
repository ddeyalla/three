import AppKit
import SwiftUI
import ThreeCore

/// Tasks on the left, the dial in the middle, the day's timeline on the right.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 0) {
            TasksPane()
                .frame(width: 320)
            NowPane()
                .frame(minWidth: 380, maxWidth: .infinity)
            DayTimelineView()
                .frame(width: 340)
        }
        .padding(.top, Space.lg)
        .frame(maxWidth: 1240)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if model.error != nil {
                ErrorNote()
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm + Space.hairline)
                    .frame(maxWidth: 560)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, Space.xl)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.error)
        .background(Backdrop())
        .background(InitialFocusSink())
        .onAppear { if ProcessInfo.processInfo.environment["THREE_OPEN"] == "settings" { openSettings() } }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1060, minHeight: 640)
    }
}

/// Capsules for today, the inbox, the week ahead, what's done and the tags,
/// then the list for whichever is chosen. Settings sits at the foot.
private struct TasksPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Space.lg)
                .padding(.bottom, Space.lg)
            Group {
                switch model.destination {
                case .today: TodayList()
                case .inbox: InboxList()
                case .upcoming: UpcomingList()
                case .done: DoneList()
                case .tags: TagsList()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(Typo.body)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
        }
    }

    /// One control for every view: words for the three lists, icons for what's done and the tags.
    private var header: some View {
        ChoiceCapsules(selection: Binding(get: { model.destination }, set: { model.destination = $0 }), options: [
            .init(.today, "Today"),
            .init(.inbox, model.inbox.isEmpty ? "Inbox" : "Inbox \(model.inbox.count)"),
            .init(.upcoming, "Upcoming"),
            .init(.done, "Done", symbol: "checkmark.circle"),
            .init(.tags, "Tags", symbol: "number"),
        ])
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// AppKit and SwiftUI give the first text field the cursor when the window first becomes key.
/// This takes that focus back once, so the window opens calm and a field only focuses when you
/// click it or press ⌘N. Later activations keep whatever you were typing in.
struct InitialFocusSink: NSViewRepresentable {
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
            invalidate()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, window.firstResponder is NSTextView else { return }
                window.makeFirstResponder(self)
            }
        }

        func invalidate() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }

    func makeNSView(context: Context) -> SinkView { SinkView() }
    func updateNSView(_ nsView: SinkView, context: Context) {}
    static func dismantleNSView(_ nsView: SinkView, coordinator: ()) { nsView.invalidate() }
}
