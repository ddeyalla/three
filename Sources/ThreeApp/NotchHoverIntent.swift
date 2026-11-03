import Foundation

/// Decides when the notch surface opens and closes from pointer samples, so that passing over the
/// notch (on the way to a menu or a status item) never makes it jump. Pure: callers pass the time,
/// and schedule a wake at `deadline` because a resting pointer sends no events.
struct NotchHoverIntent: Equatable {
    /// The pointer must rest on the collapsed surface this long before it opens.
    static let expandDelay: TimeInterval = 0.28
    /// The pointer must stay off the expanded surface this long before it closes.
    static let collapseDelay: TimeInterval = 0.4
    /// A pinned surface closes after this long without the pointer or a key press on it.
    static let pinTimeout: TimeInterval = 6

    enum Phase: Equatable {
        case collapsed
        /// Over the collapsed surface; opens at the deadline unless the pointer leaves first.
        case opening(at: TimeInterval)
        case expanded
        /// Off the expanded surface; closes at the deadline unless the pointer returns first.
        case closing(at: TimeInterval)
    }

    private(set) var phase: Phase = .collapsed
    /// Opened from the menu, Settings or an accessibility action while the pointer is elsewhere.
    /// Stays open until the pointer visits, a click elsewhere, or the pin times out.
    private(set) var pinned = false
    /// When the pin closes on its own; nil pins until the pointer visits or a click elsewhere
    /// (used while VoiceOver reads the controls, whose navigation sends no key events).
    private var pinExpiry: TimeInterval?

    /// Whether the surface should be drawn expanded.
    var isExpanded: Bool {
        switch phase {
        case .collapsed, .opening: false
        case .expanded, .closing: true
        }
    }

    /// When the controller should sample the pointer again, if a transition is pending.
    var deadline: TimeInterval? {
        if pinned { return pinExpiry }
        switch phase {
        case .opening(let at), .closing(let at): return at
        case .collapsed, .expanded: return nil
        }
    }

    /// A pointer sample. `inside` is hit-tested against the collapsed shape while `isExpanded` is
    /// false and the expanded shape while it is true. `buttonDown` is true while any mouse button is
    /// held, such as dragging across the menu bar, which never starts opening.
    mutating func pointer(inside: Bool, buttonDown: Bool, now: TimeInterval) {
        if pinned {
            if inside {
                unpin()
            } else {
                if let pinExpiry, now >= pinExpiry { reset() }
                return
            }
        }
        switch phase {
        case .collapsed:
            if inside, !buttonDown { phase = .opening(at: now + Self.expandDelay) }
        case .opening(let at):
            if !inside || buttonDown { phase = .collapsed }
            else if now >= at { phase = .expanded }
        case .expanded:
            if !inside { phase = .closing(at: now + Self.collapseDelay) }
        case .closing(let at):
            if inside { phase = .expanded }
            else if now >= at { phase = .collapsed }
        }
    }

    /// A click opens immediately on the surface and closes immediately anywhere else.
    mutating func click(inside: Bool) {
        unpin()
        phase = inside ? .expanded : .collapsed
    }

    /// Open now and stay open while the pointer is elsewhere, for `timeout` (nil: until the pointer
    /// visits or a click elsewhere).
    mutating func pin(now: TimeInterval, timeout: TimeInterval? = Self.pinTimeout) {
        phase = .expanded
        pinned = true
        pinExpiry = timeout.map { now + $0 }
    }

    /// A key press on the pinned surface: keep it open for another full timeout.
    mutating func interacted(now: TimeInterval) {
        guard pinned, pinExpiry != nil else { return }
        pinExpiry = now + Self.pinTimeout
    }

    /// Hidden, dismissed, display asleep or screens changed: forget everything pending.
    mutating func reset() {
        phase = .collapsed
        unpin()
    }

    private mutating func unpin() {
        pinned = false
        pinExpiry = nil
    }
}
