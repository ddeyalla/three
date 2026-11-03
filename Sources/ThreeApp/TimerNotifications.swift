import Foundation
import ThreeCore
import UserNotifications

@MainActor
struct TimerNotificationDelivery {
    var removePending: ([String]) -> Void
    var removeDelivered: ([String]) -> Void
    var add: (UNNotificationRequest, @escaping @Sendable (String?) -> Void) -> Void

    static var system: Self {
        let center = UNUserNotificationCenter.current()
        return Self(removePending: { center.removePendingNotificationRequests(withIdentifiers: $0) },
                    removeDelivered: { center.removeDeliveredNotifications(withIdentifiers: $0) },
                    add: { request, completion in
                        center.add(request) { completion($0.map { String($0.localizedDescription.prefix(400)) }) }
                    })
    }
}

struct TimerNotificationIdentity: Equatable, Sendable {
    let sessionID: String
    let plannedEnd: Date
    let plannedSeconds: Int
    let kind: SessionKind

    init(session: Session) {
        sessionID = session.id
        plannedEnd = session.plannedEnd
        plannedSeconds = session.plannedSeconds
        kind = session.kind
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let id = userInfo["threeSessionID"] as? String, UUID(uuidString: id) != nil,
              let end = userInfo["threePlannedEndReference"] as? Double, end.isFinite,
              let seconds = userInfo["threePlannedSeconds"] as? Int, seconds > 0,
              let kindName = userInfo["threeSessionKind"] as? String,
              let kind = SessionKind(rawValue: kindName) else { return nil }
        sessionID = id
        plannedEnd = Date(timeIntervalSinceReferenceDate: end)
        plannedSeconds = seconds
        self.kind = kind
    }

    var userInfo: [AnyHashable: Any] {
        ["threeSessionID": sessionID, "threePlannedEndReference": plannedEnd.timeIntervalSinceReferenceDate,
         "threePlannedSeconds": plannedSeconds, "threeSessionKind": kind.rawValue]
    }

    func matches(_ session: Session) -> Bool {
        session.id == sessionID && session.plannedEnd == plannedEnd && session.plannedSeconds == plannedSeconds
            && session.kind == kind
    }
}

enum TimerNotificationRoute: Equatable {
    case liveReflection, savedReflection(String), extendTimer(Session), openMain, stale

    static let focusCategory = "three.focus-ended"
    static let breakCategory = "three.break-ended"
    static let reviewAction = "three.review-block"
    static let openAction = "three.open"
    static let extendAction = "three.extend-five"

    static func resolve(action: String, identity: TimerNotificationIdentity?, current: Session?,
                        saved: [DeferredReflection], now: Date, recoverySuspended: Bool = false) -> Self {
        guard [reviewAction, openAction, extendAction, UNNotificationDefaultActionIdentifier].contains(action) else {
            return .stale
        }
        guard let identity else { return .stale }
        if action == openAction { return .openMain }
        if recoverySuspended { return .openMain }
        if identity.kind == .break, action == UNNotificationDefaultActionIdentifier { return .openMain }
        if let session = current, identity.matches(session), session.isRunning, !session.isPaused,
           session.remaining(at: now) <= 0 {
            guard session.kind == .focus else { return .stale }
            return action == extendAction ? .extendTimer(session) : .liveReflection
        }
        if let reflection = saved.first(where: { identity.matches($0.session) }) {
            return action == extendAction ? .stale : .savedReflection(reflection.id)
        }
        return .stale
    }

    static func registerCategories(center: UNUserNotificationCenter = .current()) {
        let open = UNNotificationAction(identifier: openAction, title: "Open Three", options: [.foreground])
        let review = UNNotificationAction(identifier: reviewAction, title: "Review block", options: [.foreground])
        let extend = UNNotificationAction(identifier: extendAction, title: "Add 5 minutes", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: focusCategory, actions: [review, extend, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: breakCategory, actions: [open], intentIdentifiers: []),
        ])
    }
}
