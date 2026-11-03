import Foundation
import GRDB

public struct ReflectionPrompt: Sendable {
    public let session: Session
    public let openedAt: Date

    public init(session: Session, openedAt: Date) {
        self.session = session
        self.openedAt = openedAt
    }

    public var deadline: Date { openedAt.addingTimeInterval(120) }

    public func matches(_ current: Session?) -> Bool {
        guard let current else { return false }
        return current.id == session.id && current.kind == .focus && current.isRunning
            && current.plannedSeconds == session.plannedSeconds && current.pausedSeconds == session.pausedSeconds
            && current.pausedAt == session.pausedAt
            && current.recoveryTrimSeconds == session.recoveryTrimSeconds
    }
}

public struct DeferredReflection: Identifiable, Sendable {
    public let session: Session
    public let task: TaskRow?
    public var id: String { session.id }
}

extension Store {
    public func deferredReflections() throws -> [DeferredReflection] {
        try db.read { db in
            try Session.filter(Column("reflectionPending") == true && Column("endedAt") != nil)
                .order(Column("endedAt"), Column("id")).fetchAll(db).map { session in
                    let task = try session.taskId.flatMap { try FocusTask.fetchOne(db, key: $0) }
                    let row = try task.flatMap { try rows(for: [$0], db).first }
                    return DeferredReflection(session: session, task: row)
                }
        }
    }

    @discardableResult
    public func deferReflection(_ prompt: ReflectionPrompt, note: String? = nil, now: Date = Date()) throws -> Bool {
        guard now >= prompt.deadline else { return false }
        return try write { db in
            guard var current = try Session.fetchOne(db, key: prompt.session.id), prompt.matches(current) else { return false }
            current.reflectionPending = true
            try finishFocus(&current, outcome: .progress, rating: .okay, note: note, markTaskDone: false, now: now, db)
            return true
        }
    }

    public func saveDeferredReflection(_ id: String, outcome: Outcome, rating: FocusRating, note: String?,
                                       now: Date = Date()) throws {
        try write { db in
            guard var session = try Session.fetchOne(db, key: id), session.reflectionPending, !session.isRunning else {
                throw ThreeError.invalid("This reflection has already been answered or dismissed.")
            }
            session.outcome = outcome
            session.focusRating = rating
            session.note = note?.isEmpty == true ? nil : note
            session.reflectionPending = false
            session.updatedAt = now
            try session.update(db)
        }
    }

    public func dismissDeferredReflection(_ id: String, now: Date = Date()) throws {
        try write { db in
            try db.execute(sql: "UPDATE session SET reflectionPending = 0, updatedAt = ? WHERE id = ? AND reflectionPending = 1 AND endedAt IS NOT NULL",
                           arguments: [now, id])
        }
    }
}
