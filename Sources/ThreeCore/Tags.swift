import Foundation
import GRDB

/// A thread of work that spans days or weeks: a product, a project, a feature.
/// A task can carry several. A tag's time is every focus block on every task that carries it,
/// including the copies a task leaves behind when it moves to another day.
public struct Tag: Codable, Hashable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "tag"
    public var id: String
    public var name: String
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date
}

/// One tag's total, with its tasks folded by title so a task carried over three days counts as one line.
public struct TagSummary: Hashable, Identifiable, Sendable {
    public struct Work: Hashable, Identifiable, Sendable {
        public var title: String
        public var seconds: TimeInterval
        public var lastWorked: Date?
        public var done: Bool
        public var id: String { title }
    }

    public var tag: Tag
    public var seconds: TimeInterval
    /// Focus in the last seven days, to show what's moving now.
    public var recentSeconds: TimeInterval
    public var daysWorked: Int
    public var lastWorked: Date?
    public var work: [Work]
    public var id: String { tag.id }
}

/// Done tasks for one day, newest day first in `Store.logbook`.
public struct LoggedDay: Hashable, Sendable {
    public var day: DayKey
    public var tasks: [TaskRow]
}

extension Store {
    // MARK: Reads

    func tags(for taskIds: [String], _ db: Database) throws -> [String: [Tag]] {
        guard !taskIds.isEmpty else { return [:] }
        let rows = try Row.fetchAll(db, sql: """
            SELECT taskTag.taskId, tag.* FROM taskTag JOIN tag ON tag.id = taskTag.tagId
            WHERE taskTag.taskId IN (\(databaseQuestionMarks(count: taskIds.count))) ORDER BY tag.name COLLATE NOCASE
            """, arguments: StatementArguments(taskIds))
        return try Dictionary(grouping: rows, by: { $0["taskId"] as String }).mapValues { try $0.map { try Tag(row: $0) } }
    }

    public func tags(includeArchived: Bool = false) throws -> [Tag] {
        try db.read { db in
            try (includeArchived ? Tag.all() : Tag.filter(Column("archived") == false)).order(Column("name").collating(.nocase)).fetchAll(db)
        }
    }

    /// Every tag with its time, most recently worked first; tags never worked on come last, by name.
    public func tagSummaries(includeArchived: Bool = false, now: Date = Date()) throws -> [TagSummary] {
        try db.read { db in
            let tags = try (includeArchived ? Tag.all() : Tag.filter(Column("archived") == false)).fetchAll(db)
            let links = try Row.fetchAll(db, sql: """
                SELECT taskTag.tagId, task.id, task.title, task.status FROM taskTag
                JOIN task ON task.id = taskTag.taskId WHERE task.deletedAt IS NULL
                """)
            let taskIds = Array(Set(links.map { $0["id"] as String }))
            var sessions: [String: [Session]] = [:]
            if !taskIds.isEmpty {
                for s in try Session.filter(taskIds.contains(Column("taskId")) && Column("kind") == SessionKind.focus).fetchAll(db) {
                    sessions[s.taskId!, default: []].append(s)
                }
            }
            let weekAgo = now.addingTimeInterval(-7 * 86_400)
            let byTag = Dictionary(grouping: links, by: { $0["tagId"] as String })
            return tags.map { tag in
                let rows = byTag[tag.id] ?? []
                let all = rows.flatMap { sessions[$0["id"] as String] ?? [] }
                var work: [String: TagSummary.Work] = [:]
                for row in rows {
                    let title: String = row["title"]
                    let mine = sessions[row["id"] as String] ?? []
                    var w = work[title] ?? .init(title: title, seconds: 0, lastWorked: nil, done: false)
                    w.seconds += mine.reduce(0) { $0 + $1.elapsed(at: now) }
                    w.lastWorked = ([w.lastWorked] + mine.map { $0.endedAt ?? now }).compactMap { $0 }.max()
                    w.done = w.done || (row["status"] as String) == TaskStatus.done.rawValue
                    work[title] = w
                }
                return TagSummary(
                    tag: tag,
                    seconds: all.reduce(0) { $0 + $1.elapsed(at: now) },
                    recentSeconds: all.filter { $0.startedAt >= weekAgo }.reduce(0) { $0 + $1.elapsed(at: now) },
                    daysWorked: Set(all.map { DayKey($0.startedAt) }).count,
                    lastWorked: all.map { $0.endedAt ?? now }.max(),
                    work: work.values.sorted { ($0.lastWorked ?? .distantPast, $1.title) > ($1.lastWorked ?? .distantPast, $0.title) }
                )
            }
            .sorted { a, b in
                switch (a.lastWorked, b.lastWorked) {
                case let (x?, y?): x > y
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): a.tag.name.localizedCaseInsensitiveCompare(b.tag.name) == .orderedAscending
                }
            }
        }
    }

    /// Tasks marked done in the last `days` days, grouped by the day they were finished, newest first.
    public func logbook(days: Int = 30, today: DayKey = .today) throws -> [LoggedDay] {
        try db.read { db in
            let since = today.adding(days: -(days - 1)).startDate
            let found = try Row.fetchAll(db, sql: """
                SELECT * FROM task WHERE status = 'done' AND deletedAt IS NULL AND doneAt >= ? ORDER BY doneAt DESC
                """, arguments: [since])
            let doneAt = Dictionary(uniqueKeysWithValues: found.map { ($0["id"] as String, $0["doneAt"] as Date) })
            let rows = try rows(for: try found.map { try FocusTask(row: $0) }, db)
            return Dictionary(grouping: rows, by: { DayKey(doneAt[$0.id]!) })
                .map { LoggedDay(day: $0.key, tasks: $0.value) }
                .sorted { $0.day > $1.day }
        }
    }

    /// Category, focus time, steps and tags for `tasks`, in their order. Tasks whose category is gone are left out.
    func rows(for tasks: [FocusTask], _ db: Database, now: Date = Date()) throws -> [TaskRow] {
        let categories = Dictionary(uniqueKeysWithValues: try Category.fetchAll(db).map { ($0.id, $0) })
        let ids = tasks.map(\.id)
        var focused: [String: TimeInterval] = [:]
        if !ids.isEmpty {
            for s in try Session.filter(ids.contains(Column("taskId")) && Column("kind") == SessionKind.focus).fetchAll(db) {
                focused[s.taskId!, default: 0] += s.elapsed(at: now)
            }
        }
        let steps = try self.steps(for: ids, db)
        let tags = try self.tags(for: ids, db)
        return tasks.compactMap { t in
            categories[t.categoryId].map {
                TaskRow(task: t, category: $0, focusedSeconds: focused[t.id] ?? 0, steps: steps[t.id] ?? [], tags: tags[t.id] ?? [])
            }
        }
    }

    // MARK: Writes

    /// The tag called `name`, ignoring case and a leading "@"; created when it doesn't exist, unarchived when it was archived.
    func tag(named name: String, _ db: Database) throws -> Tag {
        let name = Tag.clean(name)
        guard !name.isEmpty else { throw ThreeError.invalid("A tag needs a name.") }
        if var existing = try Tag.filter(sql: "name = ? COLLATE NOCASE", arguments: [name]).fetchOne(db) {
            if existing.archived {
                existing.archived = false
                existing.updatedAt = Date()
                try existing.update(db)
            }
            return existing
        }
        let tag = Tag(id: UUID().uuidString, name: name, archived: false, createdAt: Date(), updatedAt: Date())
        try tag.insert(db)
        return tag
    }

    func link(_ taskId: String, to names: [String], _ db: Database) throws {
        for name in names {
            let tag = try tag(named: name, db)
            try db.execute(sql: "INSERT OR IGNORE INTO taskTag(taskId, tagId) VALUES(?, ?)", arguments: [taskId, tag.id])
        }
    }

    /// Replaces a task's tags with `names`, creating any that don't exist yet.
    public func setTags(_ taskId: String, _ names: [String]) throws {
        try write { db in
            guard try FocusTask.exists(db, key: taskId) else { throw ThreeError.noSuchTask(taskId) }
            try db.execute(sql: "DELETE FROM taskTag WHERE taskId = ?", arguments: [taskId])
            try link(taskId, to: names, db)
        }
    }

    public func addTag(_ name: String, to taskId: String) throws {
        try write { db in
            _ = try editableTask(taskId, db)
            try link(taskId, to: [name], db)
        }
    }

    public func removeTag(_ tagId: String, from taskId: String) throws {
        try write { db in
            _ = try editableTask(taskId, db)
            try db.execute(sql: "DELETE FROM taskTag WHERE taskId = ? AND tagId = ?", arguments: [taskId, tagId])
        }
    }

    public func updateTag(_ id: String, name: String? = nil, archived: Bool? = nil) throws {
        try write { db in
            guard var tag = try Tag.fetchOne(db, key: id) else { throw ThreeError.invalid("No such tag.") }
            if let name {
                tag.name = Tag.clean(name)
                guard !tag.name.isEmpty else { throw ThreeError.invalid("A tag needs a name.") }
            }
            if let archived { tag.archived = archived }
            tag.updatedAt = Date()
            do { try tag.update(db) } catch let e as DatabaseError where e.resultCode == .SQLITE_CONSTRAINT {
                throw ThreeError.invalid("There's already a tag called \(tag.name).")
            }
        }
    }
}

extension Tag {
    /// "@Onboarding " → "Onboarding". Spaces become hyphens so the name can be typed back as one token.
    static func clean(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("@") { s.removeFirst() }
        return s.split(separator: " ").joined(separator: "-")
    }
}
