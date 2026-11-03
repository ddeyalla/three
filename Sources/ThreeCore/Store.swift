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

    public convenience init(url: URL = Store.defaultURL) throws {
        try self.init(url: url, upTo: nil)
    }

    /// `upTo` stops at a named migration, so tests can build an old database and migrate it.
    init(url: URL, upTo migration: String?) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.busyMode = .timeout(5)
        db = try DatabasePool(path: url.path, configuration: config)
        if let migration {
            try Store.migrator.migrate(db, upTo: migration)
        } else {
            try Store.migrator.migrate(db)
            // An older CLI can write legacy dates while the installed app catches up with an upgrade.
            try db.write { db in
                if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM dayPlan WHERE day NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')") == true {
                    try Self.canonicalizePlanDates(db)
                }
            }
        }
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
        // Calmer seed colours at matched lightness. Only untouched seeds change.
        m.registerMigration("v2-calm-colors") { db in
            for (old, new) in [("#FF4F6D", "#F2766B"), ("#5B8CFF", "#6E9BF2"), ("#F5A524", "#E5A84B"),
                               ("#2BC48A", "#4FBF8B"), ("#A971FF", "#A58AF0")] {
                try db.execute(sql: "UPDATE category SET colorHex = ? WHERE colorHex = ?", arguments: [new, old])
            }
        }
        // Inbox: a task may have no day yet. SQLite can't drop NOT NULL, so rebuild the table.
        m.registerMigration("v3-inbox-steps-prefs") { db in
            try db.create(table: "task_new") { t in
                t.primaryKey("id", .text)
                t.column("dayPlanId", .text).references("dayPlan")
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
            try db.execute(sql: "INSERT INTO task_new SELECT * FROM task")
            try db.drop(table: "task")
            try db.rename(table: "task_new", to: "task")
            try db.create(index: "task_on_dayPlanId", on: "task", columns: ["dayPlanId"])

            try db.create(table: "step") { t in
                t.primaryKey("id", .text)
                t.column("taskId", .text).notNull().references("task", onDelete: .cascade).indexed()
                t.column("position", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("done", .boolean).notNull().defaults(to: false)
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "preference") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        // Before 0.2.1 a task could be marked done while its block kept running. Close those blocks where they paused.
        m.registerMigration("v4-close-orphaned-sessions") { db in
            try db.execute(sql: """
                UPDATE session
                SET endedAt = COALESCE(pausedAt, CURRENT_TIMESTAMP),
                    pausedAt = NULL, endReason = 'completed', outcome = 'done', updatedAt = CURRENT_TIMESTAMP
                WHERE endedAt IS NULL AND taskId IN (SELECT id FROM task WHERE status = 'done')
                """)
        }
        // Tags: threads of work across days. Names are unique ignoring case.
        m.registerMigration("v5-tags") { db in
            try db.create(table: "tag") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().unique(onConflict: .abort).collate(.nocase)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "taskTag") { t in
                t.column("taskId", .text).notNull().references("task", onDelete: .cascade)
                t.column("tagId", .text).notNull().references("tag", onDelete: .cascade).indexed()
                t.primaryKey(["taskId", "tagId"])
            }
            // When a task was finished, for Done. Kept out of FocusTask and written by setDone, so editing a
            // finished task's notes doesn't move it to another day.
            try db.alter(table: "task") { t in t.add(column: "doneAt", .datetime) }
            try db.execute(sql: "UPDATE task SET doneAt = updatedAt WHERE status = 'done'")
        }
        m.registerMigration("v6-deferred-reflections") { db in
            try db.alter(table: "session") { t in
                t.add(column: "reflectionPending", .boolean).notNull().defaults(to: false)
            }
        }
        // Distraction blocker. Starts empty: no rules, no focus hours, so nothing is blocked until the user adds some.
        m.registerMigration("v7-blocker") { db in
            try db.create(table: "blockRule") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull().check { ["domain", "app"].contains($0) }
                t.column("value", .text).notNull()
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.execute(sql: "CREATE UNIQUE INDEX blockRule_live ON blockRule(kind, value COLLATE NOCASE) WHERE deletedAt IS NULL")
            try db.create(table: "focusWindow") { t in
                t.primaryKey("id", .text)
                t.column("weekday", .integer).notNull().check { $0 >= 1 && $0 <= 7 }
                t.column("startMinute", .integer).notNull().check { $0 >= 0 && $0 < 1440 }
                t.column("endMinute", .integer).notNull().check { $0 >= 0 && $0 <= 1440 }
                t.check(sql: "startMinute <> endMinute")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.execute(sql: "CREATE UNIQUE INDEX focusWindow_live ON focusWindow(weekday, startMinute, endMinute) WHERE deletedAt IS NULL")
            // Hits and temporary unblocks. Never a URL or page title: only which rule matched, and when.
            try db.create(table: "blockEvent") { t in
                t.primaryKey("id", .text)
                t.column("at", .datetime).notNull()
                t.column("ruleId", .text).notNull().references("blockRule")
                t.column("sessionId", .text).references("session")
                t.column("action", .text).notNull().check { ["blocked", "unblocked"].contains($0) }
                t.column("reason", .text)
                t.column("expiresAt", .datetime)
            }
            try db.create(index: "blockEvent_rule_at", on: "blockEvent", columns: ["ruleId", "at"])
            // One row per browser profile running the extension, so the app can say what is actually covered.
            try db.create(table: "browserClient") { t in
                t.primaryKey("id", .text)
                t.column("extensionVersion", .text).notNull()
                t.column("hostAccess", .boolean).notNull()
                t.column("connectedAt", .datetime).notNull()
                t.column("seenAt", .datetime).notNull()
            }
        }
        m.registerMigration("v8-canonical-plan-dates") { db in
            try canonicalizePlanDates(db)
        }
        return m
    }

    private static func canonicalizePlanDates(_ db: Database) throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var groups: [String: [Row]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT * FROM dayPlan ORDER BY deletedAt IS NOT NULL, createdAt, id") {
            let raw: String = row["day"]
            guard let date = formatter.date(from: raw) else {
                throw ThreeError.invalid("An existing plan has an unreadable date. The database was not changed.")
            }
            groups[DayKey(date).rawValue, default: []].append(row)
        }
        for (day, plans) in groups {
            let keeper = plans.first { row in
                let raw: String = row["day"]
                let deleted: Date? = row["deletedAt"]
                return raw == day && deleted == nil
            } ?? plans[0]
            let id: String = keeper["id"]
            var status: String = keeper["status"]
            var committed: Date? = keeper["committedAt"]
            for plan in plans where (plan["id"] as String) != id {
                let otherId: String = plan["id"]
                let deleted: Date? = plan["deletedAt"]
                let offset = (try Int.fetchOne(db, sql: "SELECT MAX(position) FROM task WHERE dayPlanId = ?", arguments: [id]) ?? -1) + 1
                try db.execute(sql: "UPDATE task SET dayPlanId = ?, position = position + ?, deletedAt = COALESCE(deletedAt, ?) WHERE dayPlanId = ?", arguments: [id, offset, deleted, otherId])
                let otherStatus: String = plan["status"]
                if deleted == nil, otherStatus == "closed" || (status == "draft" && otherStatus == "committed") { status = otherStatus }
                let otherCommitted: Date? = plan["committedAt"]
                if let otherCommitted { committed = min(committed ?? otherCommitted, otherCommitted) }
                try db.execute(sql: "DELETE FROM dayPlan WHERE id = ?", arguments: [otherId])
            }
            try db.execute(sql: "UPDATE dayPlan SET day = ?, status = ?, committedAt = ? WHERE id = ?", arguments: [day, status, committed, id])
        }
    }
}
