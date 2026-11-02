import AppKit
import SwiftUI
import ThreeCore

/// A small floating glass panel, centred over the app. Never full-screen, never modal.
@MainActor
final class ReflectionPanelController {
    private unowned let model: AppModel
    private var panel: NSPanel?

    init(model: AppModel) { self.model = model }

    var isVisible: Bool { panel?.isVisible == true }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: ReflectionView(dismiss: { [weak self] in self?.hide() })
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
        // Front, not key: never take keystrokes from whatever the user is typing in. A click makes it key.
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(target)
        }
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        return panel
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// AppKit hands the first text field the cursor when the panel turns key. Take it back at once,
    /// so a click on a choice doesn't light up the note. A click on the note still focuses it, since that click lands after this.
    override func becomeKey() {
        super.becomeKey()
        if firstResponder is NSTextView { makeFirstResponder(nil) }
    }
}

struct ReflectionView: View {
    @Environment(AppModel.self) private var model
    let dismiss: () -> Void

    @State private var outcome: Outcome = .progress
    @State private var rating: FocusRating = .okay
    @State private var note = ""
    @State private var nextId: String?
    @FocusState private var noteFocused: Bool

    private var candidates: [TaskRow] {
        model.snapshot.tasks.filter { $0.task.status.isOpen && $0.id != model.running?.taskId }
            + (outcome == .done ? [] : model.runningTask.map { [$0] } ?? [])
    }

    private var next: TaskRow? { candidates.first { $0.id == nextId } ?? candidates.first }

    private var breakMinutes: Int { (try? model.store.suggestedBreakMinutes()) ?? model.snapshot.preferences.shortBreakMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            header
            VStack(alignment: .leading, spacing: Space.lg) {
                question("How did it go?") {
                    Choices(selection: $outcome, options: [(.done, "Done"), (.progress, "Made progress"), (.stuck, "Stuck")])
                }
                question("How was your focus?") {
                    Choices(selection: $rating, options: [(.focused, "Focused"), (.okay, "Okay"), (.scattered, "Scattered")])
                }
                question("Up next") { nextRow }
                noteField
            }
            ErrorNote()
            footer
        }
        .font(Typo.body)
        .padding(Space.xl)
        .frame(width: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
        // The panel stays non-key until clicked so it never takes your typing; keep its text from dimming.
        .environment(\.controlActiveState, .key)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.hairline) {
                Text(model.runningTask?.task.title ?? "Focus block")
                    .font(Typo.focus)
                    .lineLimit(1)
                Text("\(Format.duration(model.running?.elapsed(at: model.now) ?? 0)) focused")
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
            .help("Close and keep the timer as it is (Esc)")
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

    private var footer: some View {
        GlassEffectContainer(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Button("15 more minutes") {
                    model.extend(15)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Keep this block going")
                Spacer(minLength: Space.sm)
                Button("Skip break") { finish(then: .next) }
                    .buttonStyle(.glass)
                    .help(next.map { "Start \($0.task.title) now" } ?? "End this block")
                Button("Start \(breakMinutes)m break") { finish(then: .break) }
                    .buttonStyle(.glassProminent)
                    .tint(model.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private enum Then { case `break`, next }

    private func finish(then: Then) {
        let nextTask = next
        model.perform {
            try model.store.finishFocus(outcome: outcome, rating: rating, note: note, markTaskDone: outcome == .done)
            switch then {
            case .break: try model.store.startBreak()
            case .next: if let nextTask { try model.store.startFocus(taskId: nextTask.id) }
            }
        }
        dismiss()
    }
}

/// Pick-one answers as glass capsules. The chosen one lightens; none of them is a prominent button.
private struct Choices<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        GlassEffectContainer(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                ForEach(options, id: \.0) { value, title in
                    let chosen = selection == value
                    Button { selection = value } label: {
                        Text(title)
                            .foregroundStyle(chosen ? .primary : .secondary)
                            .padding(.horizontal, Space.md)
                            .frame(height: 28)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(chosen ? .regular.tint(.white.opacity(0.15)).interactive() : .regular.interactive(), in: .capsule)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}
