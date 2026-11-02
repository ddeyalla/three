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
        host.layer?.cornerRadius = 20
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
            VStack(alignment: .leading, spacing: 2) {
                Text(model.runningTask?.task.title ?? "Focus block")
                    .font(.headline)
                    .lineLimit(1)
                Text("\(Format.duration(model.running?.elapsed(at: model.now) ?? 0)) focused")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    label("How did it go?")
                    Picker("How did it go?", selection: $outcome) {
                        Text("Done").tag(Outcome.done)
                        Text("Progress").tag(Outcome.progress)
                        Text("Stuck").tag(Outcome.stuck)
                    }
                }
                GridRow {
                    label("Focus")
                    Picker("Focus", selection: $rating) {
                        Text("Focused").tag(FocusRating.focused)
                        Text("Okay").tag(FocusRating.okay)
                        Text("Scattered").tag(FocusRating.scattered)
                    }
                }
                GridRow {
                    label("Next")
                    nextRow
                }
                GridRow {
                    label("Note")
                    TextField("Optional", text: $note)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            ErrorNote()

            HStack(spacing: 8) {
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .help("Close this and keep the timer as it is")
                Button("+15 min") {
                    model.extend(15)
                    dismiss()
                }
                Spacer()
                Button("Skip break") { finish(then: .next) }
                Button("Start break") { finish(then: .break) }
                    .buttonStyle(.borderedProminent)
                    .tint(model.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var nextRow: some View {
        if let next {
            HStack(spacing: 8) {
                Circle().fill(next.category.color).frame(width: 8, height: 8)
                if candidates.count > 1 {
                    Menu {
                        ForEach(candidates) { c in Button(c.task.title) { nextId = c.id } }
                    } label: {
                        Text(next.task.title).lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(next.task.title).lineLimit(1)
                }
                Spacer(minLength: 4)
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
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Adjust the next task")
            }
        } else {
            Text("Nothing left on today's plan.")
                .foregroundStyle(.secondary)
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

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
}
