import Foundation
import GRDB
import notify

/// Cross-process "the database changed" ping. GRDB observation only sees writes from
/// its own process, so every write posts this and the app reloads on receipt.
public enum ChangeSignal {
    static let name = "com.deyalla.three.changed"

    public static func post() { notify_post(name) }

    /// Calls `handler` on the main queue after any process writes. Keep the token alive.
    public static func observe(_ handler: @escaping () -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(name, &token, .main) { _ in handler() }
        return token
    }
}

public struct TaskRow: Hashable, Identifiable, Sendable {
    public var task: FocusTask
    public var category: Category
    public var focusedSeconds: TimeInterval
    public var steps: [Step] = []
    public var tags: [Tag] = []
    public var id: String { task.id }
    public var blockSeconds: TimeInterval { TimeInterval(task.blockMinutes * 60) }
    public var progress: Double { min(1, focusedSeconds / max(1, blockSeconds)) }
}

/// Everything the Today screen, menu bar and `three today` show.
public struct DaySnapshot: Sendable {
    public var day: DayKey
    public var plan: DayPlan?
    public var tasks: [TaskRow]
    public var sessions: [Session]
    public var running: Session?
    public var runningTask: TaskRow?
    public var categories: [Category]
    public var preferences: Preferences
    /// When the snapshot was read; `focusedSeconds` counts the running session up to here.
    public var takenAt: Date

    public var plannedMinutes: Int { tasks.filter { $0.task.status != .dropped && $0.task.status != .carried }.reduce(0) { $0 + $1.task.blockMinutes } }
    public var doneCount: Int { tasks.filter { $0.task.status == .done }.count }
    public var activeTaskCount: Int { tasks.filter { $0.task.status != .dropped && $0.task.status != .carried }.count }
    public var nextTask: TaskRow? { tasks.first { $0.task.status.isOpen && $0.id != running?.taskId } }

    /// A task's focused time at `now`, counting the running session live.
    public func focusedSeconds(of row: TaskRow, at now: Date) -> TimeInterval {
        guard let running, running.taskId == row.id else { return row.focusedSeconds }
        return row.focusedSeconds + running.elapsed(at: now) - running.elapsed(at: takenAt)
    }

    public func focusSeconds(at now: Date) -> TimeInterval {
        sessions.filter { $0.kind == .focus }.reduce(0) { $0 + $1.elapsed(at: now) }
    }
}

public struct NewTask: Sendable {
    public var title: String
    public var category: String
    public var blockMinutes: Int
    public var scheduledStart: Date?
    public var strict: Bool
    public var linearRef: String?
    public var notes: String
    /// Tag names; missing tags are created.
    public var tags: [String]

    public init(title: String, category: String, blockMinutes: Int, scheduledStart: Date? = nil,
                strict: Bool = false, linearRef: String? = nil, notes: String = "", tags: [String] = []) {
        self.title = title
        self.category = category
        self.blockMinutes = blockMinutes
        self.scheduledStart = scheduledStart
        self.strict = strict
        self.linearRef = linearRef
        self.notes = notes
        self.tags = tags
    }
}

extension Store {
    @discardableResult
    func write<T>(_ body: (Database) throws -> T) throws -> T {
        let result = try db.write(body)
        ChangeSignal.post()
        return result
    }

    // MARK: Reads

    public func snapshot(for day: DayKey = .today) throws -> DaySnapshot {
        try db.read { db in
            let categories = try Category.filter(Column("deletedAt") == nil).order(Column("position")).fetchAll(db)
            let plan = try DayPlan.filter(Column("day") == day && Column("deletedAt") == nil).fetchOne(db)
            let tasks = try plan.map {
                try FocusTask.filter(Column("dayPlanId") == $0.id && Column("deletedAt") == nil)
                    .order(Column("position")).fetchAll(db)
            } ?? []
            let start = day.startDate, end = day.adding(days: 1).startDate
            let sessions = try Session.filter(Column("startedAt") >= start && Column("startedAt") < end)
                .order(Column("startedAt")).fetchAll(db)
            let running = try Session.filter(Column("endedAt") == nil).fetchOne(db)
            let now = Date()
            let rows = try self.rows(for: tasks, db, now: now)
            var runningTask = rows.first { $0.id == running?.taskId }
            if runningTask == nil, let taskId = running?.taskId, let t = try FocusTask.fetchOne(db, key: taskId) {
                runningTask = try self.rows(for: [t], db, now: now).first
            }
            return DaySnapshot(day: day, plan: plan, tasks: rows, sessions: sessions, running: running,
                               runningTask: runningTask, categories: categories, preferences: try preferences(db), takenAt: now)
        }
    }

    public func categories() throws -> [Category] {
        try db.read { try Category.filter(Column("deletedAt") == nil).order(Column("position")).fetchAll($0) }
    }

    // MARK: Planning

    func category(_ nameOrId: String, _ db: Database) throws -> Category {
        let all = try Category.filter(Column("deletedAt") == nil).fetchAll(db)
        if let c = all.first(where: { $0.id == nameOrId || $0.name.caseInsensitiveCompare(nameOrId) == .orderedSame }) {
            return c
        }
        throw ThreeError.noSuchCategory(nameOrId)
    }

    func planRow(_ day: DayKey, source: Source, _ db: Database) throws -> DayPlan {
        if let p = try DayPlan.filter(Column("day") == day && Column("deletedAt") == nil).fetchOne(db) { return p }
        let now = Date()
        let p = DayPlan(id: UUID().uuidString, day: day, status: .draft, source: source,
                        createdAt: now, committedAt: nil, updatedAt: now, deletedAt: nil)
        try p.insert(db)
        return p
    }

    func requireEditable(_ plan: DayPlan) throws {
        guard plan.deletedAt == nil, plan.status != .closed else {
            throw ThreeError.invalid("A closed day cannot be changed.")
        }
    }

    func editableTask(_ id: String, _ db: Database) throws -> FocusTask {
        guard let task = try FocusTask.fetchOne(db, key: id), task.deletedAt == nil else {
            throw ThreeError.noSuchTask(id)
        }
        if let planId = task.dayPlanId, let plan = try DayPlan.fetchOne(db, key: planId) {
            try requireEditable(plan)
        }
        return task
    }

    func liveTasks(_ planId: String?, _ db: Database) throws -> [FocusTask] {
        try FocusTask.filter(Column("dayPlanId") == planId && Column("deletedAt") == nil)
            .order(Column("position")).fetchAll(db)
    }

    /// Inserts into `plan`, or into the inbox when `plan` is nil. Only a day counts toward the five-task cap.
    func insertTask(_ new: NewTask, plan: DayPlan?, source: Source, _ db: Database) throws -> FocusTask {
        if let plan { try requireEditable(plan) }
        let title = new.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ThreeError.invalid("A task needs a title.") }
        guard (5...480).contains(new.blockMinutes) else { throw ThreeError.invalid("Blocks are 5 to 480 minutes.") }
        let existing = try liveTasks(plan?.id, db)
        if plan != nil { try checkCap(existing) }
        let t = FocusTask(id: UUID().uuidString, dayPlanId: plan?.id, position: (existing.map(\.position).max() ?? -1) + 1,
                          title: title, categoryId: try category(new.category, db).id, blockMinutes: new.blockMinutes,
                          scheduledStart: new.scheduledStart, strict: new.strict, status: .todo,
                          linearRef: new.linearRef, notes: new.notes, createdBy: source, updatedAt: Date(), deletedAt: nil)
        try t.insert(db)
        try link(t.id, to: new.tags, db)
        return t
    }

    func checkCap(_ dayTasks: [FocusTask]) throws {
        guard dayTasks.filter({ $0.status != .dropped && $0.status != .carried }).count < Rules.maxTasks else {
            throw ThreeError.tooManyTasks
        }
    }

    @discardableResult
    public func addTask(_ new: NewTask, day: DayKey = .today, source: Source) throws -> FocusTask {
        try write { db in try insertTask(new, plan: planRow(day, source: source, db), source: source, db) }
    }

    /// Replaces the day's untouched tasks with `tasks`. Tasks that already have focus time stay.
    public func setPlan(_ tasks: [NewTask], day: DayKey, source: Source, commit: Bool) throws {
        try write { db in
            var plan = try planRow(day, source: source, db)
            try requireEditable(plan)
            guard commit || plan.status == .draft else {
                throw ThreeError.invalid("A draft cannot replace a committed plan. Replan explicitly with commit=true.")
            }
            let worked = Set(try String.fetchAll(db, sql: "SELECT DISTINCT taskId FROM session WHERE taskId IS NOT NULL"))
            for var t in try liveTasks(plan.id, db) where !worked.contains(t.id) {
                t.deletedAt = Date(); t.updatedAt = Date()
                try t.update(db)
            }
            for new in tasks { _ = try insertTask(new, plan: plan, source: source, db) }
            plan.source = source
            plan.updatedAt = Date()
            if commit { plan.status = .committed; plan.committedAt = Date() }
            try plan.update(db)
        }
    }

    public func commit(day: DayKey = .today) throws {
        try write { db in
            guard var plan = try DayPlan.filter(Column("day") == day && Column("deletedAt") == nil).fetchOne(db) else {
                throw ThreeError.invalid("No plan for \(day).")
            }
            try requireEditable(plan)
            plan.status = .committed
            plan.committedAt = plan.committedAt ?? Date()
            plan.updatedAt = Date()
            try plan.update(db)
        }
    }

    public func updateTask(_ id: String, title: String? = nil, category: String? = nil,
                           blockMinutes: Int? = nil, status: TaskStatus? = nil, notes: String? = nil) throws {
        try write { db in
            var t = try editableTask(id, db)
            if let title {
                let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { throw ThreeError.invalid("A task needs a title.") }
                t.title = clean
            }
            if let category { t.categoryId = try self.category(category, db).id }
            if let blockMinutes {
                guard (5...480).contains(blockMinutes) else { throw ThreeError.invalid("Blocks are 5 to 480 minutes.") }
                t.blockMinutes = blockMinutes
            }
            if let status {
                guard t.status != .carried || status == .carried else {
                    throw ThreeError.invalid("That task already moved to another day.")
                }
                if status == .active, try runningSession(db)?.taskId != id {
                    throw ThreeError.invalid("Start focus to activate a task.")
                }
                if let planId = t.dayPlanId, (t.status == .dropped || t.status == .carried),
                   status != .dropped && status != .carried {
                    try checkCap(liveTasks(planId, db))
                }
                t.status = status
            }
            if let notes { t.notes = notes }
            t.updatedAt = Date()
            try t.update(db)
            if let status { try setDone(id, status == .done, at: t.updatedAt, db) }
            // A closed task can't keep a timer running: done ends its block as done, otherwise as stopped.
            if let status, !status.isOpen, var s = try runningSession(db), s.taskId == id {
                if status == .done { s.outcome = .done }
                try end(&s, reason: status == .done ? .completed : .stopped, at: Date(), db)
            }
        }
    }

    /// Moves a task to `index` among the day's visible tasks. Dropped tasks are hidden, so they sink to the end.
    public func moveTask(_ id: String, to index: Int) throws {
        try write { db in
            let moving = try editableTask(id, db)
            let others = try liveTasks(moving.dayPlanId, db).filter { $0.id != id }
            var tasks = others.filter { $0.status != .dropped }
            tasks.insert(moving, at: max(0, min(index, tasks.count)))
            tasks += others.filter { $0.status == .dropped }
            for (i, var t) in tasks.enumerated() where t.position != i {
                t.position = i; t.updatedAt = Date()
                try t.update(db)
            }
        }
    }

    public func removeTask(_ id: String) throws {
        try write { db in
            var t = try editableTask(id, db)
            let worked = try Session.filter(Column("taskId") == id).fetchCount(db) > 0
            if var s = try runningSession(db), s.taskId == id { try end(&s, reason: .stopped, at: Date(), db) }
            if worked { t.status = .dropped } else { t.deletedAt = Date() }
            t.updatedAt = Date()
            try t.update(db)
        }
    }

    // MARK: Timer

    private func runningSession(_ db: Database) throws -> Session? {
        try Session.filter(Column("endedAt") == nil).fetchOne(db)
    }

    private func end(_ s: inout Session, reason: EndReason, at now: Date, _ db: Database) throws {
        if let pausedAt = s.pausedAt {
            s.pausedSeconds += Int(now.timeIntervalSince(pausedAt))
            s.pausedAt = nil
        }
        s.endedAt = now
        s.endReason = reason
        s.updatedAt = now
        try s.update(db)
    }

    /// Starts a focus session on `taskId`, or on the next open task of today.
    /// A running break is ended first; a running focus session is an error.
    @discardableResult
    public func startFocus(taskId: String? = nil, minutes: Int? = nil, now: Date = Date()) throws -> Session {
        try write { try startFocus(taskId: taskId, minutes: minutes, now: now, $0) }
    }

    @discardableResult
    private func startFocus(taskId: String?, minutes: Int? = nil, now: Date, _ db: Database) throws -> Session {
        if var running = try runningSession(db) {
            guard running.kind == .break else { throw ThreeError.alreadyRunning }
            try end(&running, reason: .completed, at: now, db)
        }
        var task: FocusTask
        if let taskId {
            guard let t = try FocusTask.fetchOne(db, key: taskId), t.deletedAt == nil else { throw ThreeError.noSuchTask(taskId) }
            task = t
        } else {
            guard let plan = try DayPlan.filter(Column("day") == DayKey(now)).fetchOne(db),
                  let t = try liveTasks(plan.id, db).first(where: { $0.status.isOpen }) else { throw ThreeError.nothingToStart }
            task = t
        }
        task = try editableTask(task.id, db)
        guard task.status.isOpen else { throw ThreeError.invalid("Reopen the task before starting it.") }
        guard task.dayPlanId != nil else { throw ThreeError.invalid("Plan it for today before starting it.") }
        let focused = try Session.filter(Column("taskId") == task.id && Column("kind") == SessionKind.focus)
            .fetchAll(db).reduce(0) { $0 + $1.elapsed(at: now) }
        let left = Int((TimeInterval(task.blockMinutes * 60) - focused) / 60)
        let session = try preferences(db).sessionMinutes
        let planned = minutes ?? (left >= 5 ? min(left, session) : session)
        guard (1...480).contains(planned) else { throw ThreeError.invalid("Sessions are 1 to 480 minutes.") }
        let s = Session(id: UUID().uuidString, taskId: task.id, kind: .focus, plannedSeconds: planned * 60,
                        startedAt: now, pausedAt: nil, pausedSeconds: 0, endedAt: nil, endReason: nil,
                        outcome: nil, focusRating: nil, note: nil, updatedAt: now)
        try s.insert(db)
        task.status = .active
        task.updatedAt = now
        try task.update(db)
        // Starting work on a draft is the commitment.
        if let planId = task.dayPlanId, var plan = try DayPlan.fetchOne(db, key: planId), plan.status == .draft {
            plan.status = .committed
            plan.committedAt = now
            plan.updatedAt = now
            try plan.update(db)
        }
        return s
    }

    /// Moves an open task to tomorrow's plan; today keeps it as `carried`.
    @discardableResult
    public func pushToTomorrow(_ id: String, now: Date = Date()) throws -> FocusTask {
        try write { db in
            var t = try editableTask(id, db)
            guard t.status.isOpen else { throw ThreeError.invalid("Only open tasks can be carried to tomorrow.") }
            guard try runningSession(db)?.taskId != id else {
                throw ThreeError.invalid("Finish the running block before moving its task.")
            }
            guard let planId = t.dayPlanId, let plan = try DayPlan.fetchOne(db, key: planId) else {
                throw ThreeError.invalid("That task isn't planned for a day.")
            }
            let tomorrow = try planRow(plan.day.adding(days: 1), source: .app, db)
            let copy = try insertTask(NewTask(title: t.title, category: t.categoryId, blockMinutes: t.blockMinutes,
                                              strict: t.strict, linearRef: t.linearRef, notes: t.notes,
                                              tags: try self.tags(for: [id], db)[id]?.map(\.name) ?? []),
                                      plan: tomorrow, source: t.createdBy, db)
            for var step in try Step.filter(Column("taskId") == id).fetchAll(db) {
                step.id = UUID().uuidString
                step.taskId = copy.id
                step.updatedAt = now
                try step.insert(db)
            }
            t.status = .carried
            t.updatedAt = now
            try t.update(db)
            return copy
        }
    }

    /// Closes a running break at its planned end, even if the app noticed late.
    public func finishBreakIfDue(now: Date = Date()) throws {
        let due = try db.read { db in try runningSession(db) }.flatMap { s in
            s.kind == .break && !s.isPaused && s.remaining(at: now) <= 0 ? s : nil
        }
        guard due != nil else { return }
        try write { db in
            guard var s = try runningSession(db), s.kind == .break, !s.isPaused, s.remaining(at: now) <= 0 else { return }
            try end(&s, reason: .completed, at: min(now, s.plannedEnd), db)
        }
    }

    public func pause(now: Date = Date()) throws {
        try write { db in
            guard var s = try runningSession(db) else { throw ThreeError.noRunningSession }
            guard s.pausedAt == nil else { return }
            s.pausedAt = now; s.updatedAt = now
            try s.update(db)
        }
    }

    public func resume(now: Date = Date()) throws {
        try write { db in
            guard var s = try runningSession(db) else { throw ThreeError.noRunningSession }
            guard let pausedAt = s.pausedAt else { return }
            s.pausedSeconds += Int(now.timeIntervalSince(pausedAt))
            s.pausedAt = nil; s.updatedAt = now
            try s.update(db)
        }
    }

    public func extend(minutes: Int, expectedSession: Session? = nil, now: Date = Date()) throws {
        guard (1...480).contains(minutes) else { throw ThreeError.invalid("Add 1 to 480 minutes.") }
        try write { db in
            guard var s = try runningSession(db) else { throw ThreeError.noRunningSession }
            if let expectedSession, !ReflectionPrompt(session: expectedSession, openedAt: now).matches(s) {
                throw ThreeError.invalid("This focus block changed. Open its reflection again.")
            }
            // Extending an overrun block adds time from now, not from the old end.
            let overrun = max(0, -Int(s.remaining(at: now)))
            s.plannedSeconds += overrun + minutes * 60
            s.updatedAt = now
            try s.update(db)
        }
    }

    /// Ends whatever is running without a reflection.
    public func stop(now: Date = Date()) throws {
        try write { db in
            guard var s = try runningSession(db) else { throw ThreeError.noRunningSession }
            try end(&s, reason: .stopped, at: now, db)
            if let taskId = s.taskId, var t = try FocusTask.fetchOne(db, key: taskId), t.status == .active {
                t.status = .partial; t.updatedAt = now
                try t.update(db)
            }
        }
    }

    /// Ends the running focus session with the reflection answers.
    public func finishFocus(outcome: Outcome, rating: FocusRating, note: String?, markTaskDone: Bool,
                            expectedSession: Session? = nil, continuation: FocusContinuation = .stop,
                            now: Date = Date()) throws {
        try write { db in
            guard var s = try runningSession(db), s.kind == .focus else { throw ThreeError.noRunningSession }
            if let expectedSession, !ReflectionPrompt(session: expectedSession, openedAt: now).matches(s) {
                throw ThreeError.invalid("This focus block changed. Open its reflection again.")
            }
            try finishFocus(&s, outcome: outcome, rating: rating, note: note, markTaskDone: markTaskDone, now: now, db)
            switch continuation {
            case .stop: break
            case .break: try startBreak(minutes: nil, now: now, db)
            case .task(let id): try startFocus(taskId: id, now: now, db)
            }
        }
    }

    func finishFocus(_ session: inout Session, outcome: Outcome, rating: FocusRating, note: String?,
                     markTaskDone: Bool, now: Date, _ db: Database) throws {
        session.outcome = outcome
        session.focusRating = rating
        session.note = note?.isEmpty == true ? nil : note
        try end(&session, reason: .completed, at: now, db)
        if let taskId = session.taskId, var task = try FocusTask.fetchOne(db, key: taskId) {
            task.status = markTaskDone ? .done : .partial
            task.updatedAt = now
            try task.update(db)
            try setDone(taskId, markTaskDone, at: now, db)
        }
    }

    /// Stamps when a task became done, keeping the first stamp if it was already done; clears it otherwise.
    func setDone(_ id: String, _ done: Bool, at now: Date, _ db: Database) throws {
        try db.execute(sql: "UPDATE task SET doneAt = CASE WHEN ? THEN COALESCE(doneAt, ?) ELSE NULL END WHERE id = ?",
                       arguments: [done, now, id])
    }

    public func setTaskStatus(_ id: String, _ status: TaskStatus) throws {
        try updateTask(id, status: status)
    }

    /// 5 minutes normally; 15 once you've focused ~100 minutes since the last long break.
    public func suggestedBreakMinutes(now: Date = Date()) throws -> Int {
        try db.read { try suggestedBreakMinutes(now: now, $0) }
    }

    private func suggestedBreakMinutes(now: Date, _ db: Database) throws -> Int {
        let prefs = try preferences(db)
        let today = try Session.filter(Column("startedAt") >= DayKey(now).startDate).order(Column("startedAt")).fetchAll(db)
        let lastLong = today.last { $0.kind == .break && $0.elapsed(at: now) >= TimeInterval(prefs.longBreakMinutes * 60 - 60) }
        let since = today.filter { $0.kind == .focus && $0.startedAt > (lastLong?.startedAt ?? .distantPast) }
        let focused = since.reduce(0) { $0 + $1.elapsed(at: now) }
        return focused >= TimeInterval(prefs.longBreakAfterMinutes * 60) ? prefs.longBreakMinutes : prefs.shortBreakMinutes
    }

    @discardableResult
    public func startBreak(minutes: Int? = nil, now: Date = Date()) throws -> Session {
        try write { try startBreak(minutes: minutes, now: now, $0) }
    }

    @discardableResult
    private func startBreak(minutes: Int?, now: Date, _ db: Database) throws -> Session {
        let planned = try minutes ?? suggestedBreakMinutes(now: now, db)
        guard (1...120).contains(planned) else { throw ThreeError.invalid("Breaks are 1 to 120 minutes.") }
        if var running = try runningSession(db) {
            guard running.kind == .break else { throw ThreeError.alreadyRunning }
            try end(&running, reason: .stopped, at: now, db)
        }
        let s = Session(id: UUID().uuidString, taskId: nil, kind: .break, plannedSeconds: planned * 60,
                        startedAt: now, pausedAt: nil, pausedSeconds: 0, endedAt: nil, endReason: nil,
                        outcome: nil, focusRating: nil, note: nil, updatedAt: now)
        try s.insert(db)
        return s
    }
}
