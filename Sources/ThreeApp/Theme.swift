import SwiftUI
import ThreeCore

enum Theme {
    static let canvas = Color(red: 0.043, green: 0.043, blue: 0.055)
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)
    static let hairline = Color.white.opacity(0.08)
    static let now = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let idle = Color(white: 0.6)

    /// Small mono caps used for stats lines, a nod to Session's log.
    static func stat(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension ThreeCore.Category {
    var color: Color { Color(hex: colorHex) }
}

enum Format {
    /// "45:00", "1:05:00", or "+04:12" once overrun.
    static func clock(_ seconds: TimeInterval) -> String {
        let over = seconds < 0
        let s = Int(abs(seconds).rounded(over ? .up : .down))
        let body = s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
        return over ? "+" + body : body
    }

    /// "1h 20m", "45m", "0m".
    static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// Every pressable thing gives a little under the finger.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
