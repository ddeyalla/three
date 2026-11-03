import AppKit
import SwiftUI
import ThreeCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WorkspaceView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if model.error != nil {
                ErrorNote()
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm + Space.hairline)
                    .frame(maxWidth: 560)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, Space.xl)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.error)
        .background(Backdrop())
        .background(InitialFocusSink())
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                if model.hasRecoveryNotice {
                    RecoveryEntry(controller: model.recovery, review: model.reviewRecovery)
                        .padding(.horizontal, Space.lg)
                        .padding(.top, Space.md)
                        .frame(maxWidth: 680)
                }
                if !model.setup.onboardingDismissed {
                    SetupIntroduction(openConnect: {
                        model.settingsTab = .connect
                        openSettings()
                    }, openSetup: { openSettings() })
                    .padding(Space.lg)
                    .frame(maxWidth: 680)
                }
            }
        }
        .onAppear {
            let open = ProcessInfo.processInfo.environment["THREE_OPEN"]
            if open == "blocking" { model.settingsTab = .blocking }
            if open == "settings" || open == "blocking" { openSettings() }
        }
        .preferredColorScheme(.dark)
        // Recovery review keeps priority: it shows first whenever both are requested.
        .sheet(isPresented: Binding(get: { model.reviewingRecovery || model.reviewSection != nil }, set: {
            if !$0 { model.reviewingRecovery = false; model.closeReview() }
        })) {
            if model.reviewingRecovery {
                RecoveryReviewView(controller: model.recovery, dismiss: { model.reviewingRecovery = false })
            } else {
                ReviewSheet()
            }
        }
        .frame(minWidth: 1060, minHeight: 640)
    }
}

/// Capsules for today, the week ahead, the inbox, what's done and the tags,
/// then the list for whichever is chosen. Review and Settings sit at the foot.
struct TasksPane: View {
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
            HStack(spacing: Space.lg) {
                Button { model.openReview(.day) } label: {
                    Label("Review", systemImage: "chart.bar.xaxis")
                }
                .help("Day review, history and trends (⌘6)")
                Spacer()
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
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
        ChoiceCapsules(selection: Binding(get: { model.destination }, set: { model.destination = $0 }),
                       options: Destination.ordered.map { .init($0, $0.title, symbol: $0.capsuleSymbol) })
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Destination {
    /// Words for the three lists, icons for what's done and the tags.
    var capsuleSymbol: String? {
        switch self {
        case .done: "checkmark.circle"
        case .tags: "number"
        case .today, .upcoming, .inbox: nil
        }
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
