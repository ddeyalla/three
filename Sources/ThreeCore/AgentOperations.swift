import Foundation
import GRDB

extension Store {
    public func carryover(before day: DayKey) throws -> [TaskRow] {
        try inbox(today: day).filter { $0.task.dayPlanId != nil }
    }

    /// Inclusive local dates, bounded to one year per read.
    public func history(from: DayKey, through to: DayKey) throws -> [Session] {
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: from.startDate, to: to.startDate).day!
        guard (0..<366).contains(days) else {
            throw ThreeError.invalid("History needs an ordered range of at most 366 days.")
        }
        return try db.read { db in
            try Session.filter(Column("startedAt") >= from.startDate && Column("startedAt") < to.adding(days: 1).startDate)
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
