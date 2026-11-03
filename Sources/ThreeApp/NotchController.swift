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
/// narrow wing either side; hovering grows it downward into the expanded controls.
struct NotchLayout: Equatable {
    /// Width of each wing beside the camera housing. Narrow enough to leave status items alone.
    static let wingWidth: CGFloat = 64
    /// Concave flare where the shape meets the top edge, so it reads as part of the bezel.
    static let ear: CGFloat = 6
    static let expandedWidth: CGFloat = 400
    static let expandedBodyHeight: CGFloat = 96

    let notchWidth: CGFloat
    let notchHeight: CGFloat

    /// Visible body (excluding the ears) when collapsed.
    var collapsedSize: CGSize { CGSize(width: notchWidth + Self.wingWidth * 2, height: notchHeight) }
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
    let collapsedRect: CGRect
    /// The expanded shape in global coordinates; leaving it collapses.
    var expandedRect: CGRect { frame.insetBy(dx: NotchLayout.ear, dy: 0) }
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
            let layout = NotchLayout(notchWidth: screen.auxiliaryRight.minX - screen.auxiliaryLeft.maxX,
                                     notchHeight: screen.safeTop)
            // Wings (and their ears) must sit inside the menu-bar areas either side of the camera.
            let reach = NotchLayout.wingWidth + NotchLayout.ear
            guard screen.auxiliaryLeft.width >= reach, screen.auxiliaryRight.width >= reach else { return nil }
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

    /// Whether the surface should be expanded for a pointer at `mouse` (global coordinates).
    /// Expands on entering the collapsed shape; stays open until the pointer leaves the expanded one.
    /// `pinned` (opened from the menu or Settings, pointer elsewhere) stays open until the pointer has
    /// visited the surface once, or the user clicks elsewhere or presses Esc.
    static func wantsExpanded(mouse: CGPoint, expanded: Bool, pinned: Bool = false,
                              placement: NotchPlacement) -> Bool {
        if expanded, pinned { return true }
        // The top screen row reports y == maxY, so grow the rects upward by a point.
        let rect = expanded ? placement.expandedRect.insetBy(dx: -Space.xs, dy: 0)
            : placement.collapsedRect
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + 1).contains(mouse)
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
    @ObservationIgnored private var pinned = false
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
        setExpanded(true)
        pinned = true
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
        track(NSEvent.mouseLocation)
    }

    private func hide() {
        removeMouseMonitors()
        setExpanded(false, animated: false)
        panel?.orderOut(nil)
        isVisible = false
    }

    // MARK: Hover

    /// Global monitors see the pointer over other apps; local ones see it over our own panel.
    /// Pointer-move monitoring needs no Accessibility permission.
    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.track(NSEvent.mouseLocation) }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.track(NSEvent.mouseLocation) }
            return event
        }) { mouseMonitors.append(local) }
        // A click anywhere else collapses, like the Dynamic Island.
        if let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.setExpanded(false) }
        }) { mouseMonitors.append(click) }
    }

    private func removeMouseMonitors() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
    }

    private func track(_ mouse: CGPoint) {
        guard isVisible, let placement else { return }
        if pinned, NotchGeometry.wantsExpanded(mouse: mouse, expanded: true, placement: placement) { pinned = false }
        let wanted = NotchGeometry.wantsExpanded(mouse: mouse, expanded: surface.isExpanded, pinned: pinned,
                                                 placement: placement)
        if wanted != surface.isExpanded { setExpanded(wanted) }
    }

    private func setExpanded(_ expanded: Bool, animated: Bool = true) {
        // Collapsed, the transparent panel must not swallow clicks meant for the menu bar or apps below.
        panel?.ignoresMouseEvents = !expanded
        if !expanded { pinned = false }
        guard surface.isExpanded != expanded else { return }
        if !expanded, panel?.isKeyWindow == true { panel?.resignKey() }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animation: Animation? = !animated ? nil
            : reduceMotion ? nil
            : expanded ? .spring(duration: 0.34, bounce: 0.18) : .spring(duration: 0.24, bounce: 0)
        withAnimation(animation) { surface.isExpanded = expanded }
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
