import AppKit
import SwiftUI
import ThreeCore

/// A floating glass panel built like the reflection panel. It says a blocked app was hidden and offers Back to work,
/// and it is where a person opens one rule for five minutes: a reason, a wait they start, then a final click.
@MainActor
final class BlockOverlayController: NSObject, NSWindowDelegate {
    struct Subject: Equatable {
        let rule: BlockRule
        /// The app's name for an app rule; nil for a site.
        var appName: String?
        /// False once macOS has refused to hide the app.
        var hidden = true
    }

    enum Mode { case blocked, unblock }

    private unowned let model: AppModel
    private var panel: OverlayPanel?
    private(set) var subject: Subject?
    /// What the panel shows now; Unblock… switches it inside the view.
    private(set) var mode = Mode.blocked
    /// A blocked app was just hidden. macOS brings another app forward next; showing after that keeps the
    /// panel from losing key to it at once.
    private var pending: (id: UUID, subject: Subject, mode: Mode)?
    private var returnsToWorkApp = true

    init(model: AppModel) { self.model = model }

    var isVisible: Bool { panel?.isVisible == true }

    func present(_ subject: Subject, mode: Mode) {
        // A blocked app that keeps coming forward gets the same panel, unmoved, with nothing restarted.
        if isVisible, self.subject?.rule.id == subject.rule.id, mode == .blocked || self.mode == mode { return }
        if mode == .blocked {
            returnsToWorkApp = true
        } else if !isVisible && pending == nil {
            returnsToWorkApp = !NSApp.isActive
        }
        pending = nil
        guard mode == .blocked, !isVisible else { return show(subject, mode: mode) }
        let id = UUID()
        pending = (id, subject, mode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard self?.pending?.id == id else { return }
            self?.showPending()
        }
    }

    /// Whether the panel is showing, or about to show, for this rule.
    func isShowing(_ rule: BlockRule) -> Bool {
        (isVisible ? subject : pending?.subject)?.rule.id == rule.id
    }

    func setHidden(_ hidden: Bool, for rule: BlockRule) {
        if pending?.subject.rule.id == rule.id { pending?.subject.hidden = hidden }
        guard isVisible, mode == .blocked, var subject, subject.rule.id == rule.id, subject.hidden != hidden else { return }
        subject.hidden = hidden
        show(subject, mode: .blocked)
    }

    func otherAppActivated(_ app: NSRunningApplication) {
        guard app.isActive else { return }
        showPending()
    }

    private func showPending() {
        guard let pending else { return }
        self.pending = nil
        guard let policy = try? model.store.blockPolicy(),
              policy.blocked.contains(where: { $0.id == pending.subject.rule.id }) else { return }
        show(pending.subject, mode: pending.mode)
    }

    /// Closes the panel when its rule is no longer in force: blocking ended, it was opened, or it was removed.
    func reconcile(with state: BlockingState) {
        guard let subject = pending?.subject ?? subject, isVisible || pending != nil else { return }
        if !state.policy.blocked.contains(where: { $0.id == subject.rule.id }) { dismiss() }
    }

    func backToWork() {
        dismiss()
        if returnsToWorkApp { model.appBlocker.returnToWork() }
    }

    func dismiss() {
        pending = nil
        subject = nil
        panel?.orderOut(nil)
    }

    /// Opens the rule for five minutes. The Store decides whether that's still allowed; its refusal is returned.
    func grant(reason: String) -> String? {
        guard let subject else { return nil }
        do {
            _ = try model.store.requestBlockException(ruleId: subject.rule.id, reason: reason)
        } catch {
            return error.localizedDescription
        }
        dismiss()
        model.refreshBlocking()
        if subject.rule.bundleID != nil { model.appBlocker.release(subject.rule) }
        return nil
    }

    private func show(_ subject: Subject, mode: Mode) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let wasVisible = panel.isVisible
        self.subject = subject
        self.mode = mode
        let host = NSHostingView(rootView: BlockOverlayView(subject: subject, mode: mode, controller: self).environment(model))
        host.wantsLayer = true
        host.layer?.cornerRadius = Radius.panel
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        panel.contentView = host
        let size = host.fittingSize
        if wasVisible {
            fit(size)
        } else {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            guard let area = screen?.visibleFrame else { return }
            let target = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2 + area.height / 8)
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            panel.setFrame(NSRect(origin: NSPoint(x: target.x, y: target.y - (reduceMotion ? 0 : 10)), size: size), display: false)
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(target)
            }
        }
        // The person just tried to open this app, or chose Unblock, so the keyboard belongs here. A nonactivating key
        // panel hears no keys until Three asks to be active; the main window stays behind the app in front.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        let name = subject.appName ?? subject.rule.name
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: mode == .blocked ? "\(name) is hidden. Back to work, or unblock it for 5 minutes." : "Open \(name) for 5 minutes",
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    func beginUnblock() { mode = .unblock }

    /// Keeps the top edge still when the content changes height, as when Unblock swaps in its field.
    func fit(_ size: CGSize) {
        guard let panel, size.height > 0, panel.frame.size != size else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.title = "Blocked"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.backToWork() }
        return panel
    }

    /// Clicking into another app is going back to work, so the panel never traps anyone. A wait in progress is dropped.
    func windowDidResignKey(_ notification: Notification) {
        guard pending == nil else { return }
        dismiss()
    }
}

/// Esc anywhere in the panel means Back to work.
final class OverlayPanel: KeyablePanel {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

struct BlockOverlayView: View {
    @Environment(AppModel.self) private var model
    let subject: BlockOverlayController.Subject
    @State var mode: BlockOverlayController.Mode
    let controller: BlockOverlayController

    @State private var reason = ""
    @State private var wait: UnblockWait?
    @State private var error: String?
    @FocusState private var reasonFocused: Bool

    static let reasonLimit = 140

    private var blocking: BlockingState { model.blocking }
    private var name: String { subject.appName ?? subject.rule.name }
    private var accent: Color { blocking.policy.focus?.categoryColor.map(Color.init(hex:)) ?? Theme.idle }

    var body: some View {
        Group {
            switch mode {
            case .blocked: blocked
            case .unblock: unblock
            }
        }
        .font(Typo.body)
        .padding(Space.xl)
        .frame(width: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
        // Three usually isn't the frontmost app; keep the panel's text and controls from drawing as inactive.
        .environment(\.controlActiveState, .key)
        .preferredColorScheme(.dark)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { controller.fit($0) }
    }

    // MARK: Blocked

    private var blocked: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(hiddenLine)
                    .font(Typo.meta)
                    .foregroundStyle(.secondary)
                    .help(subject.hidden ? "\(name) is still open and nothing in it is lost. It's hidden until blocking ends." : "")
                HStack(spacing: Space.sm) {
                    if blocking.policy.focus != nil {
                        Circle().fill(accent).frame(width: 6, height: 6)
                    }
                    Text(blocking.policy.focus.map { $0.taskTitle ?? "Focus" } ?? "Focus hours")
                        .font(Typo.focus)
                        .lineLimit(2)
                }
                Text(timeLine)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: Space.sm) {
                if blocking.policy.strict {
                    Text("Unblocking is off for this task.")
                        .font(Typo.meta)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Unblock for 5 minutes…") {
                        controller.beginUnblock()
                        mode = .unblock
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.sm)
                Button("Back to work") { controller.backToWork() }
                    .buttonStyle(.primary(accent))
                    .keyboardShortcut(.defaultAction)
                    .help("Back to work (Return or Esc)")
            }
        }
    }

    private var hiddenLine: String {
        guard subject.hidden else { return "\(name) couldn't be hidden. Try switching away from it." }
        return "\(name) is hidden during \(blocking.owningFocus == nil ? "focus hours" : "this focus session")"
    }

    /// When blocking ends, which is what the person can plan around; never the timer's end in disguise.
    private var timeLine: String {
        guard let until = blocking.policy.until else { return "" }
        let end = Format.until(until, now: model.now)
        guard let focus = blocking.owningFocus else { return "Until \(end)" }
        switch focus.phase {
        case .paused: return "Paused · until \(end)"
        case .running: return "\(max(1, Int((until.timeIntervalSince(model.now) / 60).rounded(.up)))) min left · until \(end)"
        case .overrun: return "Until \(end)"
        }
    }

    // MARK: Unblock

    private var unblock: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.hairline) {
                Text("Open \(name) for 5 minutes")
                    .font(Typo.focus)
                    .lineLimit(2)
                Text(blocking.policy.focus == nil ? "What do you need it for? Three keeps your answer." : "What do you need it for? It's saved with this session.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                TextField("Reason", text: $reason)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Reason")
                    .focused($reasonFocused)
                    .focusEffectDisabled()
                    .disabled(wait != nil)
                    .onSubmit(startWait)
                    .onExitCommand { controller.backToWork() }
                    .padding(.horizontal, Space.md)
                    .frame(height: 36)
                    .glassEffect(.regular.tint(.white.opacity(reasonFocused ? 0.06 : 0)).interactive(),
                                 in: .rect(cornerRadius: Radius.card))
                    .onChange(of: reason) {
                        error = nil
                        if reason.count > Self.reasonLimit { reason = String(reason.prefix(Self.reasonLimit)) }
                    }
                Text(hint)
                    .font(Typo.meta)
                    .foregroundStyle(.secondary)
            }
            if let error {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.overrun)
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Space.sm) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    unblockButton
                }
                Spacer(minLength: Space.sm)
                Button("Back to work") { controller.backToWork() }
                    .buttonStyle(.primary(accent))
                    .help("Back to work (Esc)")
            }
        }
        .onAppear { DispatchQueue.main.async { reasonFocused = true } }
    }

    private var covering: BlockRule? { blocking.policy.coveringRule(for: subject.rule) }

    private var hint: String {
        if let covering { return "\(covering.name) also blocks this site, so opening \(name) alone wouldn't help." }
        if wait == nil { return "Write at least three words." }
        return blocking.policy.focus == nil ? "Saved when you unblock." : "Saved with this focus session when you unblock."
    }

    private var hasReason: Bool {
        reason.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count >= 3
    }

    private var waitLeft: TimeInterval? {
        wait?.remaining()
    }

    @ViewBuilder private var unblockButton: some View {
        if let left = waitLeft, left > 0 {
            Button("Unblock in \(Format.clock(left.rounded(.up)).dropFirst())") {}
                .buttonStyle(.glass)
                .monospacedDigit()
                .disabled(true)
        } else if waitLeft != nil {
            // No keyboard shortcut: holding Return through the wait must not open anything.
            Button("Unblock for 5 minutes") {
                guard wait?.remaining() == 0 else { return }
                error = controller.grant(reason: reason)
            }
            .buttonStyle(.glass)
        } else {
            Button("Start 20-second wait", action: startWait)
                .buttonStyle(.glass)
                .disabled(!hasReason || covering != nil)
                .help("Unblocking takes a reason and a 20-second wait, every time")
        }
    }

    private func startWait() {
        guard wait == nil, hasReason, covering == nil else { return }
        wait = UnblockWait()
    }
}

struct UnblockWait {
    private let deadline: ContinuousClock.Instant

    init(startedAt: ContinuousClock.Instant = .now) {
        deadline = startedAt.advanced(by: .seconds(20))
    }

    func remaining(at now: ContinuousClock.Instant = .now) -> TimeInterval {
        let parts = now.duration(to: deadline).components
        return max(0, Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }
}
