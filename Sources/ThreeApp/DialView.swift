import SwiftUI
import ThreeCore

/// A Time Timer face: the wedge is the time left, one turn is an hour.
/// While idle, dragging anywhere on the face sets the length in 5-minute steps.
struct DialView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 220
    /// 0 → 1 when a block starts: the wedge sweeps open to its length.
    @State private var sweep: Double = 1

    private var isIdle: Bool { model.running == nil }

    private var fraction: Double {
        let minutes = model.remaining.map { max(0, $0 / 60) } ?? Double(model.dialMinutes)
        return min(1, minutes / 60)
    }

    var body: some View {
        let face = size * 0.74
        ZStack {
            Canvas { ctx, canvas in drawTicks(ctx, canvas) }
            Circle()
                .fill(.clear)
                .frame(width: face, height: face)
                .glassEffect(.regular, in: .circle)
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
            model.dialOverride = min(60, max(5, model.dialMinutes + (direction == .increment ? 5 : -5)))
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            let dx = value.location.x - size / 2, dy = value.location.y - size / 2
            var degrees = atan2(dx, -dy) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            let minutes = Int((degrees / 30).rounded()) * 5
            model.dialOverride = min(60, max(5, minutes == 0 ? 60 : minutes))
        }
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
