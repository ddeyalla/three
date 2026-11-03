import AppKit

let info = Bundle.main.infoDictionary!
let title = info["CFBundleDisplayName"] as! String
let logURL = URL(fileURLWithPath: info["QALog"] as! String)

func log(_ message: String) {
    let data = "\(Date().timeIntervalSince1970) pid=\(getpid()) \(message)\n".data(using: .utf8)!
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try! data.write(to: logURL)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit \(title)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 100, y: 180, width: 430, height: 230),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "\(title)\nOwned BPRO-396 fixture. No user documents.")
        label.frame = NSRect(x: 20, y: 150, width: 390, height: 60)
        window.contentView!.addSubview(label)
        for (index, entry) in [("QAOtherApp", "Open distraction fixture"), ("QAThreeApp", "Open Three QA"),
                               ("QAWorkApp", "Activate work fixture")].enumerated() {
            guard info[entry.0] != nil else { continue }
            let button = NSButton(title: entry.1, target: self, action: #selector(openOther(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(entry.0)
            button.frame = NSRect(x: 20, y: 100 - index * 40, width: 240, height: 36)
            window.contentView!.addSubview(button)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        log("launched")
        for (name, message) in [(NSApplication.didBecomeActiveNotification, "active"),
                                (NSApplication.didResignActiveNotification, "inactive"),
                                (NSApplication.didHideNotification, "hidden"),
                                (NSApplication.didUnhideNotification, "unhidden")] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in log(message) }
        }
    }

    @objc func openOther(_ sender: NSButton) {
        let key = sender.identifier!.rawValue
        let path = info[key] as! String
        log("\(key)-clicked")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { app, error in
            log("\(key) result=\(app?.processIdentifier ?? 0) error=\(String(describing: error))")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate
app.run()
