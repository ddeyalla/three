import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private unowned let model: AppModel
    private let shortcut: GlobalMenuShortcut
    private let openMain: () -> Void
    private let openSettings: () -> Void
    private var item: NSStatusItem?
    private var popover: NSPopover?
    private var generation = 0

    init(model: AppModel, openMain: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        shortcut = model.setup.shortcut
        self.openMain = openMain
        self.openSettings = openSettings
    }

    func start() {
        guard item == nil else { return }
        generation += 1
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        item.button?.target = self
        item.button?.action = #selector(toggle)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: MenuBarView(openMain: { [weak self] in
            self?.popover?.performClose(nil)
            self?.openMain()
        }, openSettings: { [weak self] in
            self?.popover?.performClose(nil)
            self?.openSettings()
        }).environment(model))
        self.popover = popover
        observeLabel()
        shortcut.start { [weak self] in self?.show() }
    }

    func stop() {
        generation += 1
        shortcut.stop()
        popover?.performClose(nil)
        popover = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    func show() {
        guard let button = item?.button, let popover else { return }
        model.reload()
        NSApp.activate()
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func toggle() {
        if popover?.isShown == true { popover?.performClose(nil) }
        else { show() }
    }

    private func observeLabel() {
        guard let button = item?.button else { return }
        let expected = generation
        let status = withObservationTracking {
            MenuBarStatus(model: model, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.item != nil, self.generation == expected else { return }
                self.observeLabel()
            }
        }
        button.image = NSImage(systemSymbolName: status.symbol, accessibilityDescription: nil)
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.title = status.time.map { " \($0)" } ?? ""
        button.setAccessibilityLabel(status.spokenLabel)
        button.toolTip = status.spokenLabel
    }

    isolated deinit { stop() }
}
