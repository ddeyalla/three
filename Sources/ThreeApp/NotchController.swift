import AppKit
import Observation
import SwiftUI
import ThreeCore

struct NotchScreen: Equatable {
    let id: UInt32
    let name: String
    let isBuiltIn: Bool
    let frame: CGRect
    let visibleFrame: CGRect
    let safeTop: CGFloat
    let auxiliaryLeft: CGRect
    let auxiliaryRight: CGRect
}

/// Sizes of the Dynamic-Island-style surface. The collapsed shape is the hardware notch plus a
/// narrow wing either side. Expanding keeps that footprint in the menu-bar row (so status items
/// are never covered) and grows downward; the wider body only begins below the menu bar.
struct NotchLayout: Equatable {
    /// Widest a wing may be: the progress ring, or `25:00` in Heading (39pt) with a little air.
    /// Kept short because the leftmost status item can sit close to the camera housing.
    static let maxWingWidth: CGFloat = 44
    /// Below this the time no longer fits even at its minimum scale, so the surface stays off.
    static let minWingWidth: CGFloat = 32
    /// Clear space kept between a wing's ear and the edge of the menu-bar area beside the camera.
    static let edgeMargin: CGFloat = Space.sm
    /// Concave flare where the shape meets the top edge, so it reads as part of the bezel.
    static let ear: CGFloat = 6
    /// Concave flare where the neck widens into the body, just below the menu bar.
    static let shoulder: CGFloat = Space.md
    static let expandedWidth: CGFloat = 400
    static let expandedBodyHeight: CGFloat = 96

    let notchWidth: CGFloat
    let notchHeight: CGFloat
    var wingWidth: CGFloat = Self.maxWingWidth

    /// Visible body (excluding the ears) when collapsed. Also the expanded neck in the menu-bar row.
    var collapsedSize: CGSize { CGSize(width: notchWidth + wingWidth * 2, height: notchHeight) }
    var expandedSize: CGSize {
        CGSize(width: max(Self.expandedWidth, collapsedSize.width), height: notchHeight + Self.expandedBodyHeight)
    }
    /// Panel size: the expanded shape plus its ears. The panel never moves or resizes; only the shape does.
    var panelSize: CGSize { CGSize(width: expandedSize.width + Self.ear * 2, height: expandedSize.height) }
}

struct NotchPlacement: Equatable {
    let screenID: UInt32
    let screenName: String
    let layout: NotchLayout
    /// Panel frame in global coordinates, top edge flush with the top of the display.
    let frame: CGRect
    /// The collapsed shape (notch plus wings) in global coordinates; hovering here expands.
    /// Expanded, this is still all the surface occupies in the menu-bar row.
    let collapsedRect: CGRect
    /// The part of the expanded shape below the menu bar, in global coordinates.
    var bodyRect: CGRect {
        let size = layout.expandedSize
        return CGRect(x: frame.midX - size.width / 2, y: frame.minY,
                      width: size.width, height: size.height - layout.notchHeight)
    }
}

enum NotchGeometry {
    static func placement(screens: [NotchScreen]) -> NotchPlacement? {
        let candidates = screens.compactMap { screen -> NotchPlacement? in
            let rectangles = [screen.frame, screen.visibleFrame, screen.auxiliaryLeft, screen.auxiliaryRight]
            guard rectangles.allSatisfy({ rect in
                [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                    && rect.width > 0 && rect.height > 0
            }), screen.safeTop.isFinite, screen.safeTop > 0, screen.safeTop < screen.frame.height,
                screen.frame.contains(screen.visibleFrame),
                screen.frame.contains(screen.auxiliaryLeft), screen.frame.contains(screen.auxiliaryRight),
                screen.auxiliaryLeft.maxX < screen.auxiliaryRight.minX else { return nil }

            let top = screen.frame.maxY
            guard screen.auxiliaryLeft.minY >= top - screen.safeTop,
                  screen.auxiliaryRight.minY >= top - screen.safeTop else { return nil }
            // Wings (with their ears and a margin) must sit inside the menu-bar areas beside the camera.
            let side = min(screen.auxiliaryLeft.width, screen.auxiliaryRight.width)
            let wing = min(NotchLayout.maxWingWidth, side - NotchLayout.ear - NotchLayout.edgeMargin)
            guard wing >= NotchLayout.minWingWidth else { return nil }
            let layout = NotchLayout(notchWidth: screen.auxiliaryRight.minX - screen.auxiliaryLeft.maxX,
                                     notchHeight: screen.safeTop, wingWidth: wing)
            let panel = layout.panelSize
            guard screen.frame.width >= panel.width, screen.frame.height >= panel.height * 2 else { return nil }

            let center = (screen.auxiliaryLeft.maxX + screen.auxiliaryRight.minX) / 2
            let x = min(max(center - panel.width / 2, screen.frame.minX), screen.frame.maxX - panel.width)
            let frame = CGRect(x: x, y: top - panel.height, width: panel.width, height: panel.height)
            let collapsed = layout.collapsedSize
            let collapsedRect = CGRect(x: center - collapsed.width / 2, y: top - collapsed.height,
                                       width: collapsed.width, height: collapsed.height)
            return NotchPlacement(screenID: screen.id, screenName: screen.name, layout: layout,
                                  frame: frame, collapsedRect: collapsedRect)
        }
        return candidates.first { candidate in screens.contains { $0.id == candidate.screenID && $0.isBuiltIn } }
            ?? candidates.first
    }

    /// Whether `mouse` (global coordinates) is over the surface in its collapsed or expanded shape.
    /// Expanded, the menu-bar row only counts within the collapsed footprint, so moving onto a
    /// status item leaves the surface. The top screen row reports y == maxY, so rects grow up a point.
    static func contains(_ mouse: CGPoint, expanded: Bool, placement: NotchPlacement) -> Bool {
        func hit(_ rect: CGRect, slop: CGFloat) -> Bool {
            CGRect(x: rect.minX - slop, y: rect.minY, width: rect.width + slop * 2, height: rect.height + 1)
                .contains(mouse)
        }
        guard expanded else { return hit(placement.collapsedRect, slop: 0) }
        return hit(placement.collapsedRect, slop: Space.xs) || hit(placement.bodyRect, slop: Space.xs)
    }
}


enum NotchAction {
    case pauseResume, finish, openMain
}

@MainActor
struct NotchCommands {
    let currentSession: () -> Session?
    let togglePause: (Session) -> Void
    let finishEarly: () -> Void
    let openMain: () -> Void

    func perform(_ action: NotchAction, sessionID: String) {
        if case .openMain = action {
            openMain()
            return
        }
        guard let session = currentSession(), session.id == sessionID,
              session.isRunning, session.kind == .focus else { return }
        switch action {
        case .pauseResume: togglePause(session)
        case .finish: finishEarly()
        case .openMain: break
        }
    }
}

struct NotchPresentation {
    private(set) var dismissedSessionID: String?

    mutating func dismiss(sessionID: String) { dismissedSessionID = sessionID }

    func shouldShow(enabled: Bool, session: Session?, reflecting: Bool, supported: Bool) -> Bool {
        return enabled && supported && !reflecting && session?.kind == .focus
            && session?.isRunning == true && session?.id != dismissedSessionID
    }

    mutating func reveal() { dismissedSessionID = nil }
}

@MainActor @Observable
final class NotchPreference {
    static let key = "notchControlsEnabled"
    private let defaults: UserDefaults
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.key) }
    }

    /// On by default: on a notched Mac it should just work. Settings can turn it off.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.key) as? Bool ?? true
    }
}

/// Hover state shared between the controller (which tracks the pointer) and the view (which animates).
@MainActor @Observable
final class NotchSurface {
    var isExpanded = false
    var layout = NotchLayout(notchWidth: 185, notchHeight: 32)
}

@MainActor @Observable
final class NotchController {
    let preference: NotchPreference
    let surface = NotchSurface()
    private(set) var placement: NotchPlacement?
    private(set) var isVisible = false
    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private let commands: NotchCommands
    @ObservationIgnored private var panel: NotchPanel?
    @ObservationIgnored private var presentation = NotchPresentation()
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var mouseMonitors: [Any] = []
    @ObservationIgnored private var intent = NotchHoverIntent()
    /// The one pending wake for a hover transition; replaced on every sample, cancelled on hide.
    @ObservationIgnored private var wake: Task<Void, Never>?
    @ObservationIgnored private var observing = false
    @ObservationIgnored private var generation = 0

    var availabilityText: String {
        guard let placement else {
            return "No notched display right now. Use Three’s menu-bar controls."
        }
        return "Lives in the notch on \(placement.screenName) during focus blocks. Hover it for controls; Esc hides it for this block."
    }

    init(model: AppModel, defaults: UserDefaults = .standard, openMain: @escaping () -> Void) {
        self.model = model
        preference = NotchPreference(defaults: defaults)
        commands = NotchCommands(currentSession: { [weak model] in
            model?.reload()
            return model?.reflectionPresentation == nil ? model?.running : nil
        }, togglePause: { [weak model] session in
            model?.togglePause(expectedSession: session)
        },
        finishEarly: { [weak model] in model?.finishEarly() }, openMain: openMain)
    }

    isolated deinit { stop() }

    func start() {
        guard !observing else { return }
        observing = true
        generation += 1
        let local = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        for (center, names) in [
            (local, [NSApplication.didChangeScreenParametersNotification,
                     NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification]),
            (workspace, [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification]),
        ] {
            for name in names {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reconcile() }
                }
                observers.append((center, token))
            }
        }
        observeState()
    }

    func stop() {
        observing = false
        generation += 1
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
        hide()
    }

    /// Menu and Settings entry point: reveal after Esc and open the controls for keyboard use.
    func showControls() {
        presentation.reveal()
        reconcile()
        guard isVisible else { return }
        intent.pin()
        apply(mouse: NSEvent.mouseLocation)
        panel?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        if let session = model.running { presentation.dismiss(sessionID: session.id) }
        hide()
    }

    private func observeState() {
        guard observing else { return }
        let observedGeneration = generation
        withObservationTracking {
            _ = model.snapshot
            _ = model.reflectionPresentation
            _ = preference.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observing, self.generation == observedGeneration else { return }
                self.observeState()
            }
        }
        reconcile()
    }

    private func reconcile() {
        guard observing else { return }
        placement = NotchGeometry.placement(screens: NSScreen.screens.compactMap { screen -> NotchScreen? in
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return NotchScreen(id: id, name: screen.localizedName, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                               frame: screen.frame, visibleFrame: screen.visibleFrame,
                               safeTop: screen.safeAreaInsets.top, auxiliaryLeft: left, auxiliaryRight: right)
        })
        guard presentation.shouldShow(enabled: preference.isEnabled, session: model.running,
                                      reflecting: model.reflectionPresentation != nil, supported: placement != nil),
              let placement else {
            hide()
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if surface.layout != placement.layout { surface.layout = placement.layout }
        if panel.frame != placement.frame { panel.setFrame(placement.frame, display: true) }
        if !panel.isVisible || !panel.isOnActiveSpace { panel.orderFrontRegardless() }
        isVisible = true
        installMouseMonitors()
        sample()
    }

    private func hide() {
        removeMouseMonitors()
        wake?.cancel()
        wake = nil
        intent.reset()
        setExpanded(false, animated: false)
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
        isVisible = false
    }

    // MARK: Hover

    /// Global monitors see the pointer over other apps; local ones see it over our own windows
    /// (including the menu bar while Three is frontmost). Needs no Accessibility permission.
    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        // Releases count as samples, so a drag that ends on the notch starts the dwell there.
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                            .leftMouseUp, .rightMouseUp]
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }) { mouseMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.sample() }
            return event
        }) { mouseMonitors.append(monitor) }
        // A click on the surface opens it at once; anywhere else closes it at once, like the Dynamic Island.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.click() }
        }) { mouseMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.click() }
            return event
        }) { mouseMonitors.append(monitor) }
    }

    private func removeMouseMonitors() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Feed the current pointer to the hover intent. Also runs from the pending wake, because a
    /// pointer resting on the notch sends no events.
    private func sample() {
        guard isVisible, let placement else { return }
        let mouse = NSEvent.mouseLocation
        intent.pointer(inside: NotchGeometry.contains(mouse, expanded: intent.isExpanded, placement: placement),
                       buttonDown: NSEvent.pressedMouseButtons != 0, now: now)
        apply(mouse: mouse)
    }

    private func click() {
        guard isVisible, let placement else { return }
        let mouse = NSEvent.mouseLocation
        intent.click(inside: NotchGeometry.contains(mouse, expanded: intent.isExpanded, placement: placement))
        apply(mouse: mouse)
    }

    /// Bring the drawn state, click capture and pending wake in line with the hover intent.
    private func apply(mouse: CGPoint) {
        setExpanded(intent.isExpanded)
        // Capture clicks only over the drawn shape. The panel's transparent corners sit over status
        // items, and an explicit `ignoresMouseEvents = false` would swallow clicks there too.
        let overShape = intent.isExpanded
            && placement.map { NotchGeometry.contains(mouse, expanded: true, placement: $0) } == true
        if panel?.ignoresMouseEvents != !overShape { panel?.ignoresMouseEvents = !overShape }
        scheduleWake()
    }

    private func scheduleWake() {
        wake?.cancel()
        wake = nil
        guard let deadline = intent.deadline else { return }
        let delay = max(0, deadline - now)
        wake = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.sample()
        }
    }

    private func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard surface.isExpanded != expanded else { return }
        if !expanded, panel?.isKeyWindow == true { panel?.resignKey() }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(animated && !reduceMotion ? NotchMotion.animation(expanding: expanded) : nil) {
            surface.isExpanded = expanded
        }
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.title = "Three Focus Controls"
        // Above the menu bar (24) and status items (25), like other notch apps.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.dismiss = { [weak self] in self?.dismiss() }
        let host = NotchHostingView(rootView: NotchView(commands: commands, surface: surface,
                                                        dismiss: { [weak self] in self?.dismiss() })
            .environment(model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

private final class NotchPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    /// AppKit pushes windows below the menu bar; the notch surface belongs on the top edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
