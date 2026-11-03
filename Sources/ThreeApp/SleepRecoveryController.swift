import AppKit
import Darwin
import Observation
import ThreeCore

enum RecoverySystemEvent {
    static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    static func event(for name: Notification.Name) -> RecoveryEvent? {
        switch name {
        case NSWorkspace.willSleepNotification: .began(.sleep)
        case NSWorkspace.didWakeNotification: .ended(.sleep)
        case screenLocked: .began(.lock)
        case screenUnlocked: .ended(.lock)
        case .NSSystemClockDidChange: .clockChanged
        default: nil
        }
    }
}

enum RecoverySystemClock {
    private static let bootID: String = {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else {
            return "process-\(UUID().uuidString)"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else {
            return "process-\(UUID().uuidString)"
        }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }()

    static func now() -> RecoveryInstant {
        let id = bootID
        var timebase = mach_timebase_info_data_t(numer: 1, denom: 1)
        mach_timebase_info(&timebase)
        let date = Date()
        let seconds = Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        return RecoveryInstant(date: date, continuousSeconds: seconds, clockID: id)
    }
}

@MainActor @Observable
final class SleepRecoveryController {
    private(set) var status: RecoveryStatus?
    private(set) var error: String?
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let clock: () -> RecoveryInstant
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var observing = false
    @ObservationIgnored private var pendingEvents: [(RecoveryEvent, RecoveryInstant)] = []
    @ObservationIgnored private var decisionError: String?
    private var stateUnavailable = false
    @ObservationIgnored var didChange: (Set<String>) -> Void = { _ in }

    var reviews: [RecoveryReview] { status?.reviews ?? [] }
    var needsRetry: Bool { stateUnavailable }

    init(store: Store, clock: @escaping () -> RecoveryInstant = RecoverySystemClock.now) {
        self.store = store
        self.clock = clock
        refresh()
    }

    isolated deinit { stop() }

    func start(workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
               local: NotificationCenter = .default,
               screen: NotificationCenter = DistributedNotificationCenter.default()) {
        guard !observing else { return }
        observing = true
        for (center, names) in [
            (workspace, [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification]),
            (local, [.NSSystemClockDidChange]),
            (screen, [RecoverySystemEvent.screenLocked, RecoverySystemEvent.screenUnlocked]),
        ] {
            for name in names {
                guard let event = RecoverySystemEvent.event(for: name) else { continue }
                let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        _ = self?.receive(event)
                    }
                }
                observers.append((center, token))
            }
        }
        receive(.relaunched)
    }

    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
        observing = false
    }

    func suspendsReconciliation(for session: Session?) -> Bool {
        guard let session, session.kind == .focus else { return false }
        return stateUnavailable || (status?.suspendsReconciliation(for: session.id) ?? true)
    }

    func suspendsReconciliation(for sessionID: String) -> Bool {
        stateUnavailable || (status?.suspendsReconciliation(for: sessionID) ?? true)
    }

    func retry() {
        decisionError = nil
        let affected = status?.unresolvedSessionIDs ?? []
        refresh()
        didChange(affected.union(status?.unresolvedSessionIDs ?? []))
    }

    @discardableResult
    func receive(_ event: RecoveryEvent, at instant: RecoveryInstant? = nil) -> Bool {
        let affected = status?.unresolvedSessionIDs ?? []
        pendingEvents.append((event, instant ?? clock()))
        let succeeded = refresh()
        didChange(affected.union(status?.unresolvedSessionIDs ?? []))
        return succeeded
    }

    @discardableResult
    func refresh() -> Bool {
        do {
            while let (event, instant) = pendingEvents.first {
                publish(try store.observeRecovery(event, at: instant))
                pendingEvents.removeFirst()
            }
            publish(try store.recoveryStatus())
            stateUnavailable = false
            error = decisionError
            return true
        } catch {
            stateUnavailable = true
            self.error = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func decide(_ id: String, _ decision: RecoveryDecision) -> Bool {
        decisionError = nil
        var affected = status?.unresolvedSessionIDs ?? []
        guard refresh() else { didChange(affected); return false }
        affected.formUnion(status?.unresolvedSessionIDs ?? [])
        let succeeded: Bool
        do {
            try store.decideRecovery(id, decision: decision, now: clock().date)
            publish(try store.recoveryStatus())
            error = nil
            succeeded = true
        } catch {
            decisionError = error.localizedDescription
            self.error = error.localizedDescription
            succeeded = false
        }
        didChange(affected.union(status?.unresolvedSessionIDs ?? []))
        return succeeded
    }

    private func publish(_ next: RecoveryStatus) {
        if let status, status.observing == next.observing,
           status.unresolvedSessionIDs == next.unresolvedSessionIDs,
           status.reviews.count == next.reviews.count,
           zip(status.reviews, next.reviews).allSatisfy({ before, after in
               before.gap == after.gap && before.sessions.count == after.sessions.count
                   && zip(before.sessions, after.sessions).allSatisfy {
                       $0.session == $1.session && $0.taskTitle == $1.taskTitle && $0.eligibleSeconds == $1.eligibleSeconds
                   }
           }) { return }
        status = next
    }
}
