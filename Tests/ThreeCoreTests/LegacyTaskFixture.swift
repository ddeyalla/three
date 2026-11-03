import Foundation
import GRDB
@testable import ThreeCore

extension Store {
    @discardableResult
    func addLegacyTaskFixture(_ new: NewTask, day: DayKey = .today, source: Source) throws -> FocusTask {
        try db.write { db in
            let plan = try planRow(day, source: source, db)
            let categoryId = try category(new.category, db).id
            let id = UUID().uuidString
            let position = (try Int.fetchOne(db, sql: "SELECT MAX(position) FROM task WHERE dayPlanId = ?", arguments: [plan.id]) ?? -1) + 1
            try db.execute(sql: """
                INSERT INTO task(id, dayPlanId, position, title, categoryId, blockMinutes, scheduledStart,
                                 strict, status, linearRef, notes, createdBy, updatedAt)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, 'todo', ?, ?, ?, ?)
                """, arguments: [id, plan.id, position, new.title, categoryId, new.blockMinutes, new.scheduledStart,
                                 new.strict, new.linearRef, new.notes, source, Date()])
            return try FocusTask.fetchOne(db, key: id)!
        }
    }
}
