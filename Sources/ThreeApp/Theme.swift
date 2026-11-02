import SwiftUI
import ThreeCore

enum Theme {
    static let canvas = Color(white: 0.075)
    /// Selected and running rows.
    static let rowFill = Color.white.opacity(0.06)
    static let rowHover = Color.white.opacity(0.03)
    static let now = Color(red: 1.0, green: 0.30, blue: 0.27)
    static let idle = Color(white: 0.55)
    static let overrun = Color(red: 1.0, green: 0.62, blue: 0.20)

    /// Exponential ease-out, for things arriving.
    static let arrive = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.7)
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
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "4:35 → 5:20 PM", dropping the first period when both share it.
    static func span(_ start: Date, _ end: Date) -> String {
        let a = time(start), b = time(end)
        let suffixes = [" AM", " PM", "\u{202F}AM", "\u{202F}PM"]
        if let s = suffixes.first(where: { a.hasSuffix($0) && b.hasSuffix($0) }) {
            return "\(a.dropLast(s.count)) → \(b)"
        }
        return "\(a) → \(b)"
    }
}
