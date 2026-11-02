import Foundation

public enum ChromeExtension {
    /// Fixed by the public `key` in Extensions/Chrome/manifest.json; a test derives it from that key.
    public static let id = "mgaphdelplkgbnffedmakgpemgnhnaai"
    /// Must match the manifest's version, so the app can tell a stale unpacked copy.
    public static let version = "0.3.1"
    public static var origin: String { "chrome-extension://\(id)/" }
}

public enum ChromeSetupError: LocalizedError, Equatable {
    case browserNotFound(String)
    case launcherMissing(String)
    case extensionMissing(String)
    case foreignManifest(String)
    case foreignExtension(String)

    public var errorDescription: String? {
        switch self {
        case .browserNotFound(let path): "Chrome's data folder isn't at \(path). Open Chrome once, then try again."
        case .launcherMissing(let path): "The native host launcher isn't at \(path). Build or reinstall Three."
        case .extensionMissing(let path): "The Chrome extension isn't at \(path). Build or reinstall Three."
        case .foreignManifest(let path): "\(path) belongs to something else, so Three left it alone. Move it aside to connect Chrome."
        case .foreignExtension(let path): "\(path) isn't Three's extension copy, so Three left it alone. Move it aside to connect Chrome."
        }
    }
}

/// Connects one Chromium browser to Three: copies the extension to a stable folder Chrome can load unpacked,
/// and writes the user-level native-messaging host manifest that lets only that extension start the host.
/// Every path is explicit; nothing here assumes the user's real Chrome folder.
public struct ChromeSetup: Sendable {
    public enum ManifestStatus: Equatable, Sendable {
        case missing
        /// Ours, pointing at `path`.
        case installed(path: String?)
        /// A file at our name that isn't ours, or isn't readable as a host manifest.
        case foreign
    }

    /// The executable Chrome starts: `Three.app/Contents/Helpers/three-native-host`.
    public let launcher: URL
    /// The extension folder inside the app bundle.
    public let bundledExtension: URL
    /// Where Chrome loads the extension from. Outside the app bundle, so reinstalling keeps the path.
    public let extensionFolder: URL
    /// Chrome's user data folder, e.g. `~/Library/Application Support/Google/Chrome`.
    public let browserDataFolder: URL

    public init(launcher: URL, bundledExtension: URL, extensionFolder: URL, browserDataFolder: URL) {
        self.launcher = launcher
        self.bundledExtension = bundledExtension
        self.extensionFolder = extensionFolder
        self.browserDataFolder = browserDataFolder
    }

    public var manifestURL: URL {
        browserDataFolder.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            .appendingPathComponent("\(NativeMessaging.hostName).json")
    }

    public func manifestStatus() -> ManifestStatus {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["name"] as? String == NativeMessaging.hostName else { return .foreign }
        return .installed(path: json["path"] as? String)
    }

    public func manifestData() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "name": NativeMessaging.hostName,
            "description": "Three focus blocker",
            "path": launcher.path,
            "type": "stdio",
            "allowed_origins": [ChromeExtension.origin],
        ] as [String: Any], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Safe to run again: it refreshes the extension copy and rewrites only Three's own manifest.
    public func install() throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: browserDataFolder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ChromeSetupError.browserNotFound(browserDataFolder.path)
        }
        guard launcher.path.hasPrefix("/"), fm.isExecutableFile(atPath: launcher.path) else {
            throw ChromeSetupError.launcherMissing(launcher.path)
        }
        guard fm.fileExists(atPath: bundledExtension.appendingPathComponent("manifest.json").path) else {
            throw ChromeSetupError.extensionMissing(bundledExtension.path)
        }
        guard manifestStatus() != .foreign else { throw ChromeSetupError.foreignManifest(manifestURL.path) }
        if fm.fileExists(atPath: extensionFolder.path) {
            let values = try extensionFolder.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true, let key = extensionKey(at: bundledExtension),
                  extensionKey(at: extensionFolder) == key else {
                throw ChromeSetupError.foreignExtension(extensionFolder.path)
            }
        }

        try fm.createDirectory(at: extensionFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = extensionFolder.deletingLastPathComponent()
            .appendingPathComponent(".\(extensionFolder.lastPathComponent)-\(UUID().uuidString)", isDirectory: true)
        try fm.copyItem(at: bundledExtension, to: staging)
        do {
            if fm.fileExists(atPath: extensionFolder.path) {
                _ = try fm.replaceItemAt(extensionFolder, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: extensionFolder)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }

        try fm.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manifestData().write(to: manifestURL, options: .atomic)
    }

    private func extensionKey(at folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = manifest["key"] as? String, !key.isEmpty else { return nil }
        return key
    }

    /// Removes Three's manifest so Chrome can no longer start the host. The app should refuse this while
    /// blocking is on; the extension folder stays until the user removes the extension in Chrome.
    public func removeConnection() throws {
        switch manifestStatus() {
        case .missing: return
        case .foreign: throw ChromeSetupError.foreignManifest(manifestURL.path)
        case .installed: try FileManager.default.removeItem(at: manifestURL)
        }
    }
}
