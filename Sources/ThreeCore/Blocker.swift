import Foundation

// The distraction blocker's domain: what can be blocked, when, and the one policy every process derives from it.
// Nothing here touches the database or the clock; the Store and the native host pass `now` and a calendar in.

public enum BlockError: LocalizedError, Equatable {
    case invalidDomain(DomainProblem)
    case invalidApp(String)
    case protectedApp(String)
    case invalidHours(String)
    case protectionActive(until: Date?)
    case strictSession
    case notBlocking
    case noSuchRule(String)
    case noSuchWindow(String)
    case missingReason

    public var errorDescription: String? {
        switch self {
        case .invalidDomain(let problem): problem.message
        case .invalidApp(let why), .invalidHours(let why): why
        case .protectedApp(let id): "\(id) can't be blocked. Three never blocks itself or the parts of macOS you need to get around."
        case .protectionActive(let until):
            "Blocking is on\(until.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""). Rules and focus hours can only be loosened while it's off."
        case .strictSession: "This is a strict session, so nothing can be unblocked until it ends."
        case .notBlocking: "Nothing is blocked right now."
        case .noSuchRule(let id): "No block rule matches \"\(id)\"."
        case .noSuchWindow(let id): "No focus hours match \"\(id)\"."
        case .missingReason: "Say in a few words why you need it."
        }
    }
}

// MARK: Targets

/// Why text isn't a blockable site. Callers branch on the case; `pathRule` carries the whole site to offer instead.
public enum DomainProblem: Equatable, Sendable {
    case empty, notWeb, credentials, ipAddress, incomplete, malformed
    case pathRule(suggestion: BlockDomain?)

    var message: String {
        switch self {
        case .empty, .malformed: "Enter a website like example.com."
        case .notWeb: "Only web addresses (http or https) can be blocked."
        case .credentials: "Leave out the user name and password."
        case .ipAddress: "Three blocks websites by name, not IP address."
        case .incomplete: "Enter a full website name, like example.com."
        case .pathRule(let suggestion): "Blocking part of a site comes later." + (suggestion.map { " Block \($0) instead?" } ?? "")
        }
    }
}

/// A site to block, with its subdomains: lowercase ASCII (punycode), no `www.`, at least two labels.
/// There is no public-suffix list on macOS, so `co.uk` parses; blocking it is the user's call.
public struct BlockDomain: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(parsing input: String) throws {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw BlockError.invalidDomain(.empty) }
        if !text.contains("://") {
            if text.hasSuffix("/") { text.removeLast() }
            if let cut = text.firstIndex(where: { "/?#".contains($0) }) {
                throw BlockError.invalidDomain(.pathRule(suggestion: try? BlockDomain(parsing: String(text[..<cut]))))
            }
            if text.hasPrefix("*.") { text.removeFirst(2) }
            text = "https://" + text
        }
        guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased() else {
            throw BlockError.invalidDomain(.malformed)
        }
        guard scheme == "http" || scheme == "https" else { throw BlockError.invalidDomain(.notWeb) }
        guard parts.user == nil, parts.password == nil else { throw BlockError.invalidDomain(.credentials) }
        // encodedHost is IDNA ASCII ("bücher.de" → "xn--bcher-kva.de"); URL.host() percent-encodes instead.
        guard var host = parts.encodedHost?.lowercased(), !host.isEmpty else { throw BlockError.invalidDomain(.malformed) }
        guard !host.hasPrefix("[") else { throw BlockError.invalidDomain(.ipAddress) }
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("*.") { host.removeFirst(2) }
        if host.hasPrefix("www.") { host.removeFirst(4) }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253, labels.allSatisfy(BlockDomain.isValidLabel) else { throw BlockError.invalidDomain(.malformed) }
        // A top-level domain is never all digits, so this catches IPv4 and its shorthand forms.
        guard !labels.last!.allSatisfy(\.isNumber) else { throw BlockError.invalidDomain(.ipAddress) }
        guard labels.count >= 2, labels.last != "localhost" else { throw BlockError.invalidDomain(.incomplete) }
        rawValue = host
    }

    private static func isValidLabel(_ label: Substring) -> Bool {
        (1...63).contains(label.count) && label.first != "-" && label.last != "-"
            && label.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// True for the domain itself and its subdomains, at label boundaries: reddit.com covers old.reddit.com, not notreddit.com.
    public func covers(_ other: BlockDomain) -> Bool {
        other.rawValue == rawValue || other.rawValue.hasSuffix("." + rawValue)
    }

    /// The preset name for a preset's domain ("Reddit" for redd.it), else the domain.
    public var label: String { BlockPreset.allCases.first { $0.domains.contains(self) }?.name ?? rawValue }

    public var description: String { rawValue }
    public static func < (a: BlockDomain, b: BlockDomain) -> Bool { a.rawValue < b.rawValue }
}

/// A macOS app by bundle identifier. Matching ignores case, as LaunchServices does.
public struct AppBundleID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    /// Three itself and the apps you need to get around or recover macOS.
    static let protected: Set<String> = [
        ThreeVersion.bundleID, "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
        "com.apple.systempreferences", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.activitymonitor", "com.apple.spotlight", "com.apple.securityagent", "com.apple.windowmanager",
        "com.apple.coreservices.uiagent",
    ]

    public init(parsing input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...255).contains(text.count), parts.count >= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } })
        else { throw BlockError.invalidApp("\"\(input)\" isn't a bundle identifier, like com.tinyspeck.slackmacgap.") }
        guard !AppBundleID.protected.contains(text.lowercased()) else { throw BlockError.protectedApp(text) }
        rawValue = text
    }

    public func matches(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier?.caseInsensitiveCompare(rawValue) == .orderedSame
    }

    public var description: String { rawValue }
}

public enum BlockTarget: Hashable, Sendable {
    case domain(BlockDomain)
    case app(AppBundleID)

    public var kind: String {
        switch self {
        case .domain: "domain"
        case .app: "app"
        }
    }

    public var value: String {
        switch self {
        case .domain(let d): d.rawValue
        case .app(let a): a.rawValue
        }
    }

    /// Rows are re-parsed on read, so a hand-edited database can't smuggle in a malformed or protected target.
    init?(kind: String, value: String) {
        switch kind {
        case "domain": guard let d = try? BlockDomain(parsing: value), d.rawValue == value else { return nil }; self = .domain(d)
        case "app": guard let a = try? AppBundleID(parsing: value) else { return nil }; self = .app(a)
        default: return nil
        }
    }
}

public struct BlockRule: Identifiable, Hashable, Sendable {
    public let id: String
    public let target: BlockTarget
    public let enabled: Bool
    public let createdAt: Date
}

/// Starter sets offered to the user, never seeded. X leaves out t.co, which would break links everywhere.
public enum BlockPreset: String, CaseIterable, Sendable {
    case x, reddit, youtube

    public var name: String {
        switch self {
        case .x: "X"
        case .reddit: "Reddit"
        case .youtube: "YouTube"
        }
    }

    public var domains: [BlockDomain] {
        let names = switch self {
        case .x: ["x.com", "twitter.com"]
        case .reddit: ["reddit.com", "redd.it"]
        case .youtube: ["youtube.com", "youtu.be"]
        }
        return names.map { try! BlockDomain(parsing: $0) }
    }
}

// MARK: Focus hours

/// ISO weekday: Monday is 1. `Calendar` numbers Sunday as 1, so convert through `init(_:calendar:)`.
public enum Weekday: Int, CaseIterable, Comparable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public init(_ date: Date, calendar: Calendar) {
        self.init(rawValue: (calendar.component(.weekday, from: date) + 5) % 7 + 1)!
    }

    public var shortName: String { ["mon", "tue", "wed", "thu", "fri", "sat", "sun"][rawValue - 1] }

    public static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
}

/// A local wall-clock time as minutes since midnight. 24:00 (1440) is allowed only as an end.
public struct ClockTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let minutes: Int

    public init?(minutes: Int) {
        guard (0...1440).contains(minutes) else { return nil }
        self.minutes = minutes
    }

    /// "9", "09", "9:30" or "21:05".
    public init?(parsing text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy(\.isASCII) }),
              let hour = Int(parts[0]), let minute = parts.count == 2 ? Int(parts[1]) : 0,
              parts.count == 1 || parts[1].count == 2, (0...24).contains(hour), (0...59).contains(minute),
              hour < 24 || minute == 0 else { return nil }
        self.minutes = hour * 60 + minute
    }

    public var description: String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    public static func < (a: ClockTime, b: ClockTime) -> Bool { a.minutes < b.minutes }
}

/// A weekly span of local wall-clock time, `[start, end)`. An end at or before the start runs past midnight
/// into the next day. Times float with the Mac's time zone, so travelling moves the hours with you.
public struct FocusHours: Hashable, Sendable {
    public let days: [Weekday]
    public let start: ClockTime
    public let end: ClockTime

    public init(days: some Sequence<Weekday>, start: ClockTime, end: ClockTime) throws {
        self.days = Array(Set(days)).sorted()
        guard !self.days.isEmpty else { throw BlockError.invalidHours("Pick at least one day.") }
        guard start.minutes < 1440, start != end else {
            throw BlockError.invalidHours("Focus hours need a start and a different end, like 10:00-13:00.")
        }
        self.start = start
        self.end = end
    }

    /// `days` is "mon-fri", "sat,sun", "fri-mon", "weekdays", "weekends" or "daily"; `time` is "10:00-13:00".
    public init(days: String, time: String) throws {
        var picked: [Weekday] = []
        for item in days.lowercased().split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch item {
            case "weekdays": picked += [.monday, .tuesday, .wednesday, .thursday, .friday]
            case "weekends": picked += [.saturday, .sunday]
            case "daily", "everyday", "every day": picked += Weekday.allCases
            default:
                let ends = item.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                guard (1...2).contains(ends.count), let first = FocusHours.weekday(ends[0]),
                      let last = FocusHours.weekday(ends.last!) else {
                    throw BlockError.invalidHours("Can't read \"\(item)\" as days. Try mon-fri, sat,sun or daily.")
                }
                var day = first
                picked.append(day)
                while day != last {
                    day = Weekday(rawValue: day.rawValue % 7 + 1)!
                    picked.append(day)
                }
            }
        }
        let times = time.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard times.count == 2, let start = ClockTime(parsing: times[0]), let end = ClockTime(parsing: times[1]) else {
            throw BlockError.invalidHours("Can't read \"\(time)\" as hours. Try 10:00-13:00 or 22:00-02:00.")
        }
        try self.init(days: picked, start: start, end: end)
    }

    private static func weekday(_ name: String) -> Weekday? {
        let names: [String: Weekday] = [
            "mon": .monday, "monday": .monday, "tue": .tuesday, "tues": .tuesday, "tuesday": .tuesday,
            "wed": .wednesday, "wednesday": .wednesday, "thu": .thursday, "thur": .thursday, "thurs": .thursday,
            "thursday": .thursday, "fri": .friday, "friday": .friday, "sat": .saturday, "saturday": .saturday,
            "sun": .sunday, "sunday": .sunday,
        ]
        return names[name]
    }
}

/// One stored day of focus hours.
public struct FocusWindow: Identifiable, Hashable, Sendable {
    public let id: String
    public let weekday: Weekday
    public let start: ClockTime
    public let end: ClockTime

    public var isOvernight: Bool { end <= start }
}

// MARK: Policy

/// The running focus session as the policy needs it.
public struct RunningFocus: Sendable {
    public let session: Session
    public let taskTitle: String?
    public let categoryColor: String?
    public let strict: Bool
}

/// A temporary unblock of one rule.
public struct BlockException: Hashable, Sendable {
    public let id: String
    public let ruleId: String
    public let reason: String
    public let expiresAt: Date
}

/// Why a focus session is blocking right now, and the latest it will keep blocking if nothing else happens.
public struct FocusCover: Hashable, Sendable {
    public enum Phase: String, Sendable { case running, overrun, paused }

    public let sessionId: String
    public let taskId: String?
    public let taskTitle: String?
    /// The task's category colour, "#RRGGBB".
    public let categoryColor: String?
    public let strict: Bool
    public let phase: Phase
    /// When the timer reaches zero. While paused, the end it would have if resumed at evaluation time.
    public let plannedEnd: Date
    /// The stale-session bound: blocking from this session stops here even if the app never ends it.
    public let expiresAt: Date

    /// When this session's blocking ends in the normal course: the planned end while running, else the bound.
    public var until: Date { phase == .running ? plannedEnd : expiresAt }
}

/// Whether blocking is on at one instant, why, what it blocks, and when that next changes on its own.
/// Derived from the database and the clock every time; nothing stores an "is blocking" flag.
public struct BlockPolicy: Hashable, Sendable {
    /// How long a paused or overrun focus session keeps blocking: 15 minutes after the pause, or past the planned end.
    public static let staleSessionGrace: TimeInterval = 15 * 60
    public static let exceptionDuration: TimeInterval = 5 * 60

    public let evaluatedAt: Date
    public let focus: FocusCover?
    /// The merged focus-hours span containing `evaluatedAt`.
    public let focusHours: DateInterval?
    /// Enabled rules in force, minus active exceptions. Empty while blocking is off. Blocking is off whenever there
    /// are no enabled rules, even during a session or focus hours.
    public let blocked: [BlockRule]
    /// Active temporary unblocks. Empty while blocking is off.
    public let exceptions: [BlockException]
    /// The next instant `evaluate` can return something different without a database change.
    public let nextChange: Date?

    public var isActive: Bool { focus != nil || focusHours != nil }
    public var strict: Bool { focus?.strict ?? false }
    /// When blocking ends in the normal course, across every reason that holds now.
    public var until: Date? { [focus?.until, focusHours?.end].compactMap(\.self).max() }

    public static func evaluate(at now: Date, calendar: Calendar, rules: [BlockRule], windows: [FocusWindow],
                                running: RunningFocus?, exceptions: [BlockException]) -> BlockPolicy {
        let focus = running.flatMap { cover(for: $0, at: now) }
        let spans = focusSpans(windows, around: now, calendar: calendar)
        let hours = spans.first { $0.start <= now && now < $0.end }
        var changes: [Date] = []
        if let focus { changes += [focus.phase == .running ? focus.plannedEnd : focus.expiresAt] }
        if let hours { changes.append(hours.end) } else if let next = spans.first(where: { $0.start > now }) { changes.append(next.start) }

        let enabled = rules.filter(\.enabled)
        // With nothing to block there is nothing to protect, so the lists stay editable.
        guard focus != nil || hours != nil, !enabled.isEmpty else {
            return BlockPolicy(evaluatedAt: now, focus: nil, focusHours: nil, blocked: [], exceptions: [],
                               nextChange: enabled.isEmpty ? nil : changes.filter { $0 > now }.min())
        }
        let live = exceptions.filter { e in e.expiresAt > now && enabled.contains { $0.id == e.ruleId } }
        changes += live.map(\.expiresAt)
        return BlockPolicy(evaluatedAt: now, focus: focus, focusHours: hours,
                           blocked: enabled.filter { r in !live.contains { $0.ruleId == r.id } }, exceptions: live,
                           nextChange: changes.filter { $0 > now }.min())
    }

    static func cover(for running: RunningFocus, at now: Date) -> FocusCover? {
        let s = running.session
        guard s.kind == .focus, s.isRunning else { return nil }
        let overrun = max(0, -s.remaining(at: now))
        guard overrun < staleSessionGrace else { return nil }
        let phase: FocusCover.Phase
        let plannedEnd: Date
        let expiresAt: Date
        if let pausedAt = s.pausedAt {
            phase = .paused
            plannedEnd = s.plannedEnd.addingTimeInterval(max(0, now.timeIntervalSince(pausedAt)))
            expiresAt = pausedAt.addingTimeInterval(staleSessionGrace)
        } else {
            phase = s.remaining(at: now) > 0 ? .running : .overrun
            plannedEnd = s.plannedEnd
            expiresAt = s.plannedEnd.addingTimeInterval(staleSessionGrace)
        }
        guard now < expiresAt else { return nil }
        return FocusCover(sessionId: s.id, taskId: s.taskId, taskTitle: running.taskTitle,
                          categoryColor: running.categoryColor, strict: running.strict,
                          phase: phase, plannedEnd: plannedEnd, expiresAt: expiresAt)
    }

    /// Focus-hours spans from yesterday (overnight windows reach into today) through a week ahead, merged and sorted.
    static func focusSpans(_ windows: [FocusWindow], around now: Date, calendar: Calendar) -> [DateInterval] {
        guard !windows.isEmpty,
              let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now, matchingPolicy: .nextTime,
                                       repeatedTimePolicy: .first, direction: .forward) else { return [] }
        var spans: [DateInterval] = []
        for offset in -1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: noon),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let weekday = Weekday(day, calendar: calendar)
            for w in windows where w.weekday == weekday {
                guard let start = wallClock(w.start, on: day, calendar),
                      let end = wallClock(w.end, on: w.isOvernight ? nextDay : day, calendar), start < end else { continue }
                spans.append(DateInterval(start: start, end: end))
            }
        }
        var merged: [DateInterval] = []
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, span.end))
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// A skipped DST time resolves to the next valid one; a repeated time to its first occurrence.
    private static func wallClock(_ time: ClockTime, on day: Date, _ calendar: Calendar) -> Date? {
        if time.minutes == 1440 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return wallClock(ClockTime(minutes: 0)!, on: next, calendar)
        }
        return calendar.date(bySettingHour: time.minutes / 60, minute: time.minutes % 60, second: 0, of: day,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
}
