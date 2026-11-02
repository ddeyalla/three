import SwiftUI
import ThreeCore

/// A Time Timer face: the wedge is the time left in the current hour, one turn is an hour,
/// and each further hour is a ring around the face. While idle, dragging sets the length in
/// 5-minute steps; winding past 12 o'clock adds an hour, up to `maxMinutes`.
struct DialView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: CGFloat
    /// The longest session Settings allows.
    static let maxMinutes = 240
    /// Smallest and largest faces: below 240 the ticks crowd, above 400 the time under it reads as a caption.
    static let diameters: ClosedRange<CGFloat> = 240...400

    /// As wide as the Now pane allows inside its 24pt margins, and under half its height, so the
    /// task, time left and controls keep their room.
    static func diameter(fitting pane: CGSize) -> CGFloat {
        let fit = min(pane.width - 2 * Space.xl, (pane.height - 2 * Space.xl) * 0.48).rounded(.down)
        return min(diameters.upperBound, max(diameters.lowerBound, fit))
    }
    /// 0 → 1 when a block starts: the wedge sweeps open to its length.
    @State private var sweep: Double = 1
    @State private var dragAngle: Double?
    @State private var dragMinutes: Double?

    private var isIdle: Bool { model.running == nil }
    /// Only an idle dial with a task to start takes drags, focus and keys.
    private var acceptsInput: Bool { isIdle && model.selectedTask != nil }
    /// Nothing to time: an empty or finished day shows the face as a picture.
    private var isPicture: Bool { isIdle && model.selectedTask == nil }

    private var minutesLeft: Double {
        model.remaining.map { max(0, $0 / 60) } ?? Double(model.dialMinutes)
    }

    /// Whole hours beyond the one the wedge shows: 90 minutes is one ring and a half-face wedge.
    private var extraHours: Int { max(0, Int((minutesLeft / 60).rounded(.up)) - 1) }

    private var fraction: Double {
        min(1, (minutesLeft - Double(extraHours * 60)) / 60)
    }

    var body: some View {
        let face = size * 0.74
        ZStack {
            Canvas { ctx, canvas in drawTicks(ctx, canvas) }
            Circle()
                .fill(.clear)
                .frame(width: face, height: face)
                .glassEffect(.regular, in: .circle)
            ForEach(0..<extraHours, id: \.self) { i in
                let ring = face + size * 0.033 + CGFloat(i) * size * 0.025
                Circle()
                    .stroke(model.accent.opacity(model.running?.isPaused == true ? 0.4 : 0.9), lineWidth: 2)
                    .frame(width: ring, height: ring)
                    .transition(.opacity)
            }
            Wedge(fraction: fraction * sweep)
                .fill(model.accent.opacity(model.running?.isPaused == true ? 0.4 : 1))
                .frame(width: face, height: face)
                .animation(isIdle && dragAngle == nil && !reduceMotion ? .snappy(duration: 0.18) : nil, value: fraction)
            let hub = max(22, size * 0.07)
            Circle()
                .fill(.clear)
                .frame(width: hub, height: hub)
                .glassEffect(.regular.tint(model.accent.opacity(0.4)), in: .circle)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(acceptsInput ? drag : nil)
        .focusable(acceptsInput)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard acceptsInput else { return .ignored }
            adjust(press.key == .rightArrow || press.key == .upArrow ? 5 : -5)
            return .handled
        }
        .help(acceptsInput ? "Drag to adjust; wind past twelve for another hour. Arrow keys change five minutes."
              : isIdle ? "" : "Time left in this block")
        .onChange(of: model.selectedTask?.id) { resetDrag() }
        .onChange(of: model.running?.id) { _, id in
            resetDrag()
            guard id != nil, model.running?.kind == .focus, !reduceMotion else { return }
            sweep = 0
            withAnimation(Theme.arrive) { sweep = 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(isIdle ? "Block length" : "Time left")
        .accessibilityValue(isIdle ? "\(model.dialMinutes) minutes" : Format.clock(model.remaining ?? 0))
        .accessibilityAdjustableAction { direction in
            guard acceptsInput else { return }
            adjust(direction == .increment ? 5 : -5)
        }
        .accessibilityHidden(isPicture)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = value.location.x - size / 2, dy = value.location.y - size / 2
                var degrees = atan2(dx, -dy) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                if let last = dragAngle, let minutes = dragMinutes {
                    var delta = degrees - last
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }
                    let adjusted = min(Double(Self.maxMinutes), max(5, minutes + delta / 6))
                    dragMinutes = adjusted
                    model.dialOverride = Int((adjusted / 5).rounded()) * 5
                } else {
                    dragMinutes = Double(model.dialMinutes)
                }
                dragAngle = degrees
            }
            .onEnded { _ in resetDrag() }
    }

    private func adjust(_ minutes: Int) {
        model.dialOverride = min(Self.maxMinutes, max(5, model.dialMinutes + minutes))
    }

    private func resetDrag() {
        dragAngle = nil
        dragMinutes = nil
    }

    private func drawTicks(_ ctx: GraphicsContext, _ canvas: CGSize) {
        let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let outer = canvas.width / 2 - 1
        for i in 0..<60 {
            let major = i % 5 == 0
            let a = Double(i) / 60 * 2 * .pi - .pi / 2
            let inner = outer - canvas.width * (major ? 0.0375 : 0.0167)
            var p = Path()
            p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
            p.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
            ctx.stroke(p, with: .color(.white.opacity(major ? 0.42 : 0.14)),
                       style: StrokeStyle(lineWidth: major ? 1.5 : 1, lineCap: .round))
        }
    }
}

private struct Wedge: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard fraction > 0 else { return p }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addArc(center: c, radius: rect.width / 2, startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        p.closeSubpath()
        return p
    }
}
