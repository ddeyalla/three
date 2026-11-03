import Foundation
import GRDB

public struct HistoryTotals: Codable, Hashable, Sendable {
    public var plannedSeconds: Int = 0
    public var focusSeconds: TimeInterval = 0
    public var breakSeconds: TimeInterval = 0
    public var plannedTaskCount: Int = 0
    public var doneTaskCount: Int = 0
    public var focusSessionCount: Int = 0
    public var breakSessionCount: Int = 0

    fileprivate mutating func add(_ other: Self) {
        plannedSeconds += other.plannedSeconds
        focusSeconds += other.focusSeconds
        breakSeconds += other.breakSeconds
        plannedTaskCount += other.plannedTaskCount
        doneTaskCount += other.doneTaskCount
        focusSessionCount += other.focusSessionCount
        breakSessionCount += other.breakSessionCount
    }
}

public struct HistoryCategory: Codable, Hashable, Identifiable, Sendable {
    public var categoryId: String?
    public var category: Category?
    public var plannedSeconds: Int
    public var focusSeconds: TimeInterval
    public var id: String? { categoryId }
}

public struct HistorySession: Codable, Hashable, Identifiable, Sendable {
    public var session: Session
    public var actualSeconds: TimeInterval
    public var task: FocusTask?
    public var category: Category?
    public var tags: [Tag]
    public var id: String { session.id }
}

public struct HistoryTask: Codable, Hashable, Identifiable, Sendable {
    public var task: FocusTask
    public var category: Category?
    public var plannedDay: DayKey?
    public var steps: [Step]
    public var tags: [Tag]
    /// Only focus sessions starting on this report day, including a block that ends the next day.
    public var focusSeconds: TimeInterval
    public var sessionIds: [String]
    /// Zero for references from another day, deleted tasks, dropped tasks, and carried sources.
    public var derivedPlannedSeconds: Int
    public var id: String { task.id }
}

public struct HistoryDay: Codable, Hashable, Identifiable, Sendable {
    public var day: DayKey
    public var plan: DayPlan?
    public var totals: HistoryTotals
    public var categories: [HistoryCategory]
    public var tasks: [HistoryTask]
    public var sessions: [HistorySession]
    public var id: DayKey { day }
}

public struct HistoryMonth: Codable, Hashable, Identifiable, Sendable {
    /// Gregorian yyyy-MM. The bounds describe the included portion of the month.
    public var month: String
    public var from: DayKey
    public var through: DayKey
    public var dayCount: Int
    public var totals: HistoryTotals
    public var categories: [HistoryCategory]
    public var id: String { month }
}

public struct HistoryReport: Codable, Hashable, Sendable {
    public enum PlannedMetrics: String, Codable, Sendable {
        case derivedFromCurrentTaskRows
    }

    public enum DateAttribution: String, Codable, Sendable {
        case sessionStartDayInReportTimeZone
    }

    public var from: DayKey
    public var through: DayKey
    public var takenAt: Date
    public var timeZoneIdentifier: String
    public var plannedMetrics: PlannedMetrics = .derivedFromCurrentTaskRows
    public var dateAttribution: DateAttribution = .sessionStartDayInReportTimeZone
    public var totals: HistoryTotals
    public var months: [HistoryMonth]
    public var days: [HistoryDay]
}

struct HistoryRange {
    let calendar: Calendar
    let days: [DayKey]
    let start: Date
    let end: Date

    init(from: DayKey, through: DayKey, calendar: Calendar = .current) throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        var civil = Calendar(identifier: .gregorian)
        civil.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = civil
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = civil.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        func localStart(_ date: Date) -> Date? {
            var components = civil.dateComponents([.year, .month, .day], from: date)
            components.hour = 12
            return local.date(from: components).map { local.startOfDay(for: $0) }
        }
        guard from <= through,
              let first = formatter.date(from: from.rawValue),
              let last = formatter.date(from: through.rawValue),
              let distance = civil.dateComponents([.day], from: first, to: last).day,
              (0..<366).contains(distance),
              let next = civil.date(byAdding: .day, value: 1, to: last),
              let start = localStart(first), let end = localStart(next) else {
            throw ThreeError.invalid("History needs an ordered range of at most 366 days.")
        }
        self.calendar = local
        self.start = start
        self.end = end
        days = (0...distance).map { DayKey(civil.date(byAdding: .day, value: $0, to: first)!, calendar: civil) }
    }
}

extension Store {
    /// One consistent read. Elapsed time belongs to Session; no historical pause intervals are inferred.
    public func historyReport(from: DayKey, through: DayKey, now: Date = Date(),
                              calendar: Calendar = .current) throws -> HistoryReport {
        let range = try HistoryRange(from: from, through: through, calendar: calendar)
        return try db.read { db in
            let sessions = try Session.filter(Column("startedAt") >= range.start && Column("startedAt") < range.end)
                .order(Column("startedAt"), Column("id")).fetchAll(db)
            let plans = try DayPlan.filter(Column("day") >= from && Column("day") <= through)
                .order(Column("day"), Column("id")).fetchAll(db)
            let planIds = plans.map(\.id)
            let sessionTaskIds = Set(sessions.compactMap(\.taskId))
            let tasks = try FocusTask.filter(planIds.contains(Column("dayPlanId")) || sessionTaskIds.contains(Column("id")))
                .order(Column("position"), Column("id")).fetchAll(db)
            let taskIds = tasks.map(\.id)
            let referencedPlans = try DayPlan.filter(Set(tasks.compactMap(\.dayPlanId)).contains(Column("id"))).fetchAll(db)
            let planById = Dictionary(uniqueKeysWithValues: referencedPlans.map { ($0.id, $0) })
            let planByDay = Dictionary(uniqueKeysWithValues: plans.map { ($0.day, $0) })
            let taskById = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            let categories = try Category.filter(Set(tasks.map(\.categoryId)).contains(Column("id"))).fetchAll(db)
            let categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            let tags = try self.tags(for: taskIds, db)
            let steps = try self.steps(for: taskIds, db)
            let tasksByPlan = Dictionary(grouping: tasks, by: \.dayPlanId)
            let sessionsByDay = Dictionary(grouping: sessions, by: { DayKey($0.startedAt, calendar: range.calendar) })

            let days = range.days.map { day in
                let plan = planByDay[day]
                let recorded = (sessionsByDay[day] ?? []).map { session in
                    let task = session.taskId.flatMap { taskById[$0] }
                    return HistorySession(session: session, actualSeconds: session.elapsed(at: now), task: task,
                                          category: task.flatMap { categoryById[$0.categoryId] },
                                          tags: task.flatMap { tags[$0.id] } ?? [])
                }
                let byTask = Dictionary(grouping: recorded, by: { $0.session.taskId })
                let planned = plan.map { tasksByPlan[$0.id] ?? [] } ?? []
                let plannedIds = Set(planned.map(\.id))
                let references = byTask.keys.compactMap { id -> FocusTask? in
                    guard let id, !plannedIds.contains(id) else { return nil }
                    return taskById[id]
                }.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
                let detail = (planned + references).map { task in
                    let mine = byTask[task.id] ?? []
                    let eligible = plan != nil && task.dayPlanId == plan?.id && plan?.deletedAt == nil && task.deletedAt == nil
                        && task.status != .dropped && task.status != .carried
                    return HistoryTask(task: task, category: categoryById[task.categoryId],
                                       plannedDay: task.dayPlanId.flatMap { planById[$0]?.day },
                                       steps: steps[task.id] ?? [], tags: tags[task.id] ?? [],
                                       focusSeconds: mine.filter { $0.session.kind == .focus }.reduce(0) { $0 + $1.actualSeconds },
                                       sessionIds: mine.map(\.id), derivedPlannedSeconds: eligible ? task.blockMinutes * 60 : 0)
                }
                var totals = HistoryTotals()
                for task in detail where task.derivedPlannedSeconds > 0 {
                    totals.plannedSeconds += task.derivedPlannedSeconds
                    totals.plannedTaskCount += 1
                    if task.task.status == .done { totals.doneTaskCount += 1 }
                }
                for row in recorded {
                    if row.session.kind == .focus {
                        totals.focusSeconds += row.actualSeconds
                        totals.focusSessionCount += 1
                    } else {
                        totals.breakSeconds += row.actualSeconds
                        totals.breakSessionCount += 1
                    }
                }
                var strips: [String?: HistoryCategory] = [:]
                for task in detail where task.derivedPlannedSeconds > 0 {
                    let id: String? = task.task.categoryId
                    var strip = strips[id] ?? HistoryCategory(categoryId: id, category: task.category, plannedSeconds: 0, focusSeconds: 0)
                    strip.plannedSeconds += task.derivedPlannedSeconds
                    strips[id] = strip
                }
                for row in recorded where row.session.kind == .focus {
                    let id = row.task?.categoryId
                    var strip = strips[id] ?? HistoryCategory(categoryId: id, category: row.category, plannedSeconds: 0, focusSeconds: 0)
                    strip.focusSeconds += row.actualSeconds
                    strips[id] = strip
                }
                return HistoryDay(day: day, plan: plan, totals: totals, categories: sortedHistoryCategories(strips.values),
                                  tasks: detail, sessions: recorded)
            }
            let grouped = Dictionary(grouping: days, by: { String($0.day.rawValue.prefix(7)) })
            let months = grouped.keys.sorted().map { month in
                let included = grouped[month]!
                return HistoryMonth(month: month, from: included.first!.day, through: included.last!.day,
                                    dayCount: included.count, totals: historyTotals(included),
                                    categories: historyCategories(included))
            }
            return HistoryReport(from: from, through: through, takenAt: now, timeZoneIdentifier: range.calendar.timeZone.identifier,
                                 totals: historyTotals(days), months: months, days: days)
        }
    }
}

private func historyTotals(_ days: [HistoryDay]) -> HistoryTotals {
    days.reduce(into: HistoryTotals()) { $0.add($1.totals) }
}

private func historyCategories(_ days: [HistoryDay]) -> [HistoryCategory] {
    var result: [String?: HistoryCategory] = [:]
    for day in days {
        for category in day.categories {
            var total = result[category.categoryId] ?? HistoryCategory(categoryId: category.categoryId, category: category.category,
                                                                      plannedSeconds: 0, focusSeconds: 0)
            total.plannedSeconds += category.plannedSeconds
            total.focusSeconds += category.focusSeconds
            result[category.categoryId] = total
        }
    }
    return sortedHistoryCategories(result.values)
}

private func sortedHistoryCategories(_ categories: some Sequence<HistoryCategory>) -> [HistoryCategory] {
    categories.sorted {
        let a = ($0.category?.position ?? Int.max, $0.categoryId ?? "")
        let b = ($1.category?.position ?? Int.max, $1.categoryId ?? "")
        return a < b
    }
}
