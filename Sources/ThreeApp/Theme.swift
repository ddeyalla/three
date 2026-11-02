import SwiftUI
import ThreeCore

enum Theme {
    static let canvas = Color(red: 0.055, green: 0.055, blue: 0.065)
    /// Selected and running rows.
    static let rowFill = Color.white.opacity(0.06)
    static let rowHover = Color.white.opacity(0.03)
    static let now = Color(red: 1.0, green: 0.30, blue: 0.27)
    static let idle = Color(white: 0.55)
    static let overrun = Color(red: 1.0, green: 0.62, blue: 0.20)

    /// Exponential ease-out, for things arriving.
    static let arrive = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.7)
}

/// The six type roles from DESIGN.md. Every piece of text uses one; views never set a size or weight.
enum Typo {
    /// The time left, on the dial and in the menu bar.
    static let display = Font.system(size: 48, weight: .light).monospacedDigit()
    /// Page titles.
    static let title = Font.title.weight(.bold)
    /// The task the dial is about; the reflection panel's heading.
    static let focus = Font.title3.weight(.semibold)
    /// Section headings inside a page.
    static let heading = Font.headline
    /// Task titles, steps, notes, fields, menu rows, durations.
    static let body = Font.body
    /// The detail line under a task; timeline labels.
    static let meta = Font.subheadline
    /// Literal code only.
    static let code = Font.system(.subheadline, design: .monospaced)
}

/// The spacing scale from DESIGN.md.
enum Space {
    static let hairline: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let block: CGFloat = 8
    static let card: CGFloat = 12
    static let panel: CGFloat = 20
}

/// What the glass sits on: a dark canvas lit by the current task's colour, so the material has something to refract.
struct Backdrop: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.canvas
            RadialGradient(colors: [model.accent.opacity(0.22), model.accent.opacity(0.06), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 900)
            RadialGradient(colors: [model.accent.opacity(0.08), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 700)
        }
        .animation(.easeOut(duration: 0.4), value: model.accent)
        .ignoresSafeArea()
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
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }

    /// "Today", "Tomorrow", "Wednesday" within the week, else "Mon 16 Nov".
    static func dayName(_ day: DayKey, today: DayKey) -> String {
        let days = Calendar.current.dateComponents([.day], from: today.startDate, to: day.startDate).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2..<7: return day.startDate.formatted(.dateTime.weekday(.wide))
        default: return day.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "3:45 PM" later today, else "Sat 2:00 AM", so an end on another day never reads as today.
    static func until(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? time(date) : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
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
