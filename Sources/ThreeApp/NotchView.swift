import SwiftUI
import ThreeCore

/// The notch silhouette: concave ears where it meets the top edge, rounded bottom corners.
/// `ear` insets the body on each side; the ears flare out into that inset.
struct NotchShape: Shape {
    var ear: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottomRadius) }
        set { ear = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, (rect.width - ear * 2) / 2, rect.height - ear)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
                          control: CGPoint(x: rect.minX + ear, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear + radius, y: rect.maxY),
                          control: CGPoint(x: rect.minX + ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - radius),
                          control: CGPoint(x: rect.maxX - ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        path.closeSubpath()
        return path
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
        let size = expanded ? layout.expandedSize : layout.collapsedSize
        let ear = NotchLayout.ear
        ZStack(alignment: .top) {
            NotchShape(ear: ear, bottomRadius: expanded ? Radius.panel : Radius.block + Space.xs)
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
                            .frame(maxHeight: .infinity)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
                .padding(.horizontal, ear)
            }
        }
        .frame(width: size.width + ear * 2, height: size.height)
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
                .frame(width: NotchLayout.wingWidth)
            Spacer(minLength: layout.notchWidth)
            Text(Format.clock(remaining))
                .font(Typo.heading)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(remaining < 0 ? Theme.overrun : session.isPaused ? .secondary : .primary)
                .opacity(expanded ? 0 : 1)
                .frame(width: NotchLayout.wingWidth)
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
