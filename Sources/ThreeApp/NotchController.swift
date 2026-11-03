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

struct NotchPlacement: Equatable {
    let screenID: UInt32
    let screenName: String
    let frame: CGRect
}

enum NotchGeometry {
    static let panelSize = CGSize(width: 360, height: 144)

    static func placement(screens: [NotchScreen]) -> NotchPlacement? {
        let candidates = screens.compactMap { screen -> (NotchScreen, CGRect)? in
            let rectangles = [screen.frame, screen.visibleFrame, screen.auxiliaryLeft, screen.auxiliaryRight]
            guard rectangles.allSatisfy({ rect in
                [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                    && rect.width > 0 && rect.height > 0
            }), screen.safeTop.isFinite, screen.safeTop > 0, screen.safeTop < screen.frame.height,
                screen.frame.contains(screen.visibleFrame),
                screen.frame.contains(screen.auxiliaryLeft), screen.frame.contains(screen.auxiliaryRight),
                screen.auxiliaryLeft.maxX < screen.auxiliaryRight.minX else { return nil }

            let safeTop = screen.frame.maxY - screen.safeTop
            guard screen.auxiliaryLeft.minY >= safeTop, screen.auxiliaryRight.minY >= safeTop else { return nil }
            let area = screen.visibleFrame.intersection(CGRect(
                x: screen.frame.minX, y: screen.frame.minY,
                width: screen.frame.width, height: screen.frame.height - screen.safeTop))
            let inset = Space.sm
            guard area.width >= panelSize.width + inset * 2,
                  area.height >= panelSize.height + inset * 2 else { return nil }
            let cameraCenter = (screen.auxiliaryLeft.maxX + screen.auxiliaryRight.minX) / 2
            let x = min(max(cameraCenter - panelSize.width / 2, area.minX + inset),
                        area.maxX - panelSize.width - inset)
            let frame = CGRect(x: x, y: area.maxY - inset - panelSize.height,
                               width: panelSize.width, height: panelSize.height)
            return (screen, frame)
        }
        let selected = candidates.first { $0.0.isBuiltIn }
            ?? candidates.first
        return selected.map { NotchPlacement(screenID: $0.0.id, screenName: $0.0.name, frame: $0.1) }
    }
}

enum NotchAction {
    case pauseResume, finish, openMain
}

@MainActor
struct NotchCommands {
    let currentSession: () -> Session?
    let togglePause: () -> Void
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
        case .pauseResume: togglePause()
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.key) as? Bool ?? false
    }
}

@MainActor @Observable
final class NotchController {
    let preference: NotchPreference
    private(set) var placement: NotchPlacement?
    private(set) var isVisible = false
    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private let commands: NotchCommands
    @ObservationIgnored private var panel: NotchPanel?
    @ObservationIgnored private var presentation = NotchPresentation()
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var observing = false
    @ObservationIgnored private var generation = 0

    var availabilityText: String {
        guard let placement else {
            return "No supported notched display. Use Three’s menu-bar controls."
        }
        return "Available on \(placement.screenName). Shows during focus blocks. Escape hides it for this block."
    }

    init(model: AppModel, defaults: UserDefaults = .standard, openMain: @escaping () -> Void) {
        self.model = model
        preference = NotchPreference(defaults: defaults)
        commands = NotchCommands(currentSession: { [weak model] in
            model?.reload()
            return model?.reflectionPresentation == nil ? model?.running : nil
        }, togglePause: { [weak model] in model?.togglePause() },
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

    func showControls() {
        presentation.reveal()
        reconcile()
        if isVisible { panel?.makeKeyAndOrderFront(nil) }
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
        panel.setFrame(placement.frame, display: true)
        if !panel.isVisible || !panel.isOnActiveSpace { panel.orderFrontRegardless() }
        isVisible = true
    }

    private func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.title = "Three Focus Controls"
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.dismiss = { [weak self] in self?.dismiss() }
        let host = NotchHostingView(rootView: NotchView(commands: commands, dismiss: { [weak self] in self?.dismiss() })
            .environment(model))
        host.wantsLayer = true
        host.layer?.cornerRadius = Radius.panel
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        panel.contentView = host
        return panel
    }
}

private final class NotchPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
