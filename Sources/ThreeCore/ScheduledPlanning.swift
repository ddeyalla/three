import Darwin
import Foundation
import GRDB

public struct PlanningSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var localTime = "09:30"
    public var command = Self.defaultCommand

    public init() {}

    public static let defaultCommand = #"codex exec --ignore-user-config --ephemeral --skip-git-repo-check --sandbox read-only --cd "$THREE_PLANNING_DIRECTORY" --config "$THREE_CODEX_MCP_CONFIG" "$THREE_PLANNING_PROMPT""#

    public func isDue(at now: Date, calendar: Calendar = .current) -> Bool {
        let parts = localTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: now)
        return (components.hour! * 60 + components.minute!) >= parts[0] * 60 + parts[1]
    }

    func validate() throws {
        let parts = localTime.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0...23).contains(hour), (0...59).contains(minute) else {
            throw ThreeError.invalid("Planning time must use local HH:mm, from 00:00 through 23:59.")
        }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, command.utf8.count <= 16_384,
              !command.contains("\0") else { throw ThreeError.invalid("Enter a local command of at most 16 KiB.") }
    }
}

public enum PlanningRunStatus: String, Codable, DatabaseValueConvertible, Sendable {
    case running, succeeded, failed, timedOut, cancelled, interrupted, skipped
}

public enum PlanningTrigger: String, Codable, DatabaseValueConvertible, Sendable {
    case scheduled, test
}

public struct PlanningRun: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "planningRun"
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy { .timeIntervalSince1970 }
    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy { .timeIntervalSince1970 }
    public var id: String
    public var day: DayKey
    public var trigger: PlanningTrigger
    public var status: PlanningRunStatus
    public var startedAt: Date
    public var deadline: Date
    public var finishedAt: Date?
    public var command: String
    public var stdout = ""
    public var stderr = ""
    public var outputTruncated = false
    public var exitCode: Int32?
    public var error: String?
    public var processGroup: Int32?
    public var supervisorPID: Int32?
    public var draftPlanId: String?
    public var notifiedAt: Date?

    public func isWithinWindow(at now: Date) -> Bool {
        // Compare in the stored epoch so a persisted deadline stays exact at its boundary.
        let timestamp = now.timeIntervalSince1970
        return DayKey(now) == day && timestamp >= startedAt.timeIntervalSince1970 && timestamp < deadline.timeIntervalSince1970
    }
}

public struct PlanningNotice: Sendable {
    public let day: DayKey
    public let draftReady: Bool
}

/// This is a restriction on Three's MCP channel, not a sandbox for the configured shell command.
public struct ScheduledPlanningContext: Sendable {
    public let runID: String
    public let day: DayKey

    public init?(environment: [String: String]) throws {
        let id = environment["THREE_PLANNING_RUN"], date = environment["THREE_PLANNING_DATE"]
        guard id != nil || date != nil else { return nil }
        guard let id, UUID(uuidString: id)?.uuidString == id, let date, let day = DayKey(date),
              let database = environment["THREE_DB"], database.hasPrefix("/"), !database.contains("\0") else {
            throw ThreeError.invalid("Scheduled MCP needs a run UUID, canonical target date, and absolute THREE_DB.")
        }
        self.runID = id
        self.day = day
    }
}

extension Store {
    public func planningSettings() throws -> PlanningSettings {
        try db.read { try planningSettings($0) }
    }

    private func planningSettings(_ db: Database) throws -> PlanningSettings {
        guard let json = try String.fetchOne(db, sql: "SELECT value FROM preference WHERE key = 'planning'") else { return PlanningSettings() }
        let settings = try JSONDecoder().decode(PlanningSettings.self, from: Data(json.utf8))
        try settings.validate()
        return settings
    }

    public func setPlanningSettings(_ settings: PlanningSettings) throws {
        try settings.validate()
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        try write { db in
            try db.execute(sql: "INSERT INTO preference(key,value) VALUES('planning',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", arguments: [json])
        }
    }

    public func latestPlanningRun() throws -> PlanningRun? {
        try db.read { try PlanningRun.order(Column("rowid").desc).fetchOne($0) }
    }

    public func activePlanningRun() throws -> PlanningRun? {
        try db.read { try PlanningRun.filter(Column("status") == PlanningRunStatus.running).fetchOne($0) }
    }

    public func planningRun(_ id: String) throws -> PlanningRun? {
        try db.read { try PlanningRun.fetchOne($0, key: id) }
    }

    /// A prior attempt consumes automatic admission for that date. Only Test can retry a known failure.
    public func claimPlanningRun(trigger: PlanningTrigger, now: Date = Date(), calendar: Calendar = .current,
                                 timeout: TimeInterval = 600) throws -> PlanningRun? {
        guard timeout > 0, timeout <= 600 else { throw ThreeError.invalid("Planning timeout must be above zero and at most ten minutes.") }
        let run = try db.write { db -> PlanningRun? in
            let settings = try planningSettings(db)
            if trigger == .scheduled && (!settings.enabled || !settings.isDue(at: now, calendar: calendar)) { return nil }
            if try PlanningRun.filter(Column("status") == PlanningRunStatus.running).fetchCount(db) > 0 {
                if trigger == .test { throw ThreeError.invalid("A planning command is still running or its process state is unknown. No second command was started.") }
                return nil
            }
            let day = DayKey(now, calendar: calendar)
            let previous = try PlanningRun.filter(Column("day") == day).order(Column("rowid").desc).fetchOne(db)
            if trigger == .scheduled, previous != nil { return nil }
            if trigger == .test, let previous, previous.status == .succeeded || previous.status == .skipped {
                throw ThreeError.invalid("This day already has a completed planning attempt. Existing work is preserved.")
            }
            // A timer may end later today. Leave admission open until it does.
            if try Session.filter(Column("endedAt") == nil).fetchCount(db) > 0 {
                if trigger == .test { throw ThreeError.invalid("Stop the timer before testing planning.") }
                return nil
            }
            let existing = try DayPlan.filter(Column("day") == day).fetchOne(db)
            if trigger == .test, existing != nil { throw ThreeError.invalid("A plan already exists for today. Test preserves it.") }
            let run = PlanningRun(id: UUID().uuidString, day: day, trigger: trigger,
                                  status: existing == nil ? .running : .skipped, startedAt: now,
                                  deadline: now.addingTimeInterval(timeout), finishedAt: existing == nil ? nil : now,
                                  command: settings.command, error: existing == nil ? nil : "Existing plan preserved. No command was started.")
            try run.insert(db)
            return run
        }
        if run != nil { ChangeSignal.post(databasePath: db.path) }
        return run
    }

    public func recordPlanningSupervisor(_ id: String, pid: Int32) throws {
        try write { db in
            guard pid > 0, var run = try PlanningRun.fetchOne(db, key: id),
                  run.status == .running, run.supervisorPID == nil, run.processGroup == nil else {
                throw ThreeError.invalid("Planning already has a supervisor or its claim is inactive.")
            }
            run.supervisorPID = pid
            try run.update(db)
        }
    }

    public func recordPlanningProcess(_ id: String, group: Int32) throws {
        try write { db in
            guard var run = try PlanningRun.fetchOne(db, key: id), run.status == .running, run.processGroup == nil else {
                throw ThreeError.invalid("Planning claim is no longer active.")
            }
            run.processGroup = group
            try run.update(db)
        }
    }

    public func validateScheduledContext(_ context: ScheduledPlanningContext, now: Date = Date()) throws {
        try db.read { _ = try scheduledRun(context, now: now, $0) }
    }

    private func scheduledRun(_ context: ScheduledPlanningContext, now: Date, _ db: Database) throws -> PlanningRun {
        guard let run = try PlanningRun.fetchOne(db, key: context.runID), run.status == .running,
              run.day == context.day, run.isWithinWindow(at: now) else {
            throw ThreeError.invalid("Scheduled planning claim is inactive, expired, or outside its target local day.")
        }
        return run
    }

    public func createScheduledDraft(_ tasks: [NewTask], context: ScheduledPlanningContext, now: Date = Date()) throws {
        guard !tasks.isEmpty else { throw ThreeError.invalid("A scheduled draft needs at least one task.") }
        try write { db in
            var run = try scheduledRun(context, now: now, db)
            guard run.draftPlanId == nil,
                  try DayPlan.filter(Column("day") == context.day).fetchCount(db) == 0 else {
                throw ThreeError.invalid("Scheduled planning cannot replace existing work or write a second draft.")
            }
            guard try Session.filter(Column("endedAt") == nil).fetchCount(db) == 0 else { throw ThreeError.alreadyRunning }
            let plan = try planRow(context.day, source: .routine, db)
            for task in tasks { _ = try insertTask(task, plan: plan, source: .routine, db) }
            run.draftPlanId = plan.id
            try run.update(db)
        }
    }

    public func finishPlanningRun(_ id: String, result: PlanningCommandResult, now: Date = Date()) throws {
        try write { db in
            guard var run = try PlanningRun.fetchOne(db, key: id), run.status == .running else { return }
            run.stdout = result.stdout
            run.stderr = result.stderr
            run.outputTruncated = result.outputTruncated
            run.exitCode = result.exitCode
            run.status = result.status
            run.error = result.error
            run.finishedAt = now
            if !result.cleanupConfirmed {
                run.status = .running
                run.finishedAt = nil
                run.error = "Command ended, but process-group cleanup is not confirmed. Further planning is blocked until the group is gone."
            }
            if run.status == .succeeded {
                let plan = try run.draftPlanId.flatMap { try DayPlan.fetchOne(db, key: $0) }
                if plan?.status != .draft || plan?.deletedAt != nil {
                    run.status = .failed
                    run.error = "Command exited successfully but did not leave its scheduled draft for review."
                }
            }
            try run.update(db)
        }
    }

    /// Never signal a recovered PID. A missing process group proves only that the old command is gone.
    public func recoverPlanningRun() throws {
        guard let run = try activePlanningRun(), let group = run.processGroup else { return }
        if let supervisor = run.supervisorPID {
            guard kill(supervisor, 0) == -1, errno == ESRCH else { return }
        }
        guard kill(-group, 0) == -1, errno == ESRCH else { return }
        try finishPlanningRun(run.id, result: .init(status: .interrupted, stdout: run.stdout, stderr: run.stderr,
                                                  outputTruncated: run.outputTruncated, exitCode: run.exitCode,
                                                  error: "The process group is gone without a confirmed final result. Automatic retry is disabled. Inspect today's work before Test."))
    }

    /// Claim before dispatch. Permission denial or a crash cannot cause repeated banners on later ticks.
    public func takePlanningNotice(day: DayKey, now: Date = Date()) throws -> PlanningNotice? {
        let notice = try db.write { db -> PlanningNotice? in
            guard try PlanningRun.filter(Column("day") == day && Column("notifiedAt") != nil).fetchCount(db) == 0,
                  var run = try PlanningRun.filter(Column("day") == day).order(Column("rowid").desc).fetchOne(db),
                  run.status != .running, run.status != .skipped else { return nil }
            let plan = try DayPlan.filter(Column("day") == day && Column("deletedAt") == nil).fetchOne(db)
            if let plan, plan.status != .draft { return nil }
            run.notifiedAt = now
            try run.update(db)
            return PlanningNotice(day: day, draftReady: plan?.status == .draft)
        }
        if notice != nil { ChangeSignal.post(databasePath: db.path) }
        return notice
    }
}
