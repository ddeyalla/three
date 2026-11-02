import CryptoKit
import Foundation
import GRDB
import Testing
@testable import ThreeCore

private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func json(_ text: String) -> Data { Data(text.utf8) }

// MARK: Framing

@Test func framesSurviveAnySplitOfTheStream() throws {
    let a = json(#"{"type":"hit","ruleId":"1"}"#), b = json("{}")
    let stream = try NativeMessaging.frame(a) + NativeMessaging.frame(b)
    var decoder = NativeMessageDecoder()
    var out: [Data] = []
    for byte in stream {
        decoder.append(Data([byte]))
        while let payload = try decoder.next() { out.append(payload) }
    }
    #expect(out == [a, b] && !decoder.hasPartialFrame)

    var partial = NativeMessageDecoder()
    partial.append(stream.prefix(6))
    #expect(try partial.next() == nil && partial.hasPartialFrame)
}

@Test func oversizeFramesAreRefusedBeforeTheirBody() throws {
    var decoder = NativeMessageDecoder(limit: 16)
    var length = UInt32(17)
    decoder.append(Data(bytes: &length, count: 4))
    #expect(throws: NativeMessagingError.oversize(17)) { try decoder.next() }
    #expect(throws: NativeMessagingError.oversize(NativeMessaging.maxOutboundBytes + 1)) {
        try NativeMessaging.frame(Data(count: NativeMessaging.maxOutboundBytes + 1))
    }
}

// MARK: What the browser may say

@Test func browserMessagesParseStrictly() throws {
    let client = UUID().uuidString.lowercased(), rule = UUID().uuidString
    #expect(try BrowserMessage(json: json(#"{"type":"hello","protocol":1,"clientId":"\#(client)","version":"0.3.0","hostAccess":true}"#))
        == .hello(clientId: client, extensionVersion: "0.3.0", hostAccess: true))
    #expect(try BrowserMessage(json: json(#"{"type":"hit","ruleId":"\#(rule)"}"#)) == .hit(ruleId: rule))
    let refused = [
        #"{"type":"hello","protocol":2,"clientId":"\#(client)","version":"0.3.0","hostAccess":true}"#,
        #"{"type":"hello","protocol":1,"clientId":"profile","version":"0.3.0","hostAccess":true}"#,
        #"{"type":"hello","protocol":1,"clientId":"\#(client)","version":"<script>","hostAccess":true}"#,
        #"{"type":"hello","protocol":1,"clientId":"\#(client)","version":"0.3.0","hostAccess":1}"#,
        #"{"type":"hit","ruleId":"../../etc/passwd"}"#,
        #"{"type":"removeRule","ruleId":"\#(rule)"}"#,
        #"{"type":"hit"}"#,
        #"["hit"]"#,
        "not json",
    ]
    for text in refused {
        #expect(throws: NativeMessagingError.malformed, "\(text)") { try BrowserMessage(json: json(text)) }
    }
}

// MARK: What the host says

@Test func browserStateCarriesOnlyDomainRulesAndTheLease() throws {
    let now = ISO8601DateFormatter().date(from: "2026-11-02T08:00:00Z")!
    let reddit = BlockRule(id: "R", target: .domain(try BlockDomain(parsing: "redd.it")), enabled: true, createdAt: now)
    let slack = BlockRule(id: "A", target: .app(try AppBundleID(parsing: "com.tinyspeck.slackmacgap")), enabled: true, createdAt: now)
    let session = Session(id: "s", taskId: "t", kind: .focus, plannedSeconds: 1500, startedAt: now, pausedAt: nil, pausedSeconds: 0,
                          endedAt: nil, endReason: nil, outcome: nil, focusRating: nil, note: nil, updatedAt: now)
    let policy = BlockPolicy.evaluate(at: now.addingTimeInterval(60), calendar: .current, rules: [reddit, slack], windows: [],
                                      running: RunningFocus(session: session, taskTitle: "Write PRD", categoryColor: "#6E9BF2",
                                                            strict: true), exceptions: [])
    let frame = try BrowserState(policy).frame(validUntil: now.addingTimeInterval(180))
    var decoder = NativeMessageDecoder(limit: NativeMessaging.maxOutboundBytes)
    decoder.append(frame)
    let payload = try #require(try decoder.next())
    let wire = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
    #expect(wire["type"] as? String == "state" && wire["protocol"] as? Int == 1 && wire["active"] as? Bool == true)
    #expect(wire["reason"] as? String == "focus" && wire["strict"] as? Bool == true)
    #expect(wire["validUntil"] as? Int64 == 1_793_606_580_000 && wire["until"] as? Int64 == 1_793_607_900_000)
    #expect(wire["task"] as? [String: String] == ["title": "Write PRD", "color": "#6E9BF2"])
    #expect(wire["rules"] as? [[String: String]] == [["id": "R", "domain": "redd.it", "label": "Reddit"]])

    let off = BrowserState(BlockPolicy.evaluate(at: now, calendar: .current, rules: [reddit], windows: [], running: nil, exceptions: []))
    #expect(!off.active && off.rules.isEmpty && off.reason == nil)
}

// MARK: Chrome setup

@Test func largestSupportedBrowserStateFitsTheWireLimit() throws {
    let now = Date()
    let label = String(repeating: "a", count: 63)
    let domain = try BlockDomain(parsing: [label, label, label, String(repeating: "a", count: 61)].joined(separator: "."))
    let rules = (0..<BlockRule.maxDomains).map { _ in
        BlockRule(id: UUID().uuidString, target: .domain(domain), enabled: true, createdAt: now)
    }
    let session = Session(id: "s", taskId: "t", kind: .focus, plannedSeconds: 1500, startedAt: now, pausedAt: nil, pausedSeconds: 0,
                          endedAt: nil, endReason: nil, outcome: nil, focusRating: nil, note: nil, updatedAt: now)
    for title in ["😀" + String(repeating: "a", count: 199), "a" + String(repeating: "\u{301}", count: 10_000)] {
        let focus = RunningFocus(session: session, taskTitle: title, categoryColor: "#6E9BF2", strict: false)
        let policy = BlockPolicy.evaluate(at: now, calendar: .current, rules: rules, windows: [], running: focus, exceptions: [])
        let state = BrowserState(policy)
        #expect(state.taskTitle == String(String.UnicodeScalarView(title.unicodeScalars.prefix(200))))
        #expect(try state.frame(validUntil: now + 120).count <= NativeMessaging.maxOutboundBytes + 4)
        #expect(state.rules.count == BlockRule.maxDomains)
    }
}

@Test func extensionIdIsDerivedFromTheManifestKey() throws {
    let manifest = try #require(try JSONSerialization.jsonObject(
        with: Data(contentsOf: repo.appendingPathComponent("Extensions/Chrome/manifest.json"))) as? [String: Any])
    let encoded = try #require(manifest["key"] as? String)
    let key = try #require(Data(base64Encoded: encoded))
    let letters = Array("abcdefghijklmnop")
    let id = SHA256.hash(data: key).prefix(16).flatMap { [letters[Int($0 >> 4)], letters[Int($0 & 0xF)]] }
    #expect(String(id) == ChromeExtension.id)
    #expect(manifest["version"] as? String == ChromeExtension.version)
}

private struct Sandbox {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("three-chrome-\(UUID().uuidString)")
    var chrome: URL { root.appendingPathComponent("Chrome") }
    var setup: ChromeSetup {
        ChromeSetup(launcher: root.appendingPathComponent("Three.app/Contents/Helpers/three-native-host"),
                    bundledExtension: root.appendingPathComponent("Three.app/Contents/Resources/ChromeExtension"),
                    extensionFolder: root.appendingPathComponent("Support/ChromeExtension"), browserDataFolder: chrome)
    }

    init(chromeExists: Bool = true) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: setup.bundledExtension, withIntermediateDirectories: true)
        try json(#"{"key":"three-test-extension-key"}"#).write(to: setup.bundledExtension.appendingPathComponent("manifest.json"))
        try fm.createDirectory(at: setup.launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json("#!/bin/sh\n").write(to: setup.launcher)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: setup.launcher.path)
        if chromeExists { try fm.createDirectory(at: chrome.appendingPathComponent("NativeMessagingHosts"), withIntermediateDirectories: true) }
    }
}

@Test func setupWritesOnlyThreesManifestAndCanRunAgain() throws {
    let box = try Sandbox()
    let neighbour = box.chrome.appendingPathComponent("NativeMessagingHosts/com.example.other.json")
    try json(#"{"name":"com.example.other"}"#).write(to: neighbour)

    try box.setup.install()
    let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: box.setup.manifestURL)) as? [String: Any])
    #expect(manifest["name"] as? String == "com.deyalla.three" && manifest["type"] as? String == "stdio")
    #expect(manifest["path"] as? String == box.setup.launcher.path)
    #expect(manifest["allowed_origins"] as? [String] == ["chrome-extension://mgaphdelplkgbnffedmakgpemgnhnaai/"])
    #expect(box.setup.manifestStatus() == .installed(path: box.setup.launcher.path))

    try json("stale").write(to: box.setup.extensionFolder.appendingPathComponent("old.js"))
    try box.setup.install()
    #expect(!FileManager.default.fileExists(atPath: box.setup.extensionFolder.appendingPathComponent("old.js").path))
    #expect(FileManager.default.fileExists(atPath: box.setup.extensionFolder.appendingPathComponent("manifest.json").path))
    #expect(try Data(contentsOf: neighbour) == json(#"{"name":"com.example.other"}"#))

    try box.setup.removeConnection()
    #expect(box.setup.manifestStatus() == .missing)
}

@Test func setupLeavesSomeoneElsesManifestAlone() throws {
    let box = try Sandbox()
    let theirs = json(#"{"name":"com.someone.else","path":"/bin/sh"}"#)
    try theirs.write(to: box.setup.manifestURL)
    #expect(throws: ChromeSetupError.foreignManifest(box.setup.manifestURL.path)) { try box.setup.install() }
    #expect(throws: ChromeSetupError.foreignManifest(box.setup.manifestURL.path)) { try box.setup.removeConnection() }
    #expect(try Data(contentsOf: box.setup.manifestURL) == theirs)
}

@Test func connectionRemovalChecksCurrentProtectionInTheStore() throws {
    let box = try Sandbox()
    let url = box.root.appendingPathComponent("guard.sqlite")
    let appStore = try Store(url: url), cliStore = try Store(url: url)
    try box.setup.install()
    try appStore.addBlockRule(.domain(BlockDomain(parsing: "example.com")))
    let now = Date()
    let task = try cliStore.addTask(NewTask(title: "Keep focus", category: "Coding", blockMinutes: 25), source: .app)
    #expect(try !appStore.blockPolicy().isActive)
    try cliStore.startFocus(taskId: task.id, now: now)

    #expect(throws: BlockError.self) { try appStore.removeChromeConnection(box.setup, now: now) }
    #expect(box.setup.manifestStatus() == .installed(path: box.setup.launcher.path))

    try cliStore.stop(now: now.addingTimeInterval(1))
    try appStore.removeChromeConnection(box.setup, now: now.addingTimeInterval(1))
    #expect(box.setup.manifestStatus() == .missing)
}

@Test func connectionRemovalHoldsTheWriterLockDuringItsPolicyCheck() throws {
    let box = try Sandbox()
    let url = box.root.appendingPathComponent("race.sqlite")
    let appStore = try Store(url: url), cliStore = try Store(url: url)
    try box.setup.install()
    try appStore.addBlockRule(.domain(BlockDomain(parsing: "example.com")))
    let task = try cliStore.addTask(NewTask(title: "Concurrent start", category: "Coding", blockMinutes: 25), source: .app)
    try cliStore.db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA busy_timeout = 0") }
    var attempted = false
    var failure: DatabaseError?
    appStore.db.writeWithoutTransaction { db in
        db.trace { event in
            guard !attempted, event.description.hasPrefix("SELECT") else { return }
            attempted = true
            do { try cliStore.startFocus(taskId: task.id) }
            catch { failure = error as? DatabaseError }
        }
    }
    defer { appStore.db.writeWithoutTransaction { $0.trace(nil) } }

    try appStore.removeChromeConnection(box.setup)
    #expect(attempted && failure?.resultCode == .SQLITE_BUSY)
    #expect(box.setup.manifestStatus() == .missing)
    try cliStore.startFocus(taskId: task.id)
    #expect(try cliStore.blockPolicy().isActive)
}

@Test func setupNeedsChromeAlreadyThere() throws {
    let box = try Sandbox(chromeExists: false)
    #expect(throws: ChromeSetupError.browserNotFound(box.chrome.path)) { try box.setup.install() }
    #expect(!FileManager.default.fileExists(atPath: box.chrome.path))
    #expect(!FileManager.default.fileExists(atPath: box.setup.extensionFolder.path))
}

@Test func setupPreservesFoldersItDoesNotOwn() throws {
    for key in [nil, "another-extension-key"] as [String?] {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.setup.extensionFolder, withIntermediateDirectories: true)
        let note = box.setup.extensionFolder.appendingPathComponent("notes.txt")
        try json("Keep this note").write(to: note)
        if let key {
            try JSONSerialization.data(withJSONObject: ["key": key])
                .write(to: box.setup.extensionFolder.appendingPathComponent("manifest.json"))
        }
        #expect(throws: ChromeSetupError.foreignExtension(box.setup.extensionFolder.path)) { try box.setup.install() }
        #expect(try Data(contentsOf: note) == json("Keep this note"))
        #expect(box.setup.manifestStatus() == .missing)
    }
}

@Test func setupDoesNotReplaceASymlinkEvenToAMatchingExtension() throws {
    let box = try Sandbox()
    let fm = FileManager.default
    try fm.createDirectory(at: box.setup.extensionFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: box.setup.extensionFolder, withDestinationURL: box.setup.bundledExtension)
    #expect(throws: ChromeSetupError.foreignExtension(box.setup.extensionFolder.path)) { try box.setup.install() }
    #expect(try box.setup.extensionFolder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    #expect(box.setup.manifestStatus() == .missing)
}
