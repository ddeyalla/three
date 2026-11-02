import SwiftUI
import ThreeCore

/// A Time Timer-style face: the coloured wedge is the time left, one turn is an hour.
/// While idle, dragging anywhere on the face sets the length in 5-minute steps.
struct DialView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 280

    private var minutesShown: Double {
        if let remaining = model.remaining { return max(0, remaining / 60) }
        return Double(model.dialMinutes)
    }

    private var isOverrun: Bool { (model.remaining ?? 1) <= 0 }
    private var isIdle: Bool { model.running == nil }

    var body: some View {
        let fraction = min(1, minutesShown / 60)
        ZStack {
            Canvas { ctx, canvasSize in
                drawTicks(ctx, canvasSize)
            }
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: size * 0.64, height: size * 0.64)
            Wedge(fraction: fraction)
                .fill(model.accent.gradient.opacity(model.running?.isPaused == true ? 0.45 : 1))
                .frame(width: size * 0.64, height: size * 0.64)
                .animation(isIdle && !reduceMotion ? .snappy(duration: 0.18) : nil, value: fraction)
            Hand(fraction: fraction, length: size * 0.39)
                .stroke(model.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: size, height: size)
                .animation(isIdle && !reduceMotion ? .snappy(duration: 0.18) : nil, value: fraction)
            Circle()
                .fill(.clear)
                .frame(width: 30, height: 30)
                .glassEffect(.regular, in: .circle)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(isIdle ? drag : nil)
        .accessibilityElement()
        .accessibilityLabel(isIdle ? "Session length" : "Time left")
        .accessibilityValue(isIdle ? "\(model.dialMinutes) minutes" : Format.clock(model.remaining ?? 0))
        .accessibilityAdjustableAction { direction in
            guard isIdle else { return }
            let step = direction == .increment ? 5 : -5
            model.dialOverride = min(120, max(5, model.dialMinutes + step))
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            let c = CGPoint(x: size / 2, y: size / 2)
            let dx = value.location.x - c.x, dy = value.location.y - c.y
            var degrees = atan2(dx, -dy) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            let minutes = Int((degrees / 6 / 5).rounded()) * 5
            model.dialOverride = min(60, max(5, minutes == 0 ? 60 : minutes))
        }
    }

    private func drawTicks(_ ctx: GraphicsContext, _ canvasSize: CGSize) {
        let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let outer = canvasSize.width / 2 - 2
        for i in 0..<60 {
            let major = i % 5 == 0
            let a = Double(i) / 60 * 2 * .pi - .pi / 2
            let inner = outer - (major ? 16 : 8)
            var p = Path()
            p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
            p.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
            ctx.stroke(p, with: .color(.white.opacity(major ? 0.7 : 0.25)),
                       style: StrokeStyle(lineWidth: major ? 2.5 : 1.2, lineCap: .round))
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

private struct Hand: Shape {
    var fraction: Double
    var length: CGFloat
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let a = fraction * 2 * .pi - .pi / 2
        var p = Path()
        p.move(to: c)
        p.addLine(to: CGPoint(x: c.x + cos(a) * length, y: c.y + sin(a) * length))
        return p
    }
}
