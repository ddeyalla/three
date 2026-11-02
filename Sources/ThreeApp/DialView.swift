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
    /// The angle and lap of the drag so far, so crossing 12 o'clock winds on instead of jumping back.
    @State private var dragAngle: Double?
    @State private var dragLaps = 0

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
                .animation(isIdle && !reduceMotion ? .snappy(duration: 0.18) : nil, value: fraction)
            Circle()
                .fill(.clear)
                .frame(width: 22, height: 22)
                .glassEffect(.regular.tint(model.accent.opacity(0.4)), in: .circle)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(isIdle ? drag : nil)
        .onChange(of: model.running?.id) { _, id in
            guard id != nil, model.running?.kind == .focus, !reduceMotion else { return }
            sweep = 0
            withAnimation(Theme.arrive) { sweep = 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(isIdle ? "Block length" : "Time left")
        .accessibilityValue(isIdle ? "\(model.dialMinutes) minutes" : Format.clock(model.remaining ?? 0))
        .accessibilityAdjustableAction { direction in
            guard isIdle else { return }
            model.dialOverride = min(Self.maxMinutes, max(5, model.dialMinutes + (direction == .increment ? 5 : -5)))
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = value.location.x - size / 2, dy = value.location.y - size / 2
                var degrees = atan2(dx, -dy) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                if let last = dragAngle {
                    // Crossing 12 o'clock clockwise winds on an hour; anticlockwise unwinds one.
                    if last > 270 && degrees < 90 { dragLaps += 1 }
                    if last < 90 && degrees > 270 { dragLaps -= 1 }
                } else {
                    dragLaps = max(0, (model.dialMinutes - 1) / 60)
                }
                let maxLaps = Self.maxMinutes / 60
                dragLaps = min(maxLaps, max(0, dragLaps))
                dragAngle = degrees
                let minutes = dragLaps * 60 + Int((degrees / 30).rounded()) * 5
                model.dialOverride = min(Self.maxMinutes, max(5, minutes))
            }
            .onEnded { _ in dragAngle = nil }
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
