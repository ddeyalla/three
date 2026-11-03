import Foundation
import GRDB

public struct StatsRatio: Codable, Hashable, Sendable {
    public let numerator: Double
    public let denominator: Double
    public let value: Double?
    public let percent: Double?

    init(numerator: Double, denominator: Double) {
        self.numerator = numerator
        self.denominator = denominator
        value = denominator > 0 ? numerator / denominator : nil
        percent = value.map { $0 * 100 }
    }

    private enum CodingKeys: String, CodingKey { case numerator, denominator, value, percent }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(numerator, forKey: .numerator)
        try container.encode(denominator, forKey: .denominator)
        try container.encode(value, forKey: .value)
        try container.encode(percent, forKey: .percent)
    }
}

public struct StatsBlockTarget: Codable, Hashable, Identifiable, Sendable {
    public var ruleId: String
    public var kind: String?
    public var target: String?
    public var associatedHits: Int
    public var associatedUnblocks: Int
    public var unassociatedHits: Int
    public var unassociatedUnblocks: Int
    public var hitCount: Int { associatedHits + unassociatedHits }
    public var unblockCount: Int { associatedUnblocks + unassociatedUnblocks }
    public var id: String { ruleId }
}

public struct StatsBlocks: Codable, Hashable, Sendable {
    public var associatedHits: Int
    public var associatedUnblocks: Int
    public var unassociatedHits: Int
    public var unassociatedUnblocks: Int
    public var unresolvedSessionEventCount: Int
    public var focusHours: Double
    public var hitsPerFocusHour: StatsRatio
    public var unblocksPerFocusHour: StatsRatio
    public var topTargets: [StatsBlockTarget]
}

public struct StatsQuality: Codable, Hashable, Sendable {
    public var focusSessionCount: Int
    public var ratedSessionCount: Int
    public var focusedSessionCount: Int
    public var scatteredSessionCount: Int
    public var okaySessionCount: Int
    public var missingRatingCount: Int
    public var focusedShare: StatsRatio
}

public struct StatsBreaks: Codable, Hashable, Sendable {
    public var endedFocusSessionCount: Int
    public var pendingFocusSessionCount: Int
    public var recordedDecisionCount: Int
    public var takenCount: Int
    public var skippedCount: Int
    public var missingDecisionCount: Int
    public var skippedShare: StatsRatio
}

public struct StatsCategoryQuality: Codable, Hashable, Identifiable, Sendable {
    public var categoryId: String?
    public var category: Category?
    public var quality: StatsQuality
    public var id: String? { categoryId }
}

public struct StatsMetrics: Codable, Hashable, Sendable {
    public var focusSeconds: Double
    public var derivedPlannedSeconds: Int
    public var committedPlanCount: Int
    public var commitmentSnapshotPlanCount: Int
    public var legacyCommittedPlanCount: Int
    public var committedPlannedSeconds: Int
    public var accuracyFocusSeconds: Double
    public var completedTaskCount: Int
    public var committedPlannedTaskCount: Int
    public var quality: StatsQuality
    public var categoryQuality: [StatsCategoryQuality]
    public var blocks: StatsBlocks
    public var breaks: StatsBreaks
    public var focusMinutes: Double
    public var completion: StatsRatio
    public var actualToPlanned: StatsRatio
}

public struct StatsDay: Codable, Hashable, Identifiable, Sendable {
    public var day: DayKey
    public var isPartial: Bool
    public var commitmentCapturedAt: Date?
    public var closedAt: Date?
    public var metrics: StatsMetrics
    public var averageDayCount: Int
    /// Unavailable until seven civil dates are included. Includes recorded zero-focus days.
    public var sevenDayAverageMinutes: Double?
    public var qualifiesForStreak: Bool
    public var id: DayKey { day }
}

public struct StatsWeek: Codable, Hashable, Identifiable, Sendable {
    public var weekStarting: DayKey
    public var from: DayKey
    public var through: DayKey
    public var includedDayCount: Int
    public var isPartial: Bool
    public var metrics: StatsMetrics
    public var id: DayKey { weekStarting }
}

public struct StatsTag: Codable, Hashable, Identifiable, Sendable {
    public var tag: Tag
    public var metrics: StatsMetrics
    public var days: [StatsDay]
    public var weeks: [StatsWeek]
    public var id: String { tag.id }
}

public struct StatsStreak: Codable, Hashable, Sendable {
    public var days: Int
    public var endingOn: DayKey?
    public var lookedBackFrom: DayKey
    public var lookedBackThrough: DayKey
    public var isLowerBound: Bool
    public var currentIncompleteDayPreservesPrevious: Bool
}

public struct StatsMissingData: Codable, Hashable, Sendable {
    public var commitmentSnapshotsUnavailable: Bool
    public var historicalCoverageUnknown: Bool
    public var blockerCoverageUnknown: Bool
    public var missingRatingCount: Int
    public var missingTaskReferenceCount: Int
    public var missingCategoryReferenceCount: Int
    public var unresolvedBlockSessionEventCount: Int
    public var missingBreakDecisionCount: Int
    public var missingCompletionTimestampCount: Int
    public var committedTasksMissingCurrentReferences: Int
}

public struct StatsProvenance: Codable, Hashable, Sendable {
    public var actualTime = "HistoryReport via Session.elapsed; breaks and pauses excluded; sessions attributed to their local start date"
    public var plannedTime = "Prospective planCommitment stores original IDs and minutes; legacy current-row totals remain separately labelled derived"
    public var completion = "Done original commitment IDs / original commitment IDs on nondeleted committed plans; frozen close outcomes when available, otherwise current nondeleted task outcomes; legacy plans and drafts excluded"
    public var accuracy = "Focus on dates with prospective commitment snapshots / original committed planned seconds on those dates; includes unplanned focus on those dates, may exceed 100 percent; legacy plans and drafts excluded"
    public var quality = "Focused ratings / all recorded focus-session ratings; missing ratings excluded, no inferred scores"
    public var blockEvents = "Linked focus events follow the session start date and use those sessions' focus hours; unassociated events follow occurrence date and are excluded from rates and tags"
    public var coverage = "Only recorded deduplicated block hits and granted unblocks; no measurement of unconfigured rules, unsupported browsers, or unrecorded activity"
    public var tags = "Current task-tag membership; overlapping tags each receive full membership, global focus counted once"
    public var streak = "Committed plan plus a currently done, nondeleted task whose doneAt falls on that plan's civil date; reopening removes qualification; bounded to requested dates"
    public var weeks = "Monday through Sunday in Gregorian civil dates; range boundaries and the current week are partial"
    public var breaks = "Recorded taken or skipped decisions for ended focus sessions / recorded decisions; missing decisions remain unknown; running focus sessions reported separately"
}

public struct StatsReport: Codable, Hashable, Sendable {
    public var from: DayKey
    public var through: DayKey
    public var takenAt: Date
    public var timeZoneIdentifier: String
    public var isPartial: Bool
    public var provenance: StatsProvenance
    public var missingData: StatsMissingData
    public var metrics: StatsMetrics
    public var days: [StatsDay]
    public var weeks: [StatsWeek]
    public var tags: [StatsTag]
    public var streak: StatsStreak
}

extension Store {
    /// Defaults to 28 civil dates ending today. Reports never read more than 366 dates or write data.
    public func stats(from: DayKey? = nil, through: DayKey? = nil, now: Date = Date(),
                      calendar: Calendar = .current) throws -> StatsReport {
        let today = DayKey(now, calendar: calendar)
        let through = through ?? today
        let from = from ?? statsAdding(-27, to: through)
        let range = try HistoryRange(from: from, through: through, calendar: calendar)
        guard through <= today else { throw ThreeError.invalid("Statistics cannot include future dates.") }
        return try db.read { db in
            let history = try historyReport(from: from, through: through, now: now, range: range, db: db)
            let focus = history.days.flatMap(\.sessions).filter { $0.session.kind == .focus }
            let focusById = Dictionary(uniqueKeysWithValues: history.days.flatMap { day in
                day.sessions.filter { $0.session.kind == .focus }.map { ($0.id, (day: day.day, session: $0)) }
            })
            let focusIds = focus.map(\.id)
            let eventRows = try SQLRequest<Row>("""
                SELECT e.at, e.ruleId, e.sessionId, e.action, r.kind AS targetKind, r.value AS targetValue, s.kind AS sessionKind
                FROM blockEvent e LEFT JOIN blockRule r ON r.id = e.ruleId
                LEFT JOIN session s ON s.id = e.sessionId
                WHERE e.sessionId IN \(focusIds)
                   OR (e.at >= \(range.start) AND e.at < \(range.end) AND (s.id IS NULL OR s.kind <> 'focus'))
                ORDER BY e.at, e.id
                """).fetchAll(db)
            let events = eventRows.map { row -> StatsEvent in
                let sessionId: String? = row["sessionId"]
                let linked = sessionId.flatMap { focusById[$0] }
                let at: Date = row["at"]
                return StatsEvent(day: linked?.day ?? DayKey(at, calendar: range.calendar),
                                  ruleId: row["ruleId"], kind: row["targetKind"], target: row["targetValue"],
                                  isHit: (row["action"] as String) == "blocked", associated: linked != nil,
                                  unresolvedSession: sessionId != nil && (row["sessionKind"] as String?) == nil,
                                  tagIds: Set(linked?.session.tags.map(\.id) ?? []))
            }
            let commitmentRows = try SQLRequest<Row>("SELECT * FROM planCommitment WHERE planId IN \(history.days.compactMap(\.plan?.id))").fetchAll(db)
            let commitments = try Dictionary(uniqueKeysWithValues: commitmentRows.map { row in
                let tasks = try JSONDecoder().decode([CommittedTask].self, from: Data((row["tasksJSON"] as String).utf8))
                return (row["planId"] as String, PlanCommitment(capturedAt: row["capturedAt"], tasks: tasks))
            })
            let taskIds = Set(history.days.flatMap(\.tasks).map(\.id))
                .union(commitments.values.flatMap(\.tasks).map(\.taskId))
            let taskRows = try Dictionary(uniqueKeysWithValues: FocusTask.filter(taskIds.contains(Column("id"))).fetchAll(db).map { ($0.id, $0) })
            let tagsByTask = try self.tags(for: Array(taskIds), db)
            let doneRows = try SQLRequest<Row>("SELECT id, doneAt FROM task WHERE id IN \(taskIds) AND doneAt IS NOT NULL").fetchAll(db)
            let doneAt = Dictionary(uniqueKeysWithValues: doneRows.map { ($0["id"] as String, $0["doneAt"] as Date) })
            let closeRows = try SQLRequest<Row>("SELECT day, summaryJSON FROM dayClose WHERE day IN \(range.days)").fetchAll(db)
            let closes = try Dictionary(uniqueKeysWithValues: closeRows.map { row in
                let summary = try JSONDecoder().decode(DayCloseSummary.self, from: Data((row["summaryJSON"] as String).utf8))
                return (row["day"] as DayKey, summary)
            })
            let breaks = try RecordedBreakDecision.filter(focusIds.contains(Column("sessionId"))).fetchAll(db)
            let evidence = StatsEvidence(commitments: commitments, closes: closes,
                                         breakDecisions: Dictionary(uniqueKeysWithValues: breaks.map { ($0.sessionId, $0.decision) }),
                                         tasks: taskRows, tags: tagsByTask)
            let days = statsDays(history.days, events: events, evidence: evidence, tagId: nil, today: today, doneAt: doneAt, calendar: range.calendar)
            let metrics = statsMetrics(history.days, events: events, evidence: evidence, tagId: nil)
            let tags = Dictionary(grouping: tagsByTask.values.flatMap { $0 }, by: \.id)
                .values.compactMap(\.first).sorted { ($0.name, $0.id) < ($1.name, $1.id) }
                .map { tag in
                    StatsTag(tag: tag, metrics: statsMetrics(history.days, events: events, evidence: evidence, tagId: tag.id),
                             days: statsDays(history.days, events: events, evidence: evidence, tagId: tag.id, today: today, doneAt: doneAt, calendar: range.calendar),
                             weeks: statsWeeks(history.days, events: events, evidence: evidence, tagId: tag.id, today: today))
                }
            return StatsReport(from: from, through: through, takenAt: now, timeZoneIdentifier: history.timeZoneIdentifier,
                               isPartial: through == today, provenance: StatsProvenance(),
                               missingData: StatsMissingData(commitmentSnapshotsUnavailable: metrics.legacyCommittedPlanCount > 0, historicalCoverageUnknown: true,
                                                            blockerCoverageUnknown: true, missingRatingCount: metrics.quality.missingRatingCount,
                                                            missingTaskReferenceCount: focus.filter { $0.task == nil }.count,
                                                            missingCategoryReferenceCount: focus.filter { $0.category == nil }.count,
                                                            unresolvedBlockSessionEventCount: metrics.blocks.unresolvedSessionEventCount,
                                                            missingBreakDecisionCount: metrics.breaks.missingDecisionCount,
                                                            missingCompletionTimestampCount: taskRows.values.filter { $0.status == .done && doneAt[$0.id] == nil }.count,
                                                            committedTasksMissingCurrentReferences: commitments.values.flatMap(\.tasks).filter { taskRows[$0.taskId] == nil }.count),
                               metrics: metrics, days: days,
                               weeks: statsWeeks(history.days, events: events, evidence: evidence, tagId: nil, today: today), tags: tags,
                               streak: statsStreak(days, today: today))
        }
    }
}

private struct StatsEvent {
    var day: DayKey
    var ruleId: String
    var kind: String?
    var target: String?
    var isHit: Bool
    var associated: Bool
    var unresolvedSession: Bool
    var tagIds: Set<String>
}

private struct StatsEvidence {
    var commitments: [String: PlanCommitment]
    var closes: [DayKey: DayCloseSummary]
    var breakDecisions: [String: BreakDecision]
    var tasks: [String: FocusTask]
    var tags: [String: [Tag]]

    func includes(taskId: String, tagId: String?) -> Bool {
        guard let tagId else { return true }
        return tags[taskId]?.contains { $0.id == tagId } == true
    }
}

private func statsQuality(_ sessions: [HistorySession]) -> StatsQuality {
    let ratings = sessions.compactMap(\.session.focusRating)
    return StatsQuality(focusSessionCount: sessions.count, ratedSessionCount: ratings.count,
                        focusedSessionCount: ratings.filter { $0 == .focused }.count,
                        scatteredSessionCount: ratings.filter { $0 == .scattered }.count,
                        okaySessionCount: ratings.filter { $0 == .okay }.count,
                        missingRatingCount: sessions.count - ratings.count,
                        focusedShare: StatsRatio(numerator: Double(ratings.filter { $0 == .focused }.count), denominator: Double(ratings.count)))
}

private func statsMetrics(_ days: [HistoryDay], events: [StatsEvent], evidence: StatsEvidence, tagId: String?) -> StatsMetrics {
    let sessions = days.flatMap(\.sessions).filter {
        $0.session.kind == .focus && (tagId == nil || $0.tags.contains { $0.id == tagId })
    }
    let tasks = days.flatMap(\.tasks).filter { $0.derivedPlannedSeconds > 0 && (tagId == nil || $0.tags.contains { $0.id == tagId }) }
    let committed = days.filter { $0.plan?.committedAt != nil && $0.plan?.status != .draft && $0.plan?.deletedAt == nil }
    let known = committed.compactMap { day -> (HistoryDay, PlanCommitment)? in
        guard let id = day.plan?.id, let commitment = evidence.commitments[id] else { return nil }
        return (day, commitment)
    }
    let committedTasks = known.flatMap { $0.1.tasks }.filter { evidence.includes(taskId: $0.taskId, tagId: tagId) }
    let completedCount = known.reduce(0) { total, entry in
        let (day, commitment) = entry
        let doneIds: Set<String>
        if let summary = evidence.closes[day.day] {
            doneIds = Set(summary.tasks.filter { $0.status == .done }.map(\.id))
        } else {
            doneIds = Set(commitment.tasks.compactMap { evidence.tasks[$0.taskId] }
                .filter { $0.status == .done && $0.deletedAt == nil }.map(\.id))
        }
        return total + commitment.tasks.filter { doneIds.contains($0.taskId) && evidence.includes(taskId: $0.taskId, tagId: tagId) }.count
    }
    let knownDays = Set(known.map { $0.0.day })
    let accuracyFocus = days.filter { knownDays.contains($0.day) }.flatMap(\.sessions).filter {
        $0.session.kind == .focus && (tagId == nil || $0.tags.contains { $0.id == tagId })
    }.reduce(0) { $0 + $1.actualSeconds }
    let plannedSeconds = committedTasks.reduce(0) { $0 + $1.plannedMinutes * 60 }
    let focusSeconds = sessions.reduce(0) { $0 + $1.actualSeconds }
    let dayIds = Set(days.map(\.day))
    let includedEvents = events.filter { dayIds.contains($0.day) && (tagId == nil || $0.tagIds.contains(tagId!)) }
    let targets = Dictionary(grouping: includedEvents, by: \.ruleId).map { id, events in
        StatsBlockTarget(ruleId: id, kind: events.first?.kind, target: events.first?.target,
                         associatedHits: events.filter { $0.associated && $0.isHit }.count,
                         associatedUnblocks: events.filter { $0.associated && !$0.isHit }.count,
                         unassociatedHits: events.filter { !$0.associated && $0.isHit }.count,
                         unassociatedUnblocks: events.filter { !$0.associated && !$0.isHit }.count)
    }.sorted {
        if $0.hitCount != $1.hitCount { return $0.hitCount > $1.hitCount }
        if $0.unblockCount != $1.unblockCount { return $0.unblockCount > $1.unblockCount }
        return $0.ruleId < $1.ruleId
    }
    let categories = Dictionary(grouping: sessions, by: { $0.task?.categoryId }).map { id, rows in
        StatsCategoryQuality(categoryId: id, category: rows.first?.category, quality: statsQuality(rows))
    }.sorted { ($0.category?.position ?? Int.max, $0.categoryId ?? "") < ($1.category?.position ?? Int.max, $1.categoryId ?? "") }
    let ended = sessions.filter { $0.session.endedAt != nil }
    let decisions = ended.compactMap { evidence.breakDecisions[$0.id] }
    let skipped = decisions.filter { $0 == .skipped }.count
    return StatsMetrics(focusSeconds: focusSeconds, derivedPlannedSeconds: tasks.reduce(0) { $0 + $1.derivedPlannedSeconds },
                        committedPlanCount: committed.filter { day in tagId == nil || day.tasks.contains { $0.tags.contains { $0.id == tagId } } }.count,
                        commitmentSnapshotPlanCount: known.filter { entry in tagId == nil || entry.1.tasks.contains { evidence.includes(taskId: $0.taskId, tagId: tagId) } }.count,
                        legacyCommittedPlanCount: committed.filter { day in evidence.commitments[day.plan!.id] == nil && (tagId == nil || day.tasks.contains { $0.tags.contains { $0.id == tagId } }) }.count,
                        committedPlannedSeconds: plannedSeconds, accuracyFocusSeconds: accuracyFocus,
                        completedTaskCount: completedCount,
                        committedPlannedTaskCount: committedTasks.count, quality: statsQuality(sessions), categoryQuality: categories,
                        blocks: StatsBlocks(associatedHits: targets.reduce(0) { $0 + $1.associatedHits },
                                            associatedUnblocks: targets.reduce(0) { $0 + $1.associatedUnblocks },
                                            unassociatedHits: targets.reduce(0) { $0 + $1.unassociatedHits },
                                            unassociatedUnblocks: targets.reduce(0) { $0 + $1.unassociatedUnblocks },
                                            unresolvedSessionEventCount: includedEvents.filter(\.unresolvedSession).count,
                                            focusHours: focusSeconds / 3600,
                                            hitsPerFocusHour: StatsRatio(numerator: Double(targets.reduce(0) { $0 + $1.associatedHits }), denominator: focusSeconds / 3600),
                                            unblocksPerFocusHour: StatsRatio(numerator: Double(targets.reduce(0) { $0 + $1.associatedUnblocks }), denominator: focusSeconds / 3600),
                                            topTargets: Array(targets.prefix(3))),
                        breaks: StatsBreaks(endedFocusSessionCount: ended.count, pendingFocusSessionCount: sessions.count - ended.count,
                                            recordedDecisionCount: decisions.count, takenCount: decisions.count - skipped, skippedCount: skipped,
                                            missingDecisionCount: ended.count - decisions.count,
                                            skippedShare: StatsRatio(numerator: Double(skipped), denominator: Double(decisions.count))),
                        focusMinutes: focusSeconds / 60,
                        completion: StatsRatio(numerator: Double(completedCount), denominator: Double(committedTasks.count)),
                        actualToPlanned: StatsRatio(numerator: accuracyFocus, denominator: Double(plannedSeconds)))
}

private func statsDays(_ days: [HistoryDay], events: [StatsEvent], evidence: StatsEvidence, tagId: String?, today: DayKey,
                       doneAt: [String: Date], calendar: Calendar) -> [StatsDay] {
    let metrics = days.map { statsMetrics([$0], events: events, evidence: evidence, tagId: tagId) }
    return days.enumerated().map { index, day in
        let window = metrics[max(0, index - 6)...index]
        let finished = day.tasks.contains { row in
            row.task.dayPlanId == day.plan?.id && row.task.deletedAt == nil && row.task.status == .done
                && (tagId == nil || row.tags.contains { $0.id == tagId })
                && doneAt[row.id].map { DayKey($0, calendar: calendar) == day.day } == true
        }
        return StatsDay(day: day.day, isPartial: day.day == today,
                        commitmentCapturedAt: day.plan.flatMap { evidence.commitments[$0.id]?.capturedAt },
                        closedAt: evidence.closes[day.day]?.closedAt,
                        metrics: metrics[index], averageDayCount: window.count,
                        sevenDayAverageMinutes: window.count == 7 ? window.reduce(0) { $0 + $1.focusMinutes } / 7 : nil,
                        qualifiesForStreak: day.plan?.committedAt != nil && day.plan?.status != .draft && day.plan?.deletedAt == nil && finished)
    }
}

private func statsWeeks(_ days: [HistoryDay], events: [StatsEvent], evidence: StatsEvidence, tagId: String?, today: DayKey) -> [StatsWeek] {
    let grouped = Dictionary(grouping: days, by: { statsWeekStart($0.day) })
    return grouped.keys.sorted().map { first in
        let days = grouped[first]!
        return StatsWeek(weekStarting: first, from: days.first!.day, through: days.last!.day, includedDayCount: days.count,
                         isPartial: days.count != 7 || days.last!.day == today,
                         metrics: statsMetrics(days, events: events, evidence: evidence, tagId: tagId))
    }
}

private func statsStreak(_ days: [StatsDay], today: DayKey) -> StatsStreak {
    var scan = days
    let preserve = scan.last?.day == today && scan.last?.qualifiesForStreak == false
    if preserve { scan.removeLast() }
    let ending = scan.last?.qualifiesForStreak == true ? scan.last?.day : nil
    var count = 0
    for day in scan.reversed() {
        guard day.qualifiesForStreak else { break }
        count += 1
    }
    return StatsStreak(days: count, endingOn: ending, lookedBackFrom: days.first!.day, lookedBackThrough: days.last!.day,
                       isLowerBound: count == scan.count, currentIncompleteDayPreservesPrevious: preserve)
}

private var statsCivilCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func statsCivilDate(_ day: DayKey) -> Date {
    let components = day.rawValue.split(separator: "-").map { Int($0)! }
    return statsCivilCalendar.date(from: DateComponents(year: components[0], month: components[1], day: components[2]))!
}

private func statsAdding(_ count: Int, to day: DayKey) -> DayKey {
    DayKey(statsCivilCalendar.date(byAdding: .day, value: count, to: statsCivilDate(day))!, calendar: statsCivilCalendar)
}

private func statsWeekStart(_ day: DayKey) -> DayKey {
    let weekday = statsCivilCalendar.component(.weekday, from: statsCivilDate(day))
    return statsAdding(-((weekday + 5) % 7), to: day)
}
