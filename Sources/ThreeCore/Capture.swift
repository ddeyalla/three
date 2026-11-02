import Foundation
import GRDB

// Inbox, steps, categories and preferences: everything around the day's plan.

extension Store {
    // MARK: Preferences

    func preferences(_ db: Database) throws -> Preferences {
        guard let json = try String.fetchOne(db, sql: "SELECT value FROM preference WHERE key = 'timer'") else {
            return Preferences()
        }
        return (try? JSONDecoder().decode(Preferences.self, from: Data(json.utf8))) ?? Preferences()
    }

    public func preferences() throws -> Preferences {
        try db.read { try preferences($0) }
    }

    public func setPreferences(_ p: Preferences) throws {
        let checks = [(p.sessionMinutes, 5...240), (p.shortBreakMinutes, 1...60), (p.longBreakMinutes, 1...120),
                      (p.longBreakAfterMinutes, 15...600), (p.defaultBlockMinutes, 5...480)]
        guard checks.allSatisfy({ $0.1.contains($0.0) }) else { throw ThreeError.invalid("That length is out of range.") }
        let json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        try write { db in
            try db.execute(sql: "INSERT INTO preference(key, value) VALUES('timer', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                           arguments: [json])
        }
    }

    // MARK: Inbox

    /// Open tasks with no day yet, plus open tasks left behind on earlier days (those first, oldest day first).
    public func inbox(today: DayKey = .today) throws -> [TaskRow] {
        try db.read { db in
            let leftover = try FocusTask.fetchAll(db, sql: """
                SELECT task.* FROM task JOIN dayPlan ON dayPlan.id = task.dayPlanId
                WHERE dayPlan.day < ? AND dayPlan.deletedAt IS NULL AND task.deletedAt IS NULL
                ORDER BY dayPlan.day, task.position
                """, arguments: [today])
            let unplanned = try FocusTask.filter(Column("dayPlanId") == nil && Column("deletedAt") == nil)
                .order(Column("position")).fetchAll(db)
            let tasks = (leftover + unplanned).filter { $0.status.isOpen }
            let categories = Dictionary(uniqueKeysWithValues: try Category.fetchAll(db).map { ($0.id, $0) })
            let steps = try self.steps(for: tasks.map(\.id), db)
            return tasks.compactMap { t in
                categories[t.categoryId].map { TaskRow(task: t, category: $0, focusedSeconds: 0, steps: steps[t.id] ?? []) }
            }
        }
    }

    @discardableResult
    public func addToInbox(_ new: NewTask, source: Source) throws -> FocusTask {
        try write { db in try insertTask(new, plan: nil, source: source, db) }
    }

    /// Plans a task for `day`, or returns it to the inbox when `day` is nil. Planning respects the five-task cap.
    public func schedule(_ id: String, on day: DayKey?) throws {
        try write { db in
            guard var t = try FocusTask.fetchOne(db, key: id), t.deletedAt == nil else { throw ThreeError.noSuchTask(id) }
            if try Session.filter(Column("endedAt") == nil && Column("taskId") == id).fetchCount(db) > 0 {
                throw ThreeError.invalid("Finish the running block before moving its task.")
            }
            let plan = try day.map { try planRow($0, source: .app, db) }
            guard plan?.id != t.dayPlanId else { return }
            let destination = try liveTasks(plan?.id, db)
            if plan != nil { try checkCap(destination) }
            t.dayPlanId = plan?.id
            t.position = (destination.map(\.position).max() ?? -1) + 1
            if t.status == .carried { throw ThreeError.invalid("That task already moved to another day.") }
            if t.status == .dropped { t.status = .todo }
            t.updatedAt = Date()
            try t.update(db)
        }
    }

    /// The next `days` days after `from`, each with its planned tasks. Empty days are included.
    public func upcoming(days: Int = 7, from: DayKey = .today) throws -> [DaySnapshot] {
        try (1...days).map { try snapshot(for: from.adding(days: $0)) }
    }

    // MARK: Steps

    func steps(for taskIds: [String], _ db: Database) throws -> [String: [Step]] {
        guard !taskIds.isEmpty else { return [:] }
        return Dictionary(grouping: try Step.filter(taskIds.contains(Column("taskId"))).order(Column("position")).fetchAll(db),
                          by: \.taskId)
    }

    @discardableResult
    public func addStep(to taskId: String, title: String) throws -> Step {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ThreeError.invalid("A step needs a title.") }
        return try write { db in
            guard try FocusTask.exists(db, key: taskId) else { throw ThreeError.noSuchTask(taskId) }
            let last = try Int.fetchOne(db, sql: "SELECT MAX(position) FROM step WHERE taskId = ?", arguments: [taskId]) ?? -1
            let step = Step(id: UUID().uuidString, taskId: taskId, position: last + 1, title: title, done: false, updatedAt: Date())
            try step.insert(db)
            return step
        }
    }

    public func setStep(_ id: String, done: Bool? = nil, title: String? = nil) throws {
        try write { db in
            guard var step = try Step.fetchOne(db, key: id) else { throw ThreeError.invalid("No such step.") }
            if let done { step.done = done }
            if let title { step.title = title }
            step.updatedAt = Date()
            try step.update(db)
        }
    }

    public func removeStep(_ id: String) throws {
        try write { db in _ = try Step.deleteOne(db, key: id) }
    }

    // MARK: Categories

    @discardableResult
    public func addCategory(name: String, colorHex: String) throws -> Category {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ThreeError.invalid("A category needs a name.") }
        return try write { db in
            let last = try Int.fetchOne(db, sql: "SELECT MAX(position) FROM category") ?? -1
            let c = Category(id: UUID().uuidString, name: name, colorHex: colorHex, position: last + 1,
                             archived: false, updatedAt: Date(), deletedAt: nil)
            try uniqueName(name) { try c.insert(db) }
            return c
        }
    }

    public func updateCategory(_ id: String, name: String? = nil, colorHex: String? = nil, archived: Bool? = nil) throws {
        try write { db in
            guard var c = try Category.fetchOne(db, key: id) else { throw ThreeError.noSuchCategory(id) }
            if let name {
                let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw ThreeError.invalid("A category needs a name.") }
                c.name = name
            }
            if let colorHex { c.colorHex = colorHex }
            if let archived {
                if archived, try Category.filter(Column("archived") == false && Column("deletedAt") == nil).fetchCount(db) <= 1 {
                    throw ThreeError.invalid("Keep at least one category.")
                }
                c.archived = archived
            }
            c.updatedAt = Date()
            try uniqueName(c.name) { try c.update(db) }
        }
    }

    private func uniqueName(_ name: String, _ body: () throws -> Void) throws {
        do { try body() } catch let e as DatabaseError where e.resultCode == .SQLITE_CONSTRAINT {
            throw ThreeError.invalid("There's already a category called \(name).")
        }
    }
}

/// Todoist-style quick add: "Write the PRD #writing 45m tomorrow".
/// `#category` matches by prefix, a duration sets the block, and a day word picks the day ("inbox" or "someday" for none).
/// Durations and days are read from the end of the text only.
public struct QuickAdd: Equatable, Sendable {
    public enum When: Equatable, Sendable {
        case inbox
        case day(DayKey)
    }

    public var title: String
    public var category: String?
    public var minutes: Int?
    public var when: When?

    public static func parse(_ text: String, categories: [String], today: DayKey = .today) -> QuickAdd {
        var result = QuickAdd(title: "", category: nil, minutes: nil, when: nil)
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // A duration and a day only count at the end, so "Email Tom about invoice" keeps its words.
        while let last = words.last {
            let lower = last.lowercased()
            if result.category == nil, let match = category(lower, in: categories) {
                result.category = match
            } else if result.minutes == nil, Int(lower) == nil, last.first?.isNumber == true, let minutes = parseMinutes(lower) {
                // A bare number is part of the title ("Read 3 chapters"); a duration has a unit.
                result.minutes = minutes
            } else if result.when == nil, let when = day(lower, today: today) {
                result.when = when
            } else {
                break
            }
            words.removeLast()
        }
        // A #category is explicit enough to take from anywhere.
        if result.category == nil, let i = words.firstIndex(where: { category($0.lowercased(), in: categories) != nil }) {
            result.category = category(words[i].lowercased(), in: categories)
            words.remove(at: i)
        }
        result.title = words.joined(separator: " ")
        return result
    }

    private static func category(_ token: String, in categories: [String]) -> String? {
        guard token.hasPrefix("#"), token.count > 1 else { return nil }
        let key = token.dropFirst().replacingOccurrences(of: "-", with: "")
        return categories.first { $0.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(key) }
    }

    /// "45", "45m", "45min", "1h", "1h30m", "1.5h".
    public static func parseMinutes(_ s: String) -> Int? {
        let s = s.lowercased()
        if let n = Int(s) { return n }
        if s.hasSuffix("min"), let n = Int(s.dropLast(3)) { return n }
        if s.hasSuffix("m"), !s.contains("h"), let n = Int(s.dropLast()) { return n }
        if let h = s.firstIndex(of: "h") {
            guard let hours = Double(s[..<h]) else { return nil }
            let rest = s[s.index(after: h)...].replacingOccurrences(of: "m", with: "")
            guard rest.isEmpty || Int(rest) != nil else { return nil }
            return Int(hours * 60) + (Int(rest) ?? 0)
        }
        return nil
    }

    private static func day(_ word: String, today: DayKey) -> When? {
        switch word {
        case "today": return .day(today)
        case "tomorrow", "tmr": return .day(today.adding(days: 1))
        case "inbox", "someday": return .inbox
        default: break
        }
        // No "sun" or "sat": they're words too ("Watch the sun", "SAT prep").
        let names = ["sunday": 0, "mon": 1, "monday": 1, "tue": 2, "tues": 2, "tuesday": 2,
                     "wed": 3, "wednesday": 3, "thu": 4, "thurs": 4, "thursday": 4, "fri": 5, "friday": 5,
                     "saturday": 6]
        guard let target = names[word] else { return nil }
        let weekday = Calendar.current.component(.weekday, from: today.startDate) - 1
        let ahead = (target - weekday + 7) % 7
        return .day(today.adding(days: ahead == 0 ? 7 : ahead))
    }
}
