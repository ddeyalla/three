import Foundation
import GRDB

extension Store {
    /// Open tasks left on days before `day`, oldest day first. Undated tasks belong to `inbox()`.
    public func carryover(before day: DayKey) throws -> [TaskRow] {
        try db.read { db in
            let leftover = try FocusTask.fetchAll(db, sql: """
                SELECT task.* FROM task JOIN dayPlan ON dayPlan.id = task.dayPlanId
                WHERE dayPlan.day < ? AND dayPlan.deletedAt IS NULL AND task.deletedAt IS NULL
                ORDER BY dayPlan.day, task.position
                """, arguments: [day])
            return try rows(for: leftover.filter { $0.status.isOpen }, db)
        }
    }

    /// Inclusive local dates, bounded to one year per read.
    public func history(from: DayKey, through to: DayKey) throws -> [Session] {
        let range = try HistoryRange(from: from, through: to)
        return try db.read { db in
            try Session.filter(Column("startedAt") >= range.start && Column("startedAt") < range.end)
                .order(Column("startedAt"), Column("id")).fetchAll(db)
        }
    }

    public func setTaskStrict(_ id: String) throws {
        try write { db in
            var task = try editableTask(id, db)
            guard !task.strict else { return }
            task.strict = true
            task.updatedAt = Date()
            try task.update(db)
        }
    }
}
