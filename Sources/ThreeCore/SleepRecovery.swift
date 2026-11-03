import Foundation
import GRDB

public enum RecoverySource: String, Sendable { case sleep, lock }

public enum RecoveryEvent: Sendable {
    case began(RecoverySource)
    case ended(RecoverySource)
    case relaunched
    case clockChanged
}

public struct RecoveryInstant: Sendable {
    public let date: Date
    public let continuousSeconds: TimeInterval?
    public let clockID: String?

    public init(date: Date, continuousSeconds: TimeInterval? = nil, clockID: String? = nil) {
        self.date = date
        self.continuousSeconds = continuousSeconds
        self.clockID = clockID
    }
}

public enum RecoveryState: String, Codable, DatabaseValueConvertible, Sendable {
    case observing, review, notRequired, kept, trimmed
}

public enum RecoveryDecision: Sendable { case keep, trim }

public struct RecoveryGap: Codable, Equatable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "recoveryGap"
    public let id: String
    public let startedAt: Date
    public private(set) var endedAt: Date?
    var lastObservedAt: Date
    let continuousSeconds: TimeInterval?
    let clockID: String?
    public fileprivate(set) var clockReliable: Bool
    var sleeping: Bool
    var locked: Bool
    public private(set) var awaySeconds: TimeInterval
    public fileprivate(set) var state: RecoveryState
    public fileprivate(set) var decidedAt: Date?

    mutating func set(_ source: RecoverySource, active: Bool) {
        switch source {
        case .sleep: sleeping = active
        case .lock: locked = active
        }
    }

    func contains(_ source: RecoverySource) -> Bool {
        switch source {
        case .sleep: sleeping
        case .lock: locked
        }
    }

    mutating func observe(_ instant: RecoveryInstant) {
        let wall = instant.date.timeIntervalSince(startedAt)
        if instant.date < lastObservedAt { clockReliable = false }
        if let continuousSeconds, let current = instant.continuousSeconds, clockID == instant.clockID {
            let elapsed = current - continuousSeconds
            if elapsed < 0 || abs(elapsed - wall) > 2 { clockReliable = false }
        } else if continuousSeconds != nil || instant.continuousSeconds != nil {
            clockReliable = false
        }
        lastObservedAt = max(lastObservedAt, instant.date)
    }

    mutating func finish(_ instant: RecoveryInstant) {
        observe(instant)
        endedAt = max(startedAt, instant.date)
        if let continuousSeconds, let current = instant.continuousSeconds, clockID == instant.clockID {
            awaySeconds = max(0, current - continuousSeconds)
        } else {
            awaySeconds = max(0, instant.date.timeIntervalSince(startedAt))
        }
        sleeping = false
        locked = false
        state = awaySeconds > 600 || !clockReliable ? .review : .notRequired
    }
}

private struct RecoveryImpact: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recoveryImpact"
    let gapId: String
    let sessionId: String
    let baselineWork: TimeInterval
    var eligibleSeconds: TimeInterval = 0
}

public struct RecoverySessionReview: Codable, Identifiable, Sendable {
    public let session: Session
    public let taskTitle: String?
    public let eligibleSeconds: TimeInterval
    public var id: String { session.id }
}

public struct RecoveryReview: Codable, Identifiable, Sendable {
    public let gap: RecoveryGap
    public let sessions: [RecoverySessionReview]
    public var id: String { gap.id }
    public var eligibleSeconds: TimeInterval { sessions.reduce(0) { $0 + $1.eligibleSeconds } }
}

public struct RecoveryStatus: Codable, Sendable {
    public let observing: RecoveryGap?
    public let reviews: [RecoveryReview]
    public let unresolvedSessionIDs: Set<String>

    private enum CodingKeys: String, CodingKey { case observing, reviews, unresolvedSessionIDs }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(observing, forKey: .observing)
        try container.encode(reviews, forKey: .reviews)
        try container.encode(unresolvedSessionIDs.sorted(), forKey: .unresolvedSessionIDs)
    }

    public func suspendsReconciliation(for sessionID: String) -> Bool {
        unresolvedSessionIDs.contains(sessionID)
    }
}

extension Store {
    public func recoveryStatus() throws -> RecoveryStatus {
        try db.read { try recoveryStatus($0) }
    }

    private func recoveryStatus(_ db: Database) throws -> RecoveryStatus {
        let observing = try observingRecovery(db)
        let gaps = try RecoveryGap.filter(Column("state") == RecoveryState.review)
            .order(Column("startedAt"), Column("id")).fetchAll(db)
        let reviews = try gaps.map { gap in
            let impacts = try RecoveryImpact.filter(Column("gapId") == gap.id).fetchAll(db)
            let sessions = try impacts.map { impact in
                let session = try Session.fetchOne(db, key: impact.sessionId)!
                let title = try session.taskId.flatMap { try FocusTask.fetchOne(db, key: $0)?.title }
                return RecoverySessionReview(session: session, taskTitle: title, eligibleSeconds: impact.eligibleSeconds)
            }.sorted { ($0.session.startedAt, $0.id) < ($1.session.startedAt, $1.id) }
            return RecoveryReview(gap: gap, sessions: sessions)
        }
        let ids = try String.fetchAll(db, sql: """
            SELECT DISTINCT sessionId FROM recoveryImpact JOIN recoveryGap ON recoveryGap.id = gapId
            WHERE state IN ('observing', 'review')
            """)
        return RecoveryStatus(observing: observing, reviews: reviews, unresolvedSessionIDs: Set(ids))
    }

    @discardableResult
    public func observeRecovery(_ event: RecoveryEvent, at instant: RecoveryInstant) throws -> RecoveryStatus {
        guard instant.date.timeIntervalSinceReferenceDate.isFinite,
              instant.continuousSeconds.map({ $0.isFinite && $0 >= 0 && instant.clockID?.isEmpty == false }) ?? (instant.clockID == nil) else {
            throw ThreeError.invalid("Recovery needs a valid timestamp and clock identity.")
        }
        return try write { db in
            let gap = try observingRecovery(db)
            switch event {
            case .began(let source):
                var current: RecoveryGap
                if let gap {
                    current = gap
                } else {
                    let previousEnd = try Date.fetchOne(db, sql: "SELECT MAX(endedAt) FROM recoveryGap")
                    current = RecoveryGap(id: UUID().uuidString, startedAt: instant.date, lastObservedAt: instant.date,
                                      continuousSeconds: instant.continuousSeconds, clockID: instant.clockID,
                                      clockReliable: previousEnd.map { instant.date >= $0 } ?? true,
                                      sleeping: false, locked: false, awaySeconds: 0, state: .observing)
                    try current.insert(db)
                }
                current.observe(instant)
                current.set(source, active: true)
                try current.update(db)
                if let session = try runningSession(db) {
                    try trackRecoverySession(session, at: instant.date, db)
                }
            case .ended(let source):
                guard var current = gap, current.contains(source) else { return try recoveryStatus(db) }
                current.observe(instant)
                current.set(source, active: false)
                if !current.sleeping && !current.locked {
                    try finishRecovery(&current, at: instant, db)
                } else {
                    try current.update(db)
                }
            case .relaunched:
                if var current = gap { try finishRecovery(&current, at: instant, db) }
            case .clockChanged:
                if var current = gap {
                    current.clockReliable = false
                    try current.update(db)
                }
            }
            return try recoveryStatus(db)
        }
    }

    private func observingRecovery(_ db: Database) throws -> RecoveryGap? {
        try RecoveryGap.filter(Column("state") == RecoveryState.observing).fetchOne(db)
    }

    func trackRecoverySession(_ session: Session, at now: Date, finishingPause: Bool = false, _ db: Database) throws {
        guard session.kind == .focus, var gap = try observingRecovery(db) else { return }
        if now < gap.lastObservedAt || now < session.startedAt || session.pausedAt.map({ $0 > now }) == true {
            gap.clockReliable = false
        }
        gap.lastObservedAt = max(gap.lastObservedAt, now)
        try gap.update(db)
        try db.execute(sql: """
            INSERT INTO recoveryImpact(gapId, sessionId, baselineWork) VALUES(?, ?, ?)
            ON CONFLICT(gapId, sessionId) DO NOTHING
            """, arguments: [gap.id, session.id, session.recordedElapsed(at: now)])
        if finishingPause, let pausedAt = session.pausedAt {
            let pause = max(0, now.timeIntervalSince(pausedAt))
            let roundingCredit = pause - pause.rounded(.down)
            try db.execute(sql: """
                UPDATE recoveryImpact SET baselineWork = baselineWork + ? WHERE gapId = ? AND sessionId = ?
                """, arguments: [roundingCredit, gap.id, session.id])
        }
    }

    private func finishRecovery(_ gap: inout RecoveryGap, at instant: RecoveryInstant, _ db: Database) throws {
        gap.finish(instant)
        let impacts = try RecoveryImpact.filter(Column("gapId") == gap.id).fetchAll(db)
        var candidates: [RecoveryImpact] = []
        for var impact in impacts {
            let session = try Session.fetchOne(db, key: impact.sessionId)!
            let delta = session.recordedElapsed(at: instant.date) - impact.baselineWork
            if delta < -0.002 || session.endedAt.map({ $0 < gap.startedAt }) == true { gap.clockReliable = false }
            impact.eligibleSeconds = max(0, min(delta, session.elapsed(at: instant.date)))
            candidates.append(impact)
        }
        if impacts.isEmpty { gap.state = .notRequired }
        else if !gap.clockReliable { gap.state = .review }
        for var impact in candidates {
            if !gap.clockReliable { impact.eligibleSeconds = 0 }
            try impact.update(db)
        }
        try gap.update(db)
    }

    @discardableResult
    public func decideRecovery(_ id: String, decision: RecoveryDecision, now: Date = Date()) throws -> RecoveryGap {
        try write { db in
            guard var gap = try RecoveryGap.fetchOne(db, key: id), gap.state != .observing else {
                throw ThreeError.invalid("Return from the interruption before reviewing it.")
            }
            guard gap.state == .review else { return gap }
            if case .trim = decision {
                guard gap.clockReliable else { throw ThreeError.invalid("The clock changed. Only keeping recorded time is available.") }
                let impacts = try RecoveryImpact.filter(Column("gapId") == id).fetchAll(db)
                for impact in impacts {
                    try db.execute(sql: """
                        UPDATE session SET recoveryTrimSeconds = recoveryTrimSeconds + ?, updatedAt = MAX(updatedAt, ?)
                        WHERE id = ?
                        """, arguments: [impact.eligibleSeconds, now, impact.sessionId])
                }
                gap.state = .trimmed
            } else {
                gap.state = .kept
            }
            gap.decidedAt = now
            try gap.update(db)
            return gap
        }
    }

    static func hasPendingRecovery(_ db: Database, day: DayKey) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS(
                SELECT 1 FROM recoveryGap g JOIN recoveryImpact i ON i.gapId = g.id
                JOIN session s ON s.id = i.sessionId LEFT JOIN task t ON t.id = s.taskId
                LEFT JOIN dayPlan p ON p.id = t.dayPlanId
                WHERE g.state IN ('observing', 'review')
                AND ((s.startedAt >= ? AND s.startedAt < ?) OR p.day = ?)
            )
            """, arguments: [day.startDate, day.adding(days: 1).startDate, day]) ?? false
    }
}
