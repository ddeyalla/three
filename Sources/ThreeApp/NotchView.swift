import SwiftUI
import ThreeCore

/// Motion for opening and closing the surface. Short, critically damped springs: they settle
/// without overshooting the fixed panel, and retarget smoothly when interrupted mid-flight.
enum NotchMotion {
    static let expand = Animation.spring(duration: 0.3, bounce: 0)
    static let collapse = Animation.spring(duration: 0.2, bounce: 0)

    static func animation(expanding: Bool) -> Animation { expanding ? expand : collapse }
}

/// The notch silhouette, drawn inside the fixed panel. The neck (notch plus wings) has concave ears
/// where it meets the top edge. Expanding never widens the neck: a body grows down from under the
/// menu bar, wider than the neck, joined to it by concave shoulders.
struct NotchShape: Shape {
    /// 0 collapsed, 1 expanded.
    var progress: CGFloat
    let layout: NotchLayout

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    static let collapsedRadius = Radius.block + Space.xs
    static let expandedRadius = Radius.panel

    func path(in rect: CGRect) -> Path {
        let p = min(max(progress, 0), 1)
        let ear = NotchLayout.ear
        let neck = layout.collapsedSize
        let full = layout.expandedSize
        let left = rect.midX - neck.width / 2
        let right = rect.midX + neck.width / 2
        let neckBottom = rect.minY + neck.height

        // Neck: its rounded bottom corners square off as the body takes over beneath it.
        let neckRadius = min(Self.collapsedRadius * (1 - p), neck.width / 2, neck.height - ear)
        var shape = Path()
        shape.move(to: CGPoint(x: left - ear, y: rect.minY))
        shape.addQuadCurve(to: CGPoint(x: left, y: rect.minY + ear), control: CGPoint(x: left, y: rect.minY))
        shape.addLine(to: CGPoint(x: left, y: neckBottom - neckRadius))
        shape.addQuadCurve(to: CGPoint(x: left + neckRadius, y: neckBottom), control: CGPoint(x: left, y: neckBottom))
        shape.addLine(to: CGPoint(x: right - neckRadius, y: neckBottom))
        shape.addQuadCurve(to: CGPoint(x: right, y: neckBottom - neckRadius), control: CGPoint(x: right, y: neckBottom))
        shape.addLine(to: CGPoint(x: right, y: rect.minY + ear))
        shape.addQuadCurve(to: CGPoint(x: right + ear, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        shape.closeSubpath()

        let bodyHeight = (full.height - neck.height) * p
        guard bodyHeight > 0 else { return shape }
        // Body: starts exactly at the bottom of the menu bar, never inside it.
        let width = neck.width + (full.width - neck.width) * p
        let side = (width - neck.width) / 2
        let bottomRadius = min(Self.collapsedRadius + (Self.expandedRadius - Self.collapsedRadius) * p,
                               width / 2, bodyHeight / 2)
        let topRadius = min(bottomRadius, side, bodyHeight / 2)
        let body = CGRect(x: rect.midX - width / 2, y: neckBottom, width: width, height: bodyHeight)
        shape = shape.union(UnevenRoundedRectangle(topLeadingRadius: topRadius, bottomLeadingRadius: bottomRadius,
                                                   bottomTrailingRadius: bottomRadius, topTrailingRadius: topRadius,
                                                   style: .continuous).path(in: body))
        // Shoulders: concave fillets where the neck meets the flat top of a wider body.
        let shoulder = min(NotchLayout.shoulder * p, max(0, side - topRadius), neck.height - ear)
        guard shoulder > 0 else { return shape }
        var fillets = Path()
        for (x, outward) in [(left, -shoulder), (right, shoulder)] {
            fillets.move(to: CGPoint(x: x, y: neckBottom - shoulder))
            fillets.addQuadCurve(to: CGPoint(x: x + outward, y: neckBottom), control: CGPoint(x: x, y: neckBottom))
            fillets.addLine(to: CGPoint(x: x, y: neckBottom))
            fillets.closeSubpath()
        }
        return shape.union(fillets)
    }
}

/// Dynamic-Island-style focus surface. Collapsed it extends the hardware notch with two wings:
/// progress on the left, time left on the right. Hovering grows it downward into the controls.
struct NotchView: View {
    @Environment(AppModel.self) private var model
    let commands: NotchCommands
    let surface: NotchSurface
    let dismiss: () -> Void

    private var expanded: Bool { surface.isExpanded }
    private var layout: NotchLayout { surface.layout }

    var body: some View {
        let shape = NotchShape(progress: expanded ? 1 : 0, layout: layout)
        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .shadow(color: .black.opacity(expanded ? 0.35 : 0), radius: Space.md, y: Space.xs)
            if let session = model.running, session.kind == .focus {
                VStack(spacing: 0) {
                    wings(session)
                        .frame(height: layout.notchHeight)
                    if expanded {
                        controls(session)
                            .padding(.horizontal, Space.lg)
                            .padding(.bottom, Space.md)
                            .frame(width: layout.expandedSize.width)
                            .frame(maxHeight: .infinity)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
                // Same frame as the shape, so the clip lines up with what is drawn.
                .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .top)
                .clipShape(shape)
            }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .font(Typo.body)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Three focus controls")
    }

    private func wings(_ session: Session) -> some View {
        let remaining = session.remaining(at: model.now)
        let tint = remaining < 0 ? Theme.overrun : model.runningTask?.category.color ?? Theme.idle
        return HStack(spacing: 0) {
            ProgressRing(progress: progress(session), tint: tint, paused: session.isPaused)
                .frame(width: layout.wingWidth)
            Spacer(minLength: layout.notchWidth)
            Text(Format.clock(remaining))
                .font(Typo.heading)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(remaining < 0 ? Theme.overrun : session.isPaused ? .secondary : .primary)
                .opacity(expanded ? 0 : 1)
                .frame(width: layout.wingWidth)
                .accessibilityLabel("\(Format.clock(remaining)) \(session.isPaused ? "paused" : "left")")
        }
        .frame(width: layout.collapsedSize.width)
    }

    private func controls(_ session: Session) -> some View {
        let remaining = session.remaining(at: model.now)
        return VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.hairline) {
                    Text(model.runningTask?.task.title ?? "Focus block")
                        .font(Typo.focus)
                        .lineLimit(1)
                        .help(model.runningTask?.task.title ?? "Focus block")
                    Text(status(session, remaining: remaining))
                        .font(Typo.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.xs)
                Text(Format.clock(remaining))
                    .font(Typo.title)
                    .monospacedDigit()
                    .foregroundStyle(remaining < 0 ? Theme.overrun : .primary)
            }
            HStack(spacing: Space.sm) {
                Button(session.isPaused ? "Resume" : "Pause",
                       systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                    commands.perform(.pauseResume, sessionID: session.id)
                }
                .help(session.isPaused ? "Resume this focus block" : "Pause this focus block")
                Button("Finish", systemImage: "checkmark") { commands.perform(.finish, sessionID: session.id) }
                    .help("Finish this block and open reflection")
                Spacer(minLength: Space.xs)
                Button("Open Three", systemImage: "macwindow") {
                    commands.perform(.openMain, sessionID: session.id)
                }
                .labelStyle(.iconOnly)
                .help("Open Three’s main window")
                Button("Hide for this block", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.cancelAction)
                    .help("Hide for this focus block (Esc)")
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
            // The panel is rarely key; without this the controls render in the dimmed inactive style.
            .environment(\.controlActiveState, .key)
            .disabled(model.reflectionPresentation != nil)
        }
    }

    private func status(_ session: Session, remaining: TimeInterval) -> String {
        if let error = model.error { return error }
        let category = model.runningTask?.category.name ?? "Focus"
        let state = session.isPaused ? "Paused" : remaining < 0 ? "Overrun" : "Remaining"
        return "\(category) · \(state)"
    }

    private func progress(_ session: Session) -> Double {
        guard session.plannedSeconds > 0 else { return 0 }
        return min(1, session.elapsed(at: model.now) / Double(session.plannedSeconds))
    }
}

/// Elapsed share of the block, as a small ring in the category colour.
private struct ProgressRing: View {
    let progress: Double
    let tint: Color
    let paused: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if paused {
                Image(systemName: "pause.fill")
                    .imageScale(.small)
                    .font(Typo.meta)
                    .foregroundStyle(tint)
                    .scaleEffect(0.7)
            }
        }
        .frame(width: Space.lg, height: Space.lg)
        .opacity(paused ? 0.7 : 1)
        .accessibilityLabel("\(Int(progress * 100)) percent of the block done")
    }
}

struct NotchSettingsSection: View {
    @Environment(AppModel.self) private var model
    let controller: NotchController

    var body: some View {
        @Bindable var preference = controller.preference
        Section {
            Toggle("Notch focus controls", isOn: $preference.isEnabled)
            Button("Show Controls", action: controller.showControls)
                .disabled(!preference.isEnabled || controller.placement == nil
                          || model.running?.kind != .focus || model.reflectionPresentation != nil)
        } footer: {
            Text(controller.availabilityText)
                .font(Typo.meta)
                .foregroundStyle(.secondary)
        }
        .font(Typo.body)
    }
}
