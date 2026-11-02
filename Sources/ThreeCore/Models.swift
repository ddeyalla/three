import Foundation
import GRDB

/// A local calendar date, "yyyy-MM-dd". Plans are keyed by this, never by a `Date`,
/// so a task can't drift across midnight or a timezone change.
public struct DayKey: Hashable, Codable, Comparable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init?(_ raw: String) {
        guard DayKey.formatter.date(from: raw) != nil else { return nil }
        rawValue = raw
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        var f = DayKey.formatter
        f.timeZone = calendar.timeZone
        rawValue = f.string(from: date)
    }

    public static var today: DayKey { DayKey(Date()) }

    public func adding(days: Int) -> DayKey {
        DayKey(Calendar.current.date(byAdding: .day, value: days, to: startDate)!)
    }

    public var startDate: Date { DayKey.formatter.date(from: rawValue)! }
    public var description: String { rawValue }
    public static func < (a: DayKey, b: DayKey) -> Bool { a.rawValue < b.rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}

extension DayKey: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { rawValue.databaseValue }
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> DayKey? {
        String.fromDatabaseValue(dbValue).flatMap(DayKey.init)
    }
}

public struct Category: Codable, Hashable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "category"
    public var id: String
    public var name: String
    public var colorHex: String
    public var position: Int
    public var archived: Bool
    public var updatedAt: Date
    public var deletedAt: Date?
}

public enum PlanStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case draft, committed, closed
}

public enum Source: String, Codable, Sendable, DatabaseValueConvertible {
    case app, cli, mcp, routine
}

public struct DayPlan: Codable, Hashable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "dayPlan"
    public var id: String
    public var day: DayKey
    public var status: PlanStatus
    public var source: Source
    public var createdAt: Date
    public var committedAt: Date?
    public var updatedAt: Date
    public var deletedAt: Date?
}

public enum TaskStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case todo, active, done, partial, dropped, carried

    public var isOpen: Bool { self == .todo || self == .active || self == .partial }
}

public struct FocusTask: Codable, Hashable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "task"
    public var id: String
    /// nil while the task sits in the inbox, unplanned.
    public var dayPlanId: String?
    public var position: Int
    public var title: String
    public var categoryId: String
    public var blockMinutes: Int
    public var scheduledStart: Date?
    public var strict: Bool
    public var status: TaskStatus
    public var linearRef: String?
    public var notes: String
    public var createdBy: Source
    public var updatedAt: Date
    public var deletedAt: Date?
}

public enum SessionKind: String, Codable, Sendable, DatabaseValueConvertible {
    case focus, `break`
}

public enum EndReason: String, Codable, Sendable, DatabaseValueConvertible {
    case completed, stopped
}

public enum Outcome: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case done, progress, stuck
}

public enum FocusRating: Int, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case scattered = 1, okay = 2, focused = 3
}

public enum FocusContinuation: Sendable {
    case stop
    case `break`
    case task(String)
}

/// One timer run. At most one row has `endedAt == nil`; that row is the running timer.
public struct Session: Codable, Hashable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "session"
    public var id: String
    public var taskId: String?
    public var kind: SessionKind
    public var plannedSeconds: Int
    public var startedAt: Date
    public var pausedAt: Date?
    public var pausedSeconds: Int
    public var endedAt: Date?
    public var endReason: EndReason?
    public var outcome: Outcome?
    public var focusRating: FocusRating?
    public var note: String?
    public var updatedAt: Date
    public var reflectionPending: Bool = false

    public var isRunning: Bool { endedAt == nil }
    public var isPaused: Bool { pausedAt != nil }

    /// Seconds of actual work, excluding pauses, up to `now` (or the end).
    public func elapsed(at now: Date) -> TimeInterval {
        let end = endedAt ?? pausedAt ?? now
        return max(0, end.timeIntervalSince(startedAt) - TimeInterval(pausedSeconds))
    }

    /// Negative once the block has overrun.
    public func remaining(at now: Date) -> TimeInterval {
        TimeInterval(plannedSeconds) - elapsed(at: now)
    }

    /// Wall-clock moment the block ends, if it keeps running unpaused.
    public var plannedEnd: Date {
        startedAt.addingTimeInterval(TimeInterval(plannedSeconds + pausedSeconds))
    }
}

/// A checklist item under a task: the first small step, the next one.
public struct Step: Codable, Hashable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "step"
    public var id: String
    public var taskId: String
    public var position: Int
    public var title: String
    public var done: Bool
    public var updatedAt: Date
}

/// Timer defaults, shared by the app and the CLI through the database.
public struct Preferences: Codable, Hashable, Sendable {
    public var sessionMinutes = 45
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var longBreakAfterMinutes = 100
    public var defaultBlockMinutes = 60

    public init() {}
}
