import Foundation
import Testing
@testable import ThreeCore

private func calendar(_ zone: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    return c
}

private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func domain(_ text: String) -> BlockDomain { try! BlockDomain(parsing: text) }

private func rule(_ id: String, _ text: String, enabled: Bool = true) -> BlockRule {
    BlockRule(id: id, target: .domain(domain(text)), enabled: enabled, createdAt: .distantPast)
}

private func window(_ day: Weekday, _ start: String, _ end: String) -> FocusWindow {
    FocusWindow(id: "\(day)-\(start)", weekday: day, start: ClockTime(parsing: start)!, end: ClockTime(parsing: end)!)
}

private func focus(_ startedAt: Date, minutes: Int, pausedAt: Date? = nil, kind: SessionKind = .focus,
                   strict: Bool = false) -> RunningFocus {
    let s = Session(id: "s1", taskId: "t1", kind: kind, plannedSeconds: minutes * 60, startedAt: startedAt, pausedAt: pausedAt,
                    pausedSeconds: 0, endedAt: nil, endReason: nil, outcome: nil, focusRating: nil, note: nil, updatedAt: startedAt)
    return RunningFocus(session: s, taskTitle: "Write PRD", categoryColor: "#6E9BF2", strict: strict)
}

private func evaluate(_ now: Date, zone: String = "UTC", rules: [BlockRule] = [rule("r", "reddit.com")],
                      windows: [FocusWindow] = [], running: RunningFocus? = nil,
                      exceptions: [BlockException] = []) -> BlockPolicy {
    BlockPolicy.evaluate(at: now, calendar: calendar(zone), rules: rules, windows: windows, running: running, exceptions: exceptions)
}

// MARK: Domains and apps

@Test func domainsNormaliseToOneCanonicalHost() throws {
    let cases: [(String, String)] = [
        ("https://WWW.Reddit.com:443/", "reddit.com"),
        ("  Reddit.com \n", "reddit.com"),
        ("http://old.reddit.com/", "old.reddit.com"),
        ("*.reddit.com", "reddit.com"),
        ("https://*.reddit.com", "reddit.com"),
        ("x.com.", "x.com"),
        ("youtube.com/", "youtube.com"),
        ("www.youtube.com", "youtube.com"),
        ("bücher.de", "xn--bcher-kva.de"),
        ("https://例え.テスト/", "xn--r8jz45g.xn--zckzah"),
    ]
    for (input, expected) in cases {
        #expect(try BlockDomain(parsing: input).rawValue == expected, "\(input)")
    }
}

@Test func domainsRejectWhatTheyCantBlockHonestly() {
    let cases: [(String, DomainProblem)] = [
        ("", .empty),
        ("youtube.com/shorts", .pathRule(suggestion: domain("youtube.com"))),
        ("https://youtube.com/shorts", .pathRule(suggestion: domain("youtube.com"))),
        ("http://reddit.com/r/adhd?sort=new#top", .pathRule(suggestion: domain("reddit.com"))),
        ("https://reddit.com/?x=1", .pathRule(suggestion: domain("reddit.com"))),
        ("https://reddit.com/#top", .pathRule(suggestion: domain("reddit.com"))),
        ("https://例え.テスト/path", .pathRule(suggestion: domain("xn--r8jz45g.xn--zckzah"))),
        ("reddit.com?x=1", .pathRule(suggestion: domain("reddit.com"))),
        ("localhost", .incomplete),
        ("com", .incomplete),
        ("app.localhost", .incomplete),
        ("[::1]", .ipAddress),
        ("https://[::1]/", .ipAddress),
        ("127.0.0.1", .ipAddress),
        ("https://127.0.0.0x1/", .ipAddress),
        ("0x7f000001", .ipAddress),
        ("127.0x", .ipAddress),
        ("http://192.168.1.4/admin", .ipAddress),
        ("ftp://reddit.com", .notWeb),
        ("https://user:pw@reddit.com", .credentials),
        ("under_score.com", .malformed),
        ("-bad.com", .malformed),
        ("a..com", .malformed),
        (String(repeating: "a", count: 64) + ".com", .malformed),
    ]
    for (input, problem) in cases {
        #expect(throws: BlockError.invalidDomain(problem), "\(input)") { try BlockDomain(parsing: input) }
    }
}

@Test func domainsCoverSubdomainsAtLabelBoundaries() {
    #expect(domain("reddit.com").covers(domain("old.reddit.com")))
    #expect(domain("reddit.com").covers(domain("reddit.com")))
    #expect(!domain("reddit.com").covers(domain("notreddit.com")))
    #expect(!domain("old.reddit.com").covers(domain("reddit.com")))
}

@Test func presetsAreExplicitDomainsAndLeaveTcoAlone() {
    #expect(BlockPreset.x.domains.map(\.rawValue) == ["x.com", "twitter.com"])
    #expect(BlockPreset.reddit.domains.map(\.rawValue) == ["reddit.com", "redd.it"])
    #expect(BlockPreset.youtube.domains.map(\.rawValue) == ["youtube.com", "youtu.be"])
    #expect(!BlockPreset.allCases.flatMap(\.domains).contains { $0.covers(domain("t.co")) })
    #expect(domain("redd.it").label == "Reddit")
    #expect(domain("news.ycombinator.com").label == "news.ycombinator.com")
}

@Test func appsNeverIncludeThreeOrEssentialSystemApps() throws {
    let slack = try AppBundleID(parsing: " com.tinyspeck.slackmacgap ")
    #expect(slack.rawValue == "com.tinyspeck.slackmacgap")
    #expect(slack.matches("com.TinySpeck.SlackMacGap"))
    #expect(!slack.matches(nil))
    #expect(throws: BlockError.protectedApp("com.apple.Finder")) { try AppBundleID(parsing: "com.apple.Finder") }
    #expect(throws: BlockError.protectedApp(ThreeVersion.bundleID)) { try AppBundleID(parsing: ThreeVersion.bundleID) }
    for bad in ["Slack", "com..slack", "com.slack app", ""] {
        #expect(throws: (any Error).self, "\(bad)") { try AppBundleID(parsing: bad) }
    }
}

@Test func typedTextClassifiesAsAnAppOrASite() throws {
    let apps: [(String, String)] = [
        ("com.apple.Music", "com.apple.Music"), (" com.tinyspeck.slackmacgap ", "com.tinyspeck.slackmacgap"),
        ("org.mozilla.firefox", "org.mozilla.firefox"), ("com.apple.news", "com.apple.news"),
        ("dev.warp.Warp-Stable", "dev.warp.Warp-Stable"), ("me.proton.pass", "me.proton.pass"), ("com.foo.my_app", "com.foo.my_app"),
    ]
    for (text, id) in apps {
        #expect(try BlockTarget(classifying: text) == .app(AppBundleID(parsing: id)), "\(text)")
    }
    for text in ["reddit.com", "x.com", "news.ycombinator.com", "sub.example.co.uk", "app.slack.com", "linear.app",
                 "dev.to", "Reddit.com", "https://www.reddit.com/", "com.example.org"] {
        #expect(try BlockTarget(classifying: text) == .domain(BlockDomain(parsing: text)), "\(text)")
    }
    #expect(try BlockTarget(classifying: "com.apple.Music").value == "com.apple.Music")
    // An installed app wins over the reverse-DNS guess, never over a scheme or path.
    let installed = { (id: String) in id == "de.zattoo.Player" || id == "app.slack.com" }
    #expect(try BlockTarget(classifying: "de.zattoo.Player") == .domain(BlockDomain(parsing: "de.zattoo.Player")))
    #expect(try BlockTarget(classifying: "de.zattoo.Player", isInstalledApp: installed) == .app(AppBundleID(parsing: "de.zattoo.Player")))
    #expect(try BlockTarget(classifying: "https://app.slack.com", isInstalledApp: installed) == .domain(BlockDomain(parsing: "app.slack.com")))
    #expect(throws: BlockError.invalidDomain(.pathRule(suggestion: domain("youtube.com")))) {
        try BlockTarget(classifying: "youtube.com/shorts")
    }
    #expect(throws: BlockError.protectedApp("com.apple.finder")) { try BlockTarget(classifying: "com.apple.finder") }
    #expect(throws: BlockError.invalidDomain(.empty)) { try BlockTarget(classifying: "  ") }
}

@Test func appBundlePathsClassifyByTheirBundleIdentifier() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let app = folder.appendingPathComponent("Music Fake.app")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.MusicFake",
                                                                      "CFBundlePackageType": "APPL"], format: .xml, options: 0)
    try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
    #expect(try BlockTarget(classifying: app.path) == .app(AppBundleID(parsing: "com.example.MusicFake")))
    #expect(try BlockTarget(classifying: app.path + "/") == .app(AppBundleID(parsing: "com.example.MusicFake")))
    #expect(throws: BlockError.invalidApp("Can't read an app at /nowhere/Gone.app.")) {
        try BlockTarget(classifying: "/nowhere/Gone.app")
    }
    // The explicit app override reads paths too and takes any bundle identifier at its word.
    #expect(try BlockTarget(app: app.path) == .app(AppBundleID(parsing: "com.example.MusicFake")))
    #expect(try BlockTarget(app: "app.slack.com") == .app(AppBundleID(parsing: "app.slack.com")))
    #expect(throws: BlockError.invalidApp("Can't read an app at /nowhere/Gone.app.")) { try BlockTarget(app: "/nowhere/Gone.app") }
}

// MARK: Focus hours

@Test func focusHoursReadDayRangesAndOvernightTimes() throws {
    #expect(try FocusHours(days: "mon-fri", time: "10:00-13:00").days == [.monday, .tuesday, .wednesday, .thursday, .friday])
    #expect(try FocusHours(days: "fri-mon", time: "9-17").days == [.monday, .friday, .saturday, .sunday])
    #expect(try FocusHours(days: "sat, sun", time: "9-17").days == [.saturday, .sunday])
    #expect(try FocusHours(days: "weekends", time: "9-17").days == [.saturday, .sunday])
    #expect(try FocusHours(days: "Daily", time: "9-17").days.count == 7)
    let night = try FocusHours(days: "fri", time: "22:00-02:00")
    #expect(night.start.minutes == 22 * 60 && night.end.minutes == 120)
    #expect(try FocusHours(days: "mon", time: "00:00-24:00").end.minutes == 1440)
    for (days, time) in [("mon", "10:00-10:00"), ("mon", "24:00-02:00"), ("mon", "10:60-11:00"), ("funday", "9-17"),
                         ("mon", "10:00"), ("mon", "9:5-10"), ("mon", "+9-10")] {
        #expect(throws: (any Error).self, "\(days) \(time)") { try FocusHours(days: days, time: time) }
    }
}

@Test func focusHoursStartInclusiveEndExclusive() {
    let hours = [window(.monday, "10:00", "13:00")]
    let before = evaluate(at("2026-11-02T09:59:59Z"), windows: hours)
    #expect(!before.isActive && before.nextChange == at("2026-11-02T10:00:00Z"))
    let start = evaluate(at("2026-11-02T10:00:00Z"), windows: hours)
    #expect(start.focusHours == DateInterval(start: at("2026-11-02T10:00:00Z"), end: at("2026-11-02T13:00:00Z")))
    #expect(start.blocked.map(\.id) == ["r"] && start.until == at("2026-11-02T13:00:00Z"))
    let end = evaluate(at("2026-11-02T13:00:00Z"), windows: hours)
    #expect(!end.isActive && end.blocked.isEmpty)
    #expect(end.nextChange == at("2026-11-09T10:00:00Z"))
}

@Test func overnightHoursWrapSundayIntoMonday() {
    let hours = [window(.sunday, "22:00", "02:00")]
    #expect(evaluate(at("2026-11-08T22:00:00Z"), windows: hours).isActive)
    let monday = evaluate(at("2026-11-09T01:30:00Z"), windows: hours)
    #expect(monday.isActive && monday.until == at("2026-11-09T02:00:00Z"))
    #expect(!evaluate(at("2026-11-09T02:00:00Z"), windows: hours).isActive)
    #expect(!evaluate(at("2026-11-09T23:00:00Z"), windows: hours).isActive)
}

@Test func hoursOnOtherDaysDontFireButSetNextChange() {
    let friday = evaluate(at("2026-11-06T11:00:00Z"), windows: [window(.saturday, "10:00", "12:00")])
    #expect(!friday.isActive && friday.nextChange == at("2026-11-07T10:00:00Z"))
}

@Test func touchingWindowsMergeAcrossMidnight() {
    let hours = [window(.monday, "22:00", "24:00"), window(.tuesday, "00:00", "01:00")]
    #expect(evaluate(at("2026-11-02T23:00:00Z"), windows: hours).until == at("2026-11-03T01:00:00Z"))
}

@Test func hoursFollowTheInjectedTimeZone() {
    let hours = [window(.monday, "10:00", "13:00")]
    #expect(evaluate(at("2026-11-02T15:00:00Z"), zone: "America/New_York", windows: hours).isActive)
    #expect(!evaluate(at("2026-11-02T15:00:00Z"), zone: "UTC", windows: hours).isActive)
}

@Test func skippedSpringTimesStartAtTheNextValidMinute() {
    // New York, 2026-03-08: 02:00 EST jumps to 03:00 EDT, so a 02:30 start becomes 03:00 EDT (07:00Z).
    let ny = [window(.sunday, "02:30", "04:00")]
    let early = evaluate(at("2026-03-08T06:59:00Z"), zone: "America/New_York", windows: ny)
    #expect(!early.isActive && early.nextChange == at("2026-03-08T07:00:00Z"))
    #expect(evaluate(at("2026-03-08T07:10:00Z"), zone: "America/New_York", windows: ny).focusHours
        == DateInterval(start: at("2026-03-08T07:00:00Z"), end: at("2026-03-08T08:00:00Z")))
    // London, 2026-03-29: 01:00 GMT jumps to 02:00 BST.
    #expect(evaluate(at("2026-03-29T01:30:00Z"), zone: "Europe/London", windows: [window(.sunday, "01:15", "03:00")]).focusHours
        == DateInterval(start: at("2026-03-29T01:00:00Z"), end: at("2026-03-29T02:00:00Z")))
}

@Test func repeatedFallTimesUseTheFirstOccurrence() {
    // New York, 2026-11-01: 02:00 EDT falls back to 01:00 EST. 01:30 EDT is 05:30Z; 02:30 EST is 07:30Z.
    let p = evaluate(at("2026-11-01T06:45:00Z"), zone: "America/New_York", windows: [window(.sunday, "01:30", "02:30")])
    #expect(p.focusHours == DateInterval(start: at("2026-11-01T05:30:00Z"), end: at("2026-11-01T07:30:00Z")))
}

// MARK: Sessions

private let t0 = at("2026-11-02T08:00:00Z")

@Test func runningFocusBlocksUntilItsPlannedEnd() {
    let p = evaluate(t0 + 600, running: focus(t0, minutes: 25))
    #expect(p.focus?.phase == .running && p.focus?.taskTitle == "Write PRD")
    #expect(p.until == t0 + 25 * 60 && p.focus?.expiresAt == t0 + 40 * 60)
    #expect(p.nextChange == t0 + 25 * 60 && p.blocked.map(\.id) == ["r"])
}

@Test func overrunBlocksForAtMostFifteenMinutes() {
    let running = focus(t0, minutes: 25)
    let overrun = evaluate(t0 + 25 * 60, running: running)
    #expect(overrun.focus?.phase == .overrun && overrun.until == t0 + 40 * 60 && overrun.nextChange == t0 + 40 * 60)
    #expect(evaluate(t0 + 40 * 60 - 1, running: running).isActive)
    let stale = evaluate(t0 + 40 * 60, running: running)
    #expect(!stale.isActive && stale.blocked.isEmpty)
}

@Test func pausedFocusBlocksForFifteenMinutesAfterThePause() {
    let paused = focus(t0, minutes: 25, pausedAt: t0 + 600)
    let p = evaluate(t0 + 600 + 15 * 60 - 1, running: paused)
    #expect(p.focus?.phase == .paused && p.until == t0 + 600 + 15 * 60)
    #expect(!evaluate(t0 + 600 + 15 * 60, running: paused).isActive)
    // Paused five minutes into an overrun: the pause bound applies, not the overrun one.
    #expect(evaluate(t0 + 44 * 60, running: focus(t0, minutes: 25, pausedAt: t0 + 30 * 60)).focus?.until == t0 + 45 * 60)
    #expect(!evaluate(t0 + 41 * 60, running: focus(t0, minutes: 25, pausedAt: t0 + 41 * 60)).isActive)
}

@Test func breaksBlockOnlyInsideFocusHours() {
    let onBreak = focus(t0, minutes: 5, kind: .break)
    #expect(!evaluate(t0 + 60, running: onBreak).isActive)
    let inside = evaluate(t0 + 60, windows: [window(.monday, "07:00", "09:00")], running: onBreak)
    #expect(inside.focus == nil && inside.focusHours != nil && inside.blocked.map(\.id) == ["r"])
}

@Test func sessionInsideHoursBlocksUntilTheLaterEnd() {
    let p = evaluate(t0 + 60, windows: [window(.monday, "07:00", "09:00")], running: focus(t0, minutes: 25, strict: true))
    #expect(p.until == at("2026-11-02T09:00:00Z") && p.strict)
    #expect(p.nextChange == t0 + 25 * 60)
}

@Test func exceptionsLiftOneRuleUntilTheyExpire() {
    let rules = [rule("r", "reddit.com"), rule("y", "youtube.com"), rule("off", "x.com", enabled: false)]
    let unblock = BlockException(id: "e", ruleId: "r", reason: "Reply to a mod", expiresAt: t0 + 15 * 60)
    let open = evaluate(t0 + 600, rules: rules, running: focus(t0, minutes: 25), exceptions: [unblock])
    #expect(open.blocked.map(\.id) == ["y"] && open.exceptions == [unblock] && open.nextChange == t0 + 15 * 60)
    let closed = evaluate(t0 + 15 * 60, rules: rules, running: focus(t0, minutes: 25), exceptions: [unblock])
    #expect(closed.blocked.map(\.id) == ["r", "y"] && closed.exceptions.isEmpty)
}

@Test func noEnabledRulesMeansNothingIsProtected() {
    let p = evaluate(t0 + 60, rules: [rule("off", "x.com", enabled: false)], windows: [window(.monday, "07:00", "09:00")],
                     running: focus(t0, minutes: 25))
    #expect(!p.isActive && p.focus == nil && p.focusHours == nil && p.nextChange == nil)
}
