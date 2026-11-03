import Foundation
import GRDB

public struct DayCloseSettings: Codable, Equatable, Sendable {
    public var closeMinute: Int = 22 * 60
    public init() {}
}

public struct CommittedTask: Codable, Equatable, Sendable {
    public let taskId: String
    public let plannedMinutes: Int
}

public struct PlanCommitment: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let tasks: [CommittedTask]
    public var plannedMinutes: Int { tasks.reduce(0) { $0 + $1.plannedMinutes } }
}

public enum BreakDecision: String, Codable, Sendable, DatabaseValueConvertible {
    case taken, skipped
}

public struct RecordedBreakDecision: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "breakDecision"
    public let sessionId: String
    public let decision: BreakDecision
    public let decidedAt: Date
}

public enum DayCloseReason: String, Codable, Sendable { case resolved, due }
public enum DayCloseDeferral: String, Codable, Sendable { case focus, reflection, recovery }
public enum DayCloseIneligibility: String, Codable, Sendable {
    case noCommittedPlan, emptyPlan, futureDay, notDue, legacyClosed
}

public struct DayCloseTaskOutcome: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: TaskStatus
    public let blockMinutes: Int
    public let carriedFromTaskId: String?

    init(_ task: FocusTask) {
        id = task.id
        title = task.title
        status = task.status
        blockMinutes = task.blockMinutes
        carriedFromTaskId = task.carriedFromTaskId
    }
}

public struct DayCloseSessionOutcome: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let taskId: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let endReason: EndReason?
    public let plannedSeconds: Int
    public let focusedSeconds: TimeInterval
    public let outcome: Outcome?
    public let focusRating: FocusRating?
    public let note: String?

    init(_ session: Session, at now: Date) {
        id = session.id
        taskId = session.taskId
        startedAt = session.startedAt
        endedAt = session.endedAt
        endReason = session.endReason
        plannedSeconds = session.plannedSeconds
        focusedSeconds = session.elapsed(at: now)
        outcome = session.outcome
        focusRating = session.focusRating
        note = session.note
    }
}

public struct DayCloseSummary: Codable, Equatable, Identifiable, Sendable {
    public let planId: String
    public let day: DayKey
    public let closedAt: Date
    public let reason: DayCloseReason
    public let tasks: [DayCloseTaskOutcome]
    public let commitment: PlanCommitment?
    public let focusSessions: [DayCloseSessionOutcome]
    public let breakDecisions: [RecordedBreakDecision]
    public let focusedSeconds: TimeInterval
    public var id: String { planId }
    public var plannedMinutes: Int {
        commitment?.plannedMinutes ?? tasks.filter { $0.status != .dropped && $0.status != .carried }
            .reduce(0) { $0 + $1.blockMinutes }
    }
    public var doneCount: Int { tasks.filter { $0.status == .done }.count }
    public var committedDoneCount: Int? {
        commitment.map { committed in
            let done = Set(tasks.filter { $0.status == .done }.map(\.id))
            return committed.tasks.filter { done.contains($0.taskId) }.count
        }
    }
    public var skippedBreakCount: Int? {
        let recorded = Set(breakDecisions.map(\.sessionId))
        guard focusSessions.allSatisfy({ recorded.contains($0.id) }) else { return nil }
        return breakDecisions.filter { $0.decision == .skipped }.count
    }
}

public enum DayCloseResult: Codable, Equatable, Sendable {
    case ready(DayCloseReason)
    case closed(DayCloseSummary)
    case deferred(DayCloseDeferral)
    case notEligible(DayCloseIneligibility)
}

public struct DayCloseAttempt: Codable, Sendable {
    public let day: DayKey
    public let result: DayCloseResult
}

public struct DayCloseBatch: Codable, Sendable {
    public let attempts: [DayCloseAttempt]
    public let nextAfter: DayKey?
}

public enum CarryDisposition: String, Codable, Sendable, DatabaseValueConvertible { case accepted, dismissed }

public struct CarryDecision: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "carryDecision"
    public let sourceTaskId: String
    public let decision: CarryDisposition
    public let copyTaskId: String?
    public let destinationDay: DayKey?
    public let decidedAt: Date
}

public struct DayCloseReview: Sendable {
    public let summary: DayCloseSummary
    public let offers: [TaskRow]
    public let decisions: [CarryDecision]
}

/// An optional additional guard on the same transaction as the durable recovery check.
public typealias DayCloseRecoveryCheck = (Database, DayKey) throws -> Bool

extension Store {
    public func dayCloseSettings() throws -> DayCloseSettings {
        try db.read { try dayCloseSettings($0) }
    }

    func dayCloseSettings(_ db: Database) throws -> DayCloseSettings {
        guard let value = try String.fetchOne(db, sql: "SELECT value FROM preference WHERE key = 'dayClose'") else {
            return DayCloseSettings()
        }
        let settings = try JSONDecoder().decode(DayCloseSettings.self, from: Data(value.utf8))
        guard (0..<1440).contains(settings.closeMinute) else { throw ThreeError.invalid("Choose a time within the day.") }
        return settings
    }

    public func setDayCloseSettings(_ settings: DayCloseSettings) throws {
        guard (0..<1440).contains(settings.closeMinute) else { throw ThreeError.invalid("Choose a time within the day.") }
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        try write { db in
            try db.execute(sql: "INSERT INTO preference(key, value) VALUES('dayClose', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                           arguments: [json])
        }
    }

    func captureCommitment(_ plan: DayPlan, at now: Date, _ db: Database) throws {
        guard plan.status == .draft, plan.committedAt == nil else { return }
        let tasks = try liveTasks(plan.id, db).filter { $0.status != .dropped && $0.status != .carried }
            .map { CommittedTask(taskId: $0.id, plannedMinutes: $0.blockMinutes) }
        let json = String(decoding: try JSONEncoder().encode(tasks), as: UTF8.self)
        try db.execute(sql: "INSERT INTO planCommitment(planId, capturedAt, tasksJSON) VALUES(?, ?, ?) ON CONFLICT(planId) DO NOTHING",
                       arguments: [plan.id, now, json])
    }

    public func planCommitment(for day: DayKey) throws -> PlanCommitment? {
        try db.read { db in
            guard let plan = try DayPlan.filter(Column("day") == day && Column("deletedAt") == nil).fetchOne(db) else { return nil }
            return try planCommitment(plan.id, db)
        }
    }

    private func planCommitment(_ planId: String, _ db: Database) throws -> PlanCommitment? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM planCommitment WHERE planId = ?", arguments: [planId]) else { return nil }
        return PlanCommitment(capturedAt: row["capturedAt"], tasks: try JSONDecoder().decode([CommittedTask].self, from: Data((row["tasksJSON"] as String).utf8)))
    }

    public func dayCloseSummary(for day: DayKey) throws -> DayCloseSummary? {
        try db.read { try dayCloseSummary(day, $0) }
    }

    private func dayCloseSummary(_ day: DayKey, _ db: Database) throws -> DayCloseSummary? {
        guard let json = try String.fetchOne(db, sql: "SELECT summaryJSON FROM dayClose WHERE day = ?", arguments: [day]) else { return nil }
        return try JSONDecoder().decode(DayCloseSummary.self, from: Data(json.utf8))
    }

    public func dayCloseStatus(for day: DayKey, now: Date = Date(),
                               pendingRecovery: DayCloseRecoveryCheck? = nil) throws -> DayCloseResult {
        try db.read { try dayCloseStatus(day, now: now, pendingRecovery: pendingRecovery, $0) }
    }

    private func dayCloseStatus(_ day: DayKey, now: Date, pendingRecovery: DayCloseRecoveryCheck?,
                                _ db: Database) throws -> DayCloseResult {
        if let summary = try dayCloseSummary(day, db) { return .closed(summary) }
        guard let plan = try DayPlan.filter(Column("day") == day && Column("deletedAt") == nil).fetchOne(db) else {
            return .notEligible(.noCommittedPlan)
        }
        if plan.status == .closed { return .notEligible(.legacyClosed) }
        guard plan.status == .committed else { return .notEligible(.noCommittedPlan) }
        guard day <= DayKey(now) else { return .notEligible(.futureDay) }
        let tasks = try liveTasks(plan.id, db)
        guard !tasks.isEmpty else { return .notEligible(.emptyPlan) }
        let start = day.startDate, end = day.adding(days: 1).startDate
        let affectingSessions = try Session.fetchAll(db, sql: """
            SELECT session.* FROM session LEFT JOIN task ON task.id = session.taskId
            WHERE session.kind = 'focus' AND ((session.startedAt >= ? AND session.startedAt < ?) OR task.dayPlanId = ?)
              AND (session.endedAt IS NULL OR session.reflectionPending = 1)
            """, arguments: [start, end, plan.id])
        if affectingSessions.contains(where: \.isRunning) { return .deferred(.focus) }
        if !affectingSessions.isEmpty { return .deferred(.reflection) }
        if try Self.hasPendingRecovery(db, day: day) || (pendingRecovery?(db, day) ?? false) { return .deferred(.recovery) }
        if tasks.allSatisfy({ !$0.status.isOpen }) { return .ready(.resolved) }
        let minute = try dayCloseSettings(db).closeMinute
        let due = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: start)!
        return now >= due ? .ready(.due) : .notEligible(.notDue)
    }

    @discardableResult
    public func closeDay(_ day: DayKey = .today, now: Date = Date(),
                         pendingRecovery: DayCloseRecoveryCheck? = nil) throws -> DayCloseResult {
        let outcome = try db.write { try closeDay(day, now: now, pendingRecovery: pendingRecovery, $0) }
        if outcome.didClose { ChangeSignal.post(databasePath: db.path) }
        return outcome.result
    }

    private func closeDay(_ day: DayKey, now: Date, pendingRecovery: DayCloseRecoveryCheck?,
                          _ db: Database) throws -> (result: DayCloseResult, didClose: Bool) {
        let status = try dayCloseStatus(day, now: now, pendingRecovery: pendingRecovery, db)
        guard case .ready(let reason) = status else { return (status, false) }
        let plan = try DayPlan.filter(Column("day") == day && Column("deletedAt") == nil).fetchOne(db)!
        let sessions = try Session.filter(Column("kind") == SessionKind.focus && Column("startedAt") >= day.startDate
                                         && Column("startedAt") < day.adding(days: 1).startDate)
            .order(Column("startedAt"), Column("id")).fetchAll(db)
        let decisions = try RecordedBreakDecision.filter(sessions.map(\.id).contains(Column("sessionId"))).fetchAll(db)
            .sorted { $0.sessionId < $1.sessionId }
        let summary = DayCloseSummary(planId: plan.id, day: day, closedAt: now, reason: reason,
                                      tasks: try liveTasks(plan.id, db).map(DayCloseTaskOutcome.init), commitment: try planCommitment(plan.id, db),
                                      focusSessions: sessions.map { DayCloseSessionOutcome($0, at: now) }, breakDecisions: decisions,
                                      focusedSeconds: sessions.reduce(0) { $0 + $1.elapsed(at: now) })
        let json = String(decoding: try JSONEncoder().encode(summary), as: UTF8.self)
        try db.execute(sql: "INSERT INTO dayClose(planId, day, closedAt, summaryJSON) VALUES(?, ?, ?, ?)", arguments: [plan.id, day, now, json])
        try db.execute(sql: "UPDATE dayPlan SET status = 'closed', updatedAt = ? WHERE id = ?", arguments: [now, plan.id])
        return (.closed(summary), true)
    }

    /// At most 31 plans per transaction. Feed nextAfter into the next tick, then restart from nil.
    public func closeEligibleDays(now: Date = Date(), limit: Int = 7, after: DayKey? = nil,
                                  pendingRecovery: DayCloseRecoveryCheck? = nil) throws -> DayCloseBatch {
        guard (1...31).contains(limit) else { throw ThreeError.invalid("Close 1 to 31 days at a time.") }
        let outcome = try db.write { db in
            let days = try DayKey.fetchAll(db, sql: """
                SELECT day FROM dayPlan WHERE status = 'committed' AND deletedAt IS NULL AND day <= ?
                AND (? IS NULL OR day > ?) AND EXISTS (SELECT 1 FROM task WHERE dayPlanId = dayPlan.id AND deletedAt IS NULL)
                ORDER BY day LIMIT ?
                """, arguments: [DayKey(now), after, after, limit + 1])
            var didClose = false
            let attempts = try days.prefix(limit).map { day in
                let outcome = try closeDay(day, now: now, pendingRecovery: pendingRecovery, db)
                didClose = didClose || outcome.didClose
                return DayCloseAttempt(day: day, result: outcome.result)
            }
            return (batch: DayCloseBatch(attempts: attempts, nextAfter: days.count > limit ? attempts.last?.day : nil), didClose: didClose)
        }
        if outcome.didClose { ChangeSignal.post(databasePath: db.path) }
        return outcome.batch
    }

    public func recentDayCloses(limit: Int = 31) throws -> [DayCloseSummary] {
        guard (1...366).contains(limit) else { throw ThreeError.invalid("Read 1 to 366 day summaries.") }
        return try db.read { db in
            try String.fetchAll(db, sql: "SELECT summaryJSON FROM dayClose ORDER BY day DESC LIMIT ?", arguments: [limit])
                .map { try JSONDecoder().decode(DayCloseSummary.self, from: Data($0.utf8)) }
        }
    }

    /// The closed days either side of `day`, for stepping through every close rather than a
    /// recent window. `day` itself need not be closed.
    public func closedDays(around day: DayKey) throws -> (previous: DayKey?, next: DayKey?) {
        try db.read { db in
            (try DayKey.fetchOne(db, sql: "SELECT MAX(day) FROM dayClose WHERE day < ?", arguments: [day]),
             try DayKey.fetchOne(db, sql: "SELECT MIN(day) FROM dayClose WHERE day > ?", arguments: [day]))
        }
    }

    public func dayCloseReview(for day: DayKey) throws -> DayCloseReview? {
        try db.read { db in
            guard let summary = try dayCloseSummary(day, db) else { return nil }
            let ids = summary.tasks.map(\.id)
            let decisions = try CarryDecision.filter(ids.contains(Column("sourceTaskId"))).fetchAll(db)
            let decided = Set(decisions.map(\.sourceTaskId))
            let offers = try liveTasks(summary.planId, db).filter { $0.status.isOpen && !decided.contains($0.id) }
            return DayCloseReview(summary: summary, offers: try rows(for: offers, db), decisions: decisions)
        }
    }

    public func carryDecision(for taskId: String) throws -> CarryDecision? {
        try db.read { try CarryDecision.fetchOne($0, key: taskId) }
    }

    func carrySource(_ id: String, _ db: Database) throws -> (FocusTask, DayPlan) {
        guard let task = try FocusTask.fetchOne(db, key: id), task.deletedAt == nil else { throw ThreeError.noSuchTask(id) }
        guard task.status.isOpen else { throw ThreeError.invalid("Only open tasks can be carried or dismissed.") }
        guard let planId = task.dayPlanId, let plan = try DayPlan.fetchOne(db, key: planId), plan.deletedAt == nil else {
            throw ThreeError.invalid("That task isn't planned for a day.")
        }
        guard try runningSession(db)?.taskId != id else { throw ThreeError.invalid("Finish the running block before moving its task.") }
        guard try Session.filter(Column("taskId") == id && Column("reflectionPending") == true).fetchCount(db) == 0 else {
            throw ThreeError.invalid("Review the saved reflection before carrying or dismissing this task.")
        }
        return (task, plan)
    }

    @discardableResult
    public func dismissCarry(_ id: String, now: Date = Date()) throws -> CarryDecision {
        try write { db in
            if let existing = try CarryDecision.fetchOne(db, key: id) {
                guard existing.decision == .dismissed else { throw ThreeError.invalid("That work has already been accepted.") }
                return existing
            }
            var (task, _) = try carrySource(id, db)
            let decision = CarryDecision(sourceTaskId: id, decision: .dismissed, copyTaskId: nil, destinationDay: nil, decidedAt: now)
            try decision.insert(db)
            task.status = .dropped
            task.updatedAt = now
            try task.update(db)
            return decision
        }
    }
}
