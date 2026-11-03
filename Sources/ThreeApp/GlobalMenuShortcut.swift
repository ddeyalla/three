import AppKit
import Carbon
import Observation

struct MenuShortcut: Codable, Equatable {
    enum Key: String, Codable, CaseIterable {
        case space, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z

        var title: String { self == .space ? "Space" : rawValue.uppercased() }
        var code: UInt32 {
            switch self {
            case .space: 49
            case .a: 0; case .b: 11; case .c: 8; case .d: 2; case .e: 14; case .f: 3
            case .g: 5; case .h: 4; case .i: 34; case .j: 38; case .k: 40; case .l: 37
            case .m: 46; case .n: 45; case .o: 31; case .p: 35; case .q: 12; case .r: 15
            case .s: 1; case .t: 17; case .u: 32; case .v: 9; case .w: 13; case .x: 7
            case .y: 16; case .z: 6
            }
        }
    }

    var key: Key = .space
    var command = true
    var option = true
    var control = false
    var shift = false

    var isValid: Bool { command || option || control }
    var modifiers: UInt32 {
        UInt32((command ? cmdKey : 0) | (option ? optionKey : 0)
            | (control ? controlKey : 0) | (shift ? shiftKey : 0))
    }
    var title: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "")
            + (command ? "⌘" : "") + key.title
    }
}

@MainActor
final class CarbonMenuShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private static let signature: OSType = 0x54485245

    func register(_ shortcut: MenuShortcut, action: @escaping () -> Void) throws {
        stop()
        var symbolicKeys: Unmanaged<CFArray>?
        let copied = CopySymbolicHotKeys(&symbolicKeys)
        guard copied == noErr else { throw ShortcutFailure.registration(copied) }
        guard let keys = symbolicKeys?.takeRetainedValue() as? [[String: Any]] else {
            throw ShortcutFailure.registration(OSStatus(paramErr))
        }
        if Self.conflicts(shortcut, symbolicKeys: keys) {
            throw ShortcutFailure.registration(OSStatus(eventHotKeyExistsErr))
        }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard result == noErr, identity.signature == CarbonMenuShortcut.signature,
                  identity.id == 1 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<CarbonMenuShortcut>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw ShortcutFailure.registration(status) }
        let registered = RegisterEventHotKey(shortcut.key.code, shortcut.modifiers,
                                            EventHotKeyID(signature: Self.signature, id: 1),
                                            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        guard registered == noErr else {
            stop()
            throw ShortcutFailure.registration(registered)
        }
        self.action = action
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        action = nil
    }

    static func conflicts(_ shortcut: MenuShortcut, symbolicKeys: [[String: Any]]) -> Bool {
        symbolicKeys.contains { key in
            (key[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && (key[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == shortcut.key.code
                && (key[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == shortcut.modifiers
        }
    }

    isolated deinit { stop() }
}

enum ShortcutFailure: LocalizedError {
    case invalid, registration(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalid: "Choose Command, Option, or Control with the key."
        case .registration(let status) where status == eventHotKeyExistsErr:
            "This shortcut is already in use. Choose another shortcut or change it in System Settings."
        case .registration(let status):
            "macOS could not register this shortcut (\(status)). Choose another shortcut or retry."
        }
    }
}

@MainActor @Observable
final class GlobalMenuShortcut {
    enum Status: Equatable {
        case stopped, registered, failed(String)
    }

    private(set) var shortcut: MenuShortcut
    private(set) var isEnabled: Bool
    private(set) var status: Status = .stopped
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let register: (MenuShortcut, @escaping () -> Void) throws -> Void
    @ObservationIgnored private let unregister: () -> Void
    @ObservationIgnored private var action: (() -> Void)?
    static let shortcutKey = "menuBarShortcut"
    static let enabledKey = "menuBarShortcutEnabled"

    convenience init(defaults: UserDefaults = .standard) {
        let native = CarbonMenuShortcut()
        self.init(defaults: defaults, register: native.register, unregister: native.stop)
    }

    init(defaults: UserDefaults, register: @escaping (MenuShortcut, @escaping () -> Void) throws -> Void,
         unregister: @escaping () -> Void) {
        self.defaults = defaults
        self.register = register
        self.unregister = unregister
        if let data = defaults.data(forKey: Self.shortcutKey),
           let saved = try? JSONDecoder().decode(MenuShortcut.self, from: data), saved.isValid {
            shortcut = saved
        } else { shortcut = MenuShortcut() }
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start(action: @escaping () -> Void) {
        guard self.action == nil else { return }
        self.action = action
        reconcile()
    }

    func apply(_ shortcut: MenuShortcut, enabled: Bool) {
        guard shortcut.isValid else { status = .failed(ShortcutFailure.invalid.localizedDescription); return }
        self.shortcut = shortcut
        isEnabled = enabled
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: Self.shortcutKey)
        defaults.set(enabled, forKey: Self.enabledKey)
        reconcile()
    }

    func retry() { reconcile() }

    func stop() {
        unregister()
        action = nil
        status = .stopped
    }

    private func reconcile() {
        unregister()
        status = .stopped
        guard let action, isEnabled else { return }
        do {
            try register(shortcut, action)
            status = .registered
        } catch { status = .failed(String(error.localizedDescription.prefix(400))) }
    }

    isolated deinit { unregister() }
}
