import AppKit
import SwiftUI
import ThreeCore

/// A small floating glass panel at the top of the screen. Never full-screen, never modal.
@MainActor
final class ReflectionPanelController {
    private unowned let model: AppModel
    private var panel: NSPanel?

    init(model: AppModel) { self.model = model }

    var isVisible: Bool { panel?.isVisible == true }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: ReflectionView(dismiss: { [weak self] in self?.hide() })
            .environment(model))
        panel.setContentSize(panel.contentView!.fittingSize)
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let target = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 12)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrameOrigin(NSPoint(x: target.x, y: target.y + (reduceMotion ? 0 : 12)))
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
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
}

struct ReflectionView: View {
    @Environment(AppModel.self) private var model
    let dismiss: () -> Void

    @State private var outcome: Outcome = .progress
    @State private var rating: FocusRating = .okay
    @State private var note = ""
    @State private var nextId: String?

    private var candidates: [TaskRow] {
        model.snapshot.tasks.filter { $0.task.status.isOpen && $0.id != model.running?.taskId }
            + (outcome == .done ? [] : model.runningTask.map { [$0] } ?? [])
    }

    private var next: TaskRow? { candidates.first { $0.id == nextId } ?? candidates.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.runningTask?.task.title ?? "Focus block")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text("\(Format.duration(model.running?.elapsed(at: model.now) ?? 0).uppercased()) FOCUSED")
                    .font(Theme.stat(10))
                    .foregroundStyle(Theme.secondary)
            }

            question("How did it go?") {
                ForEach([(Outcome.done, "Done"), (.progress, "Made progress"), (.stuck, "Stuck")], id: \.0) { value, label in
                    Chip(label: label, selected: outcome == value, color: model.accent) { outcome = value }
                }
            }

            question("Focus?") {
                ForEach([(FocusRating.focused, "🎯 Focused"), (.okay, "🙂 Okay"), (.scattered, "🌀 Scattered")], id: \.0) { value, label in
                    Chip(label: label, selected: rating == value, color: model.accent) { rating = value }
                }
            }

            question("What's next?") {
                if let next {
                    HStack(spacing: 8) {
                        Circle().fill(next.category.color).frame(width: 8, height: 8)
                        Text("\(next.task.title) · \(next.task.blockMinutes)m")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if candidates.count > 1 {
                            Menu("Switch") {
                                ForEach(candidates) { c in Button(c.task.title) { nextId = c.id } }
                            }
                            .menuStyle(.button)
                            .fixedSize()
                        }
                        Button("−15m") {
                            model.perform { try model.store.updateTask(next.id, blockMinutes: max(5, next.task.blockMinutes - 15)) }
                        }
                        .disabled(next.task.blockMinutes <= 5)
                        if next.id != model.running?.taskId {
                            Button("Tomorrow") { model.perform { try model.store.pushToTomorrow(next.id) } }
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                } else {
                    Text("Nothing left on today's plan.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
            }

            TextField("Note (optional)", text: $note)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))

            HStack(spacing: 8) {
                Button { finish(then: .break) } label: { Text("Start break").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent)
                    .tint(model.accent)
                Button { finish(then: .next) } label: { Text("Skip break").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                Button {
                    model.extend(15)
                    dismiss()
                } label: { Text("+15 min").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .padding(22)
        .frame(width: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .preferredColorScheme(.dark)
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

    private func question<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.stat(10))
                .foregroundStyle(Theme.tertiary)
            HStack(spacing: 8) { content() }
        }
    }
}

private struct Chip: View {
    let label: String
    let selected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.primary : Theme.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(selected ? .regular.tint(color.opacity(0.35)) : .regular, in: .capsule)
        }
        .buttonStyle(PressableStyle())
    }
}
