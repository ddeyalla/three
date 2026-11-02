import SwiftUI
import ThreeCore

/// A Time Timer face: the wedge is the time left in the current hour, one turn is an hour,
/// and each further hour is a ring around the face. While idle, dragging sets the length in
/// 5-minute steps; winding past 12 o'clock adds an hour, up to `maxMinutes`.
struct DialView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 220
    /// The longest session Settings allows.
    static let maxMinutes = 240
    /// 0 → 1 when a block starts: the wedge sweeps open to its length.
    @State private var sweep: Double = 1
    @State private var dragAngle: Double?
    @State private var dragMinutes: Double?

    private var isIdle: Bool { model.running == nil }

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
                Circle()
                    .stroke(model.accent.opacity(model.running?.isPaused == true ? 0.4 : 0.9), lineWidth: 2)
                    .frame(width: face + 8 + CGFloat(i) * 6, height: face + 8 + CGFloat(i) * 6)
                    .transition(.opacity)
            }
            Wedge(fraction: fraction * sweep)
                .fill(model.accent.opacity(model.running?.isPaused == true ? 0.4 : 1))
                .frame(width: face, height: face)
                .animation(isIdle && dragAngle == nil && !reduceMotion ? .snappy(duration: 0.18) : nil, value: fraction)
            Circle()
                .fill(.clear)
                .frame(width: 22, height: 22)
                .glassEffect(.regular.tint(model.accent.opacity(0.4)), in: .circle)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(isIdle ? drag : nil)
        .focusable(isIdle)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard isIdle else { return .ignored }
            adjust(press.key == .rightArrow || press.key == .upArrow ? 5 : -5)
            return .handled
        }
        .help(isIdle ? "Drag to adjust; wind past twelve for another hour. Arrow keys change five minutes." : "Time left in this block")
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
            guard isIdle else { return }
            adjust(direction == .increment ? 5 : -5)
        }
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
            let inner = outer - (major ? 9 : 4)
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
