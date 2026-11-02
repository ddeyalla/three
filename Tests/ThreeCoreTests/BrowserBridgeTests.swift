import CryptoKit
import Foundation
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
        try json("{}").write(to: setup.bundledExtension.appendingPathComponent("manifest.json"))
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

@Test func setupNeedsChromeAlreadyThere() throws {
    let box = try Sandbox(chromeExists: false)
    #expect(throws: ChromeSetupError.browserNotFound(box.chrome.path)) { try box.setup.install() }
    #expect(!FileManager.default.fileExists(atPath: box.chrome.path))
    #expect(!FileManager.default.fileExists(atPath: box.setup.extensionFolder.path))
}
