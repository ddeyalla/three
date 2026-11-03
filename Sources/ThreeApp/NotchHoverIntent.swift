import Foundation

/// Decides when the notch surface opens and closes from pointer samples, so that passing over the
/// notch (on the way to a menu or a status item) never makes it jump. Pure: callers pass the time,
/// and schedule a wake at `deadline` because a resting pointer sends no events.
struct NotchHoverIntent: Equatable {
    /// The pointer must rest on the collapsed surface this long before it opens.
    static let expandDelay: TimeInterval = 0.28
    /// The pointer must stay off the expanded surface this long before it closes.
    static let collapseDelay: TimeInterval = 0.4

    enum Phase: Equatable {
        case collapsed
        /// Over the collapsed surface; opens at the deadline unless the pointer leaves first.
        case opening(at: TimeInterval)
        case expanded
        /// Off the expanded surface; closes at the deadline unless the pointer returns first.
        case closing(at: TimeInterval)
    }

    private(set) var phase: Phase = .collapsed
    /// Opened from the menu or Settings while the pointer is elsewhere: stays open until the
    /// pointer has visited the surface once, or a click elsewhere closes it.
    private(set) var pinned = false

    /// Whether the surface should be drawn expanded.
    var isExpanded: Bool {
        switch phase {
        case .collapsed, .opening: false
        case .expanded, .closing: true
        }
    }

    /// When the controller should sample the pointer again, if a transition is pending.
    var deadline: TimeInterval? {
        switch phase {
        case .opening(let at), .closing(let at): at
        case .collapsed, .expanded: nil
        }
    }

    /// A pointer sample. `inside` is hit-tested against the collapsed shape while `isExpanded` is
    /// false and the expanded shape while it is true. `buttonDown` is true while any mouse button is
    /// held, such as dragging across the menu bar, which never starts opening.
    mutating func pointer(inside: Bool, buttonDown: Bool, now: TimeInterval) {
        if pinned {
            guard inside else { return }
            pinned = false
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
        pinned = false
        phase = inside ? .expanded : .collapsed
    }

    /// Menu and Settings entry point: open now and stay open until the pointer visits.
    mutating func pin() {
        phase = .expanded
        pinned = true
    }

    /// Hidden or dismissed: forget everything pending.
    mutating func reset() {
        phase = .collapsed
        pinned = false
    }
}
