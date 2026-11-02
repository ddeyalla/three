import AppKit
import SwiftUI
import ThreeCore

/// A small floating glass panel, centred over the app. Never full-screen, never modal.
@MainActor
final class ReflectionPanelController {
    private unowned let model: AppModel
    private var panel: NSPanel?

    init(model: AppModel) { self.model = model }

    func show(_ presentation: ReflectionPresentation, takeFocus: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: ReflectionView(presentation: presentation, dismiss: { [weak self] in self?.model.closeReflection() })
            .environment(model))
        // Clip to the glass shape so no square corners or shadow show around it.
        host.wantsLayer = true
        host.layer?.cornerRadius = Radius.panel
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        panel.contentView = host
        panel.setContentSize(panel.contentView!.fittingSize)
        // Centred over the main window when it's on screen, else the middle of the screen.
        let main = NSApp.windows.first { $0.title == "Three" && $0.isVisible && !$0.isMiniaturized && $0.isOnActiveSpace }
        guard let area = main?.frame ?? NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        let target = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrameOrigin(NSPoint(x: target.x, y: target.y - (reduceMotion ? 0 : 10)))
        panel.alphaValue = 0
        if takeFocus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            // An automatic prompt must not take keystrokes from another app.
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(target)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func activate() {
        panel?.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .floating
        panel.title = "Reflection"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        return panel
    }
}

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct ReflectionView: View {
    @Environment(AppModel.self) private var model
    let presentation: ReflectionPresentation
    let dismiss: () -> Void

    @State private var outcome: Outcome = .progress
    @State private var rating: FocusRating = .okay
    @State private var note = ""
    @State private var nextId: String?
    @FocusState private var noteFocused: Bool

    init(presentation: ReflectionPresentation, dismiss: @escaping () -> Void) {
        self.presentation = presentation
        self.dismiss = dismiss
        _outcome = State(initialValue: presentation.session.outcome ?? .progress)
        _rating = State(initialValue: presentation.session.focusRating ?? .okay)
        _note = State(initialValue: presentation.session.note ?? "")
    }

    private var candidates: [TaskRow] {
        model.snapshot.tasks.filter { $0.task.status.isOpen && $0.id != presentation.session.taskId }
            + (outcome == .done ? [] : model.runningTask.map { [$0] } ?? [])
    }

    private var next: TaskRow? { candidates.first { $0.id == nextId } ?? candidates.first }

    private var breakMinutes: Int { (try? model.store.suggestedBreakMinutes()) ?? model.snapshot.preferences.shortBreakMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            header
            VStack(alignment: .leading, spacing: Space.lg) {
                question("How did it go?") {
                    ChoiceCapsules(selection: $outcome, options: [.init(.done, "Done"), .init(.progress, "Made progress"), .init(.stuck, "Stuck")])
                }
                question("How was your focus?") {
                    ChoiceCapsules(selection: $rating, options: [.init(.focused, "Focused"), .init(.okay, "Okay"), .init(.scattered, "Scattered")])
                }
                if !presentation.isSaved { question("Up next") { nextRow } }
                noteField
            }
            ErrorNote()
            footer
        }
        .font(Typo.body)
        .padding(Space.xl)
        .frame(width: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
        .background(InitialFocusSink())
        // The panel stays non-key until clicked so it never takes your typing; keep its text from dimming.
        .environment(\.controlActiveState, .key)
        .preferredColorScheme(.dark)
        .onChange(of: outcome) { model.reflectionActivity(note: note) }
        .onChange(of: rating) { model.reflectionActivity(note: note) }
        .onChange(of: nextId) { model.reflectionActivity(note: note) }
        .onChange(of: note) { model.reflectionActivity(note: note) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.hairline) {
                Text(presentation.task?.task.title ?? "Focus block")
                    .font(Typo.focus)
                    .lineLimit(1)
                Text("\(Format.duration(presentation.session.elapsed(at: model.now))) focused")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.sm)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(presentation.isSaved ? "Dismiss reminder and keep the saved answers (Esc)" : "Close and keep the timer as it is (Esc)")
            .accessibilityLabel("Close")
        }
    }

    private func question<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder private var nextRow: some View {
        if let next {
            HStack(spacing: Space.sm) {
                Circle().fill(next.category.color).frame(width: 6, height: 6)
                if candidates.count > 1 {
                    Menu {
                        ForEach(candidates) { c in Button(c.task.title) { nextId = c.id } }
                    } label: {
                        Text(next.task.title).lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Pick another task")
                } else {
                    Text(next.task.title).lineLimit(1)
                }
                Spacer(minLength: Space.xs)
                Text("\(next.task.blockMinutes)m")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Menu {
                    Button("Shorten by 15 min") {
                        model.perform { try model.store.updateTask(next.id, blockMinutes: max(5, next.task.blockMinutes - 15)) }
                    }
                    .disabled(next.task.blockMinutes <= 5)
                    if next.id != model.running?.taskId {
                        Button("Push to tomorrow") { model.perform { try model.store.pushToTomorrow(next.id) } }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Adjust the next task")
                .accessibilityLabel("Adjust next task")
            }
            .padding(.horizontal, Space.md)
            .frame(height: 36)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
        } else {
            Text("Nothing left on today's plan.")
                .foregroundStyle(.secondary)
        }
    }

    private var noteField: some View {
        TextField("Add a note (optional)", text: $note)
            .textFieldStyle(.plain)
            .focused($noteFocused)
            .focusEffectDisabled()
            .padding(.horizontal, Space.md)
            .frame(height: 36)
            .glassEffect(.regular.tint(.white.opacity(noteFocused ? 0.06 : 0)).interactive(), in: .rect(cornerRadius: Radius.card))
    }

    @ViewBuilder private var footer: some View {
        if presentation.isSaved {
            HStack(spacing: Space.sm) {
                Button("Dismiss", action: dismiss)
                    .buttonStyle(.glass)
                Spacer(minLength: Space.sm)
                Button("Save reflection") {
                    if model.perform({
                        try model.store.saveDeferredReflection(presentation.session.id, outcome: outcome, rating: rating, note: note)
                    }) { model.hideReflection() }
                }
                .buttonStyle(.primary(presentation.task?.category.color ?? Theme.idle))
                .keyboardShortcut(.defaultAction)
            }
        } else {
            liveFooter
        }
    }

    private var liveFooter: some View {
        GlassEffectContainer(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Button("15 more minutes") {
                    if model.perform({
                        try model.store.extend(minutes: 15, expectedSession: presentation.session)
                    }) { model.hideReflection() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Keep this block going")
                Spacer(minLength: Space.sm)
                Button("Skip break") { finish(then: next.map { .task($0.id) } ?? .stop) }
                    .buttonStyle(.glass)
                    .help(next.map { "Start \($0.task.title) now" } ?? "End this block")
                Button("Start \(breakMinutes)m break") { finish(then: .break) }
                    .buttonStyle(.primary(model.accent))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func finish(then continuation: FocusContinuation) {
        if model.perform({
            try model.store.finishFocus(outcome: outcome, rating: rating, note: note, markTaskDone: outcome == .done,
                                        expectedSession: presentation.session, continuation: continuation)
        }) { model.hideReflection() }
    }
}
