import Foundation
import GRDB

/// One browser profile's Three extension, as last heard from by the native host.
public struct BrowserConnection: Identifiable, Hashable, Sendable {
    /// How long a connection counts as live after its last heartbeat.
    public static let liveFor: TimeInterval = 120

    /// A random id the extension keeps per profile. It says nothing about the profile itself.
    public let id: String
    public let extensionVersion: String
    /// Whether Chrome lets the extension act on every site. Without it, redirects to the block page fail.
    public let hostAccess: Bool
    public let connectedAt: Date
    public let seenAt: Date

    public func isLive(at now: Date) -> Bool { now < seenAt.addingTimeInterval(BrowserConnection.liveFor) }
}

/// Everything a blocker screen or `three block status` shows.
public struct BlockStatus: Sendable {
    public let policy: BlockPolicy
    /// Every rule, enabled or not, oldest first.
    public let rules: [BlockRule]
    /// Every focus-hours window, by weekday then start.
    public let windows: [FocusWindow]
    /// Block hits per rule id since local midnight.
    public let hitsToday: [String: Int]
    /// Profiles heard from in the last day, most recent first. Filter with `isLive(at:)`.
    public let browsers: [BrowserConnection]

    public func liveBrowsers(at now: Date) -> [BrowserConnection] { browsers.filter { $0.isLive(at: now) } }
}

extension Store {
    /// Hits on one rule closer together than this count once, so a reload storm can't flood the log.
    static let hitDedupeWindow: TimeInterval = 10

    // MARK: Reads

    public func blockStatus(now: Date = Date(), calendar: Calendar = .current) throws -> BlockStatus {
        try db.read { db in
            let midnight = calendar.startOfDay(for: now)
            let hits = try Row.fetchAll(db, sql: """
                SELECT ruleId, COUNT(*) AS n FROM blockEvent WHERE action = 'blocked' AND at >= ? GROUP BY ruleId
                """, arguments: [midnight])
            let browsers = try Row.fetchAll(db, sql: """
                SELECT * FROM browserClient WHERE seenAt >= ? ORDER BY seenAt DESC
                """, arguments: [now.addingTimeInterval(-86_400)]).map {
                    BrowserConnection(id: $0["id"], extensionVersion: $0["extensionVersion"], hostAccess: $0["hostAccess"],
                                      connectedAt: $0["connectedAt"], seenAt: $0["seenAt"])
                }
            return BlockStatus(policy: try blockPolicy(now: now, calendar: calendar, db), rules: try blockRules(db),
                               windows: try focusWindows(db),
                               hitsToday: Dictionary(uniqueKeysWithValues: hits.map { ($0["ruleId"] as String, $0["n"] as Int) }),
                               browsers: browsers)
        }
    }

    public func blockPolicy(now: Date = Date(), calendar: Calendar = .current) throws -> BlockPolicy {
        try db.read { try blockPolicy(now: now, calendar: calendar, $0) }
    }

    func blockPolicy(now: Date, calendar: Calendar, _ db: Database) throws -> BlockPolicy {
        var running: RunningFocus?
        if let s = try Session.filter(Column("endedAt") == nil).fetchOne(db), s.kind == .focus {
            let task = try s.taskId.flatMap { try FocusTask.fetchOne(db, key: $0) }
            let category = try task.flatMap { try Category.fetchOne(db, key: $0.categoryId) }
            running = RunningFocus(session: s, taskTitle: task?.title, categoryColor: category?.colorHex, strict: task?.strict ?? false)
        }
        let exceptions = try Row.fetchAll(db, sql: """
            SELECT id, ruleId, reason, expiresAt FROM blockEvent WHERE action = 'unblocked' AND expiresAt > ?
            """, arguments: [now]).map {
                BlockException(id: $0["id"], ruleId: $0["ruleId"], reason: $0["reason"] ?? "", expiresAt: $0["expiresAt"])
            }
        return BlockPolicy.evaluate(at: now, calendar: calendar, rules: try blockRules(db), windows: try focusWindows(db),
                                    running: running, exceptions: exceptions)
    }

    /// Rows that no longer parse (a hand-edited database) are skipped rather than failing every read.
    func blockRules(_ db: Database) throws -> [BlockRule] {
        try Row.fetchAll(db, sql: "SELECT * FROM blockRule WHERE deletedAt IS NULL ORDER BY createdAt, rowid").compactMap { row in
            BlockTarget(kind: row["kind"], value: row["value"]).map {
                BlockRule(id: row["id"], target: $0, enabled: row["enabled"], createdAt: row["createdAt"])
            }
        }
    }

    func focusWindows(_ db: Database) throws -> [FocusWindow] {
        try Row.fetchAll(db, sql: """
            SELECT * FROM focusWindow WHERE deletedAt IS NULL ORDER BY weekday, startMinute, endMinute
            """).compactMap { row in
                guard let day = Weekday(rawValue: row["weekday"]), let start = ClockTime(minutes: row["startMinute"]),
                      let end = ClockTime(minutes: row["endMinute"]), start.minutes < 1440, start != end else { return nil }
                return FocusWindow(id: row["id"], weekday: day, start: start, end: end)
            }
    }

    // MARK: Tightening: always allowed

    @discardableResult
    public func addBlockRule(_ target: BlockTarget, now: Date = Date()) throws -> BlockRule {
        try addBlockRules([target], now: now)[0]
    }

    @discardableResult
    public func addBlockPreset(_ preset: BlockPreset, now: Date = Date()) throws -> [BlockRule] {
        try addBlockRules(preset.domains.map(BlockTarget.domain), now: now)
    }

    /// Adds all of `targets` in one transaction and returns the rule now covering each, in order.
    /// Re-adding is harmless: an existing rule is returned (and re-enabled), and a domain already covered by
    /// an enabled parent rule returns that rule instead of adding a redundant one.
    @discardableResult
    public func addBlockRules(_ targets: [BlockTarget], now: Date = Date()) throws -> [BlockRule] {
        try write { db in
            let rules = try targets.map { target in
                if let row = try Row.fetchOne(db, sql: """
                    SELECT * FROM blockRule WHERE deletedAt IS NULL AND kind = ? AND value = ? COLLATE NOCASE
                    """, arguments: [target.kind, target.value]) {
                    if !(row["enabled"] as Bool) {
                        try db.execute(sql: "UPDATE blockRule SET enabled = 1, updatedAt = ? WHERE id = ?", arguments: [now, row["id"]])
                    }
                    return BlockRule(id: row["id"], target: target, enabled: true, createdAt: row["createdAt"])
                }
                if case .domain(let d) = target, let parent = try blockRules(db).first(where: {
                    guard $0.enabled, case .domain(let p) = $0.target else { return false }
                    return p.covers(d)
                }) {
                    return parent
                }
                let rule = BlockRule(id: UUID().uuidString, target: target, enabled: true, createdAt: now)
                try db.execute(sql: """
                    INSERT INTO blockRule (id, kind, value, enabled, createdAt, updatedAt) VALUES (?, ?, ?, 1, ?, ?)
                    """, arguments: [rule.id, target.kind, target.value, now, now])
                return rule
            }
            try requireSupportedRuleCount(db)
            return rules
        }
    }

    private func requireSupportedRuleCount(_ db: Database) throws {
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM blockRule WHERE kind = 'domain' AND enabled = 1 AND deletedAt IS NULL") ?? 0
        guard count <= BlockRule.maxDomains else { throw BlockError.tooManyDomains }
    }

    /// Adds one window per day in `hours`, in one transaction. Windows that already exist are reused.
    @discardableResult
    public func addFocusHours(_ hours: FocusHours, now: Date = Date()) throws -> [FocusWindow] {
        try write { try insertFocusHours(hours, now: now, $0) }
    }

    private func insertFocusHours(_ hours: FocusHours, now: Date, _ db: Database) throws -> [FocusWindow] {
        try hours.days.map { day in
            let (start, end) = (hours.start.minutes, hours.end.minutes)
            if let id = try String.fetchOne(db, sql: """
                SELECT id FROM focusWindow WHERE deletedAt IS NULL AND weekday = ? AND startMinute = ? AND endMinute = ?
                """, arguments: [day.rawValue, start, end]) {
                return FocusWindow(id: id, weekday: day, start: hours.start, end: hours.end)
            }
            let w = FocusWindow(id: UUID().uuidString, weekday: day, start: hours.start, end: hours.end)
            try db.execute(sql: """
                INSERT INTO focusWindow (id, weekday, startMinute, endMinute, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [w.id, day.rawValue, start, end, now, now])
            return w
        }
    }

    // MARK: Loosening: refused while blocking is on

    /// Disabling is loosening, so it waits for blocking to end. Enabling is always allowed.
    public func setBlockRule(_ id: String, enabled: Bool, now: Date = Date(), calendar: Calendar = .current) throws {
        try write { db in
            guard try ruleExists(id, db) else { throw BlockError.noSuchRule(id) }
            if !enabled { try requireBlockingOff(now: now, calendar: calendar, db) }
            try db.execute(sql: "UPDATE blockRule SET enabled = ?, updatedAt = ? WHERE id = ?", arguments: [enabled, now, id])
            if enabled { try requireSupportedRuleCount(db) }
        }
    }

    /// A disabled rule blocks nothing, so it can go at any time; an enabled one waits for blocking to end.
    public func removeBlockRule(_ id: String, now: Date = Date(), calendar: Calendar = .current) throws {
        try write { db in
            guard let enabled = try Bool.fetchOne(db, sql: "SELECT enabled FROM blockRule WHERE id = ? AND deletedAt IS NULL",
                                                  arguments: [id]) else { throw BlockError.noSuchRule(id) }
            if enabled { try requireBlockingOff(now: now, calendar: calendar, db) }
            try db.execute(sql: "UPDATE blockRule SET deletedAt = ?, updatedAt = ? WHERE id = ?", arguments: [now, now, id])
        }
    }

    /// Removes every window in `ids` or none of them.
    public func removeFocusWindows(_ ids: [String], now: Date = Date(), calendar: Calendar = .current) throws {
        try write { db in try deleteFocusWindows(ids, now: now, calendar: calendar, db) }
    }

    /// Swaps a group of windows for new hours in one transaction, so an edit can't leave half a group behind.
    @discardableResult
    public func replaceFocusWindows(_ ids: [String], with hours: FocusHours, now: Date = Date(),
                                    calendar: Calendar = .current) throws -> [FocusWindow] {
        try write { db in
            try deleteFocusWindows(ids, now: now, calendar: calendar, db)
            return try insertFocusHours(hours, now: now, db)
        }
    }

    private func deleteFocusWindows(_ ids: [String], now: Date, calendar: Calendar, _ db: Database) throws {
        for id in ids {
            let live = try String.fetchOne(db, sql: "SELECT id FROM focusWindow WHERE id = ? AND deletedAt IS NULL", arguments: [id])
            guard live != nil else { throw BlockError.noSuchWindow(id) }
        }
        try requireBlockingOff(now: now, calendar: calendar, db)
        for id in ids {
            try db.execute(sql: "UPDATE focusWindow SET deletedAt = ?, updatedAt = ? WHERE id = ?", arguments: [now, now, id])
        }
    }

    private func requireBlockingOff(now: Date, calendar: Calendar, _ db: Database) throws {
        let policy = try blockPolicy(now: now, calendar: calendar, db)
        guard !policy.isActive else { throw BlockError.protectionActive(until: policy.until) }
    }

    private func ruleExists(_ id: String, _ db: Database) throws -> Bool {
        try String.fetchOne(db, sql: "SELECT id FROM blockRule WHERE id = ? AND deletedAt IS NULL", arguments: [id]) != nil
    }

    // MARK: Events

    /// Logs that a rule in force stopped a site or app. Returns false, writing nothing, when the rule isn't in force
    /// right now or was hit within the last few seconds.
    @discardableResult
    public func recordBlockHit(ruleId: String, now: Date = Date(), calendar: Calendar = .current) throws -> Bool {
        let recorded = try db.write { db -> Bool in
            let policy = try blockPolicy(now: now, calendar: calendar, db)
            guard policy.blocked.contains(where: { $0.id == ruleId }) else { return false }
            let recent = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM blockEvent WHERE ruleId = ? AND action = 'blocked' AND at > ?
                """, arguments: [ruleId, now.addingTimeInterval(-Store.hitDedupeWindow)]) ?? 0
            guard recent == 0 else { return false }
            try db.execute(sql: "INSERT INTO blockEvent (id, at, ruleId, sessionId, action) VALUES (?, ?, ?, ?, 'blocked')",
                           arguments: [UUID().uuidString, now, ruleId, policy.focus?.sessionId])
            return true
        }
        if recorded { ChangeSignal.post() }
        return recorded
    }

    /// Opens one rule for five minutes while blocking is on, logged with the reason. Refused during a strict
    /// session. Asking again while it's open returns the same exception. The reason length and the wait before
    /// granting are the app's to enforce; this only requires a reason.
    @discardableResult
    public func requestBlockException(ruleId: String, reason: String, now: Date = Date(),
                                      calendar: Calendar = .current) throws -> BlockException {
        let reason = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !reason.isEmpty else { throw BlockError.missingReason }
        return try write { db in
            let policy = try blockPolicy(now: now, calendar: calendar, db)
            guard policy.isActive else { throw BlockError.notBlocking }
            guard !policy.strict else { throw BlockError.strictSession }
            if let open = policy.exceptions.first(where: { $0.ruleId == ruleId }) { return open }
            guard policy.blocked.contains(where: { $0.id == ruleId }) else { throw BlockError.noSuchRule(ruleId) }
            let e = BlockException(id: UUID().uuidString, ruleId: ruleId, reason: reason,
                                   expiresAt: now.addingTimeInterval(BlockPolicy.exceptionDuration))
            try db.execute(sql: """
                INSERT INTO blockEvent (id, at, ruleId, sessionId, action, reason, expiresAt) VALUES (?, ?, ?, ?, 'unblocked', ?, ?)
                """, arguments: [e.id, now, ruleId, policy.focus?.sessionId, reason, e.expiresAt])
            return e
        }
    }

    /// A profile's extension connected. Signals the app so coverage updates at once.
    public func recordBrowserHello(clientId: String, extensionVersion: String, hostAccess: Bool, now: Date = Date()) throws {
        try write { db in
            try db.execute(sql: """
                INSERT INTO browserClient (id, extensionVersion, hostAccess, connectedAt, seenAt) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET extensionVersion = excluded.extensionVersion, hostAccess = excluded.hostAccess,
                    connectedAt = excluded.connectedAt, seenAt = excluded.seenAt
                """, arguments: [clientId, extensionVersion, hostAccess, now, now])
            try db.execute(sql: "DELETE FROM browserClient WHERE seenAt < ?", arguments: [now.addingTimeInterval(-30 * 86_400)])
        }
    }

    /// Keeps a connection live. Deliberately silent: a heartbeat isn't a change anyone needs to reload for.
    public func recordBrowserHeartbeat(clientId: String, now: Date = Date()) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE browserClient SET seenAt = ? WHERE id = ?", arguments: [now, clientId])
        }
    }
}
