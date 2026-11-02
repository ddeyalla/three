import Foundation
import GRDB

public enum ThreeError: LocalizedError, Equatable {
    case tooManyTasks
    case noSuchTask(String)
    case noSuchCategory(String)
    case noRunningSession
    case alreadyRunning
    case nothingToStart
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .tooManyTasks: "A day holds at most \(Rules.maxTasks) tasks. Drop one first."
        case .noSuchTask(let id): "No task matches \"\(id)\"."
        case .noSuchCategory(let name): "No category named \"\(name)\"."
        case .noRunningSession: "Nothing is running."
        case .alreadyRunning: "A session is already running. Stop it first."
        case .nothingToStart: "No open task left today."
        case .invalid(let why): why
        }
    }
}

public enum Rules {
    public static let maxTasks = 5
    public static let idealTasks = 3
    public static let defaultSessionMinutes = 45
    public static let shortBreakMinutes = 5
    public static let longBreakMinutes = 15
    public static let longBreakAfterFocusMinutes = 100
}

/// The one database shared by the app and the `three` CLI.
public final class Store: @unchecked Sendable {
    public let db: DatabasePool

    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["THREE_DB"] {
            return URL(fileURLWithPath: override)
        }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Three", isDirectory: true)
        return dir.appendingPathComponent("three.sqlite")
    }

    public init(url: URL = Store.defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.busyMode = .timeout(5)
        db = try DatabasePool(path: url.path, configuration: config)
        try Store.migrator.migrate(db)
    }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "category") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().unique(onConflict: .abort)
                t.column("colorHex", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(table: "dayPlan") { t in
                t.primaryKey("id", .text)
                t.column("day", .text).notNull().unique()
                t.column("status", .text).notNull()
                t.column("source", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("committedAt", .datetime)
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(table: "task") { t in
                t.primaryKey("id", .text)
                t.column("dayPlanId", .text).notNull().references("dayPlan").indexed()
                t.column("position", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("categoryId", .text).notNull().references("category")
                t.column("blockMinutes", .integer).notNull().check { $0 > 0 }
                t.column("scheduledStart", .datetime)
                t.column("strict", .boolean).notNull().defaults(to: false)
                t.column("status", .text).notNull()
                t.column("linearRef", .text)
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("createdBy", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(table: "session") { t in
                t.primaryKey("id", .text)
                t.column("taskId", .text).references("task").indexed()
                t.column("kind", .text).notNull()
                t.column("plannedSeconds", .integer).notNull()
                t.column("startedAt", .datetime).notNull().indexed()
                t.column("pausedAt", .datetime)
                t.column("pausedSeconds", .integer).notNull().defaults(to: 0)
                t.column("endedAt", .datetime)
                t.column("endReason", .text)
                t.column("outcome", .text)
                t.column("focusRating", .integer)
                t.column("note", .text)
                t.column("updatedAt", .datetime).notNull()
            }
            // At most one running timer, enforced by the database.
            try db.execute(sql: "CREATE UNIQUE INDEX session_one_running ON session(endedAt IS NULL) WHERE endedAt IS NULL")

            let seed: [(String, String)] = [
                ("Coding", "#FF4F6D"), ("Writing", "#5B8CFF"), ("Admin", "#F5A524"),
                ("Learning", "#2BC48A"), ("Meeting prep", "#A971FF"),
            ]
            for (i, (name, color)) in seed.enumerated() {
                try Category(id: UUID().uuidString, name: name, colorHex: color, position: i,
                             archived: false, updatedAt: Date(), deletedAt: nil).insert(db)
            }
        }
        return m
    }
}
