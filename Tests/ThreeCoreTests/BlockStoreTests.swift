import Foundation
import Testing
@testable import ThreeCore

private func freshURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("three-\(UUID().uuidString).sqlite")
}

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// A Monday morning, inside the 10:00-13:00 focus hours some tests add.
private let monday = ISO8601DateFormatter().date(from: "2026-11-02T10:30:00Z")!

private func startFocus(_ store: Store, strict: Bool = false, at now: Date = monday) throws {
    let task = try store.addTask(NewTask(title: "Write PRD", category: "Coding", blockMinutes: 60, strict: strict), source: .cli)
    try store.startFocus(taskId: task.id, minutes: 25, now: now)
}

@Test func migratesFromV6WithBlockingOff() throws {
    let url = freshURL()
    do {
        let old = try Store(url: url, upTo: "v6-deferred-reflections")
        try old.addTask(NewTask(title: "Keep me", category: "Coding", blockMinutes: 30), source: .cli)
    }
    let store = try Store(url: url)
    let status = try store.blockStatus(now: monday, calendar: utc)
    #expect(!status.policy.isActive && status.rules.isEmpty && status.windows.isEmpty && status.browsers.isEmpty)
    #expect(try store.snapshot().tasks.map(\.task.title) == ["Keep me"])
}

@Test func addingRulesIsIdempotentAndSkipsCoveredSubdomains() throws {
    let store = try Store(url: freshURL())
    let reddit = try store.addBlockPreset(.reddit, now: monday)
    #expect(try store.addBlockPreset(.reddit, now: monday).map(\.id) == reddit.map(\.id))
    #expect(try store.addBlockRule(.domain(BlockDomain(parsing: "https://old.reddit.com/")), now: monday).id == reddit[0].id)
    try store.addBlockRule(.app(AppBundleID(parsing: "com.tinyspeck.slackmacgap")), now: monday)
    try store.addBlockRule(.app(AppBundleID(parsing: "com.TinySpeck.SlackMacGap")), now: monday)
    let values = try store.blockStatus(now: monday, calendar: utc).rules.map(\.target.value)
    #expect(values == ["reddit.com", "redd.it", "com.tinyspeck.slackmacgap"])
}

@Test func unsupportedRuleCountsRollBackAddsAndReenabling() throws {
    let store = try Store(url: freshURL())
    let disabled = try store.addBlockRule(.domain(BlockDomain(parsing: "disabled.example.com")))
    try store.setBlockRule(disabled.id, enabled: false)
    try store.db.write { db in
        for i in 0..<(BlockRule.maxDomains - 1) {
            try db.execute(sql: "INSERT INTO blockRule (id, kind, value, enabled, createdAt, updatedAt) VALUES (?, 'domain', ?, 1, ?, ?)",
                           arguments: [UUID().uuidString, "site\(i).example.com", monday, monday])
        }
    }
    #expect(throws: BlockError.tooManyDomains) { try store.addBlockPreset(.x) }
    #expect(try store.blockStatus().rules.filter(\.enabled).count == BlockRule.maxDomains - 1)
    #expect(try !store.blockStatus().rules.contains { BlockPreset.x.domains.map(\.rawValue).contains($0.target.value) })

    let final = try store.addBlockRule(.domain(BlockDomain(parsing: "last.example.com")))
    #expect(try store.addBlockRule(final.target).id == final.id)
    #expect(throws: BlockError.tooManyDomains) { try store.addBlockRule(disabled.target) }
    #expect(throws: BlockError.tooManyDomains) { try store.setBlockRule(disabled.id, enabled: true) }
    #expect(try store.blockStatus().rules.first { $0.id == disabled.id }?.enabled == false)
    try store.addBlockRule(.app(AppBundleID(parsing: "com.example.allowed")))
    try store.removeBlockRule(final.id)
    try store.setBlockRule(disabled.id, enabled: true)
    #expect(try store.blockStatus().rules.filter { $0.enabled && $0.target.kind == "domain" }.count == BlockRule.maxDomains)
}

@Test func looseningRulesWaitsForBlockingToEnd() throws {
    let store = try Store(url: freshURL())
    let reddit = try store.addBlockPreset(.reddit, now: monday)[0]
    try startFocus(store)
    let during = monday.addingTimeInterval(60)
    let refused = BlockError.protectionActive(until: monday.addingTimeInterval(25 * 60))
    #expect(throws: refused) { try store.removeBlockRule(reddit.id, now: during, calendar: utc) }
    #expect(throws: refused) { try store.setBlockRule(reddit.id, enabled: false, now: during, calendar: utc) }
    try store.addBlockPreset(.youtube, now: during)
    try store.setBlockRule(reddit.id, enabled: true, now: during, calendar: utc)
    #expect(try store.blockPolicy(now: during, calendar: utc).blocked.count == 4)

    try store.stop(now: during.addingTimeInterval(60))
    try store.setBlockRule(reddit.id, enabled: false, now: during.addingTimeInterval(120), calendar: utc)
    try startFocus(store, at: during.addingTimeInterval(180))
    // A disabled rule blocks nothing, so removing it isn't loosening.
    try store.removeBlockRule(reddit.id, now: during.addingTimeInterval(240), calendar: utc)
    #expect(!(try store.blockStatus(now: during.addingTimeInterval(240), calendar: utc).rules.contains { $0.id == reddit.id }))
}

@Test func focusHoursChangeAsAGroupAndCantShrinkWhileBlocking() throws {
    let store = try Store(url: freshURL())
    try store.addBlockPreset(.x, now: monday)
    let week = try store.addFocusHours(FocusHours(days: "mon-fri", time: "10:00-13:00"), now: monday)
    #expect(week.map(\.weekday) == [.monday, .tuesday, .wednesday, .thursday, .friday])
    #expect(try store.addFocusHours(FocusHours(days: "mon", time: "10:00-13:00"), now: monday).map(\.id) == [week[0].id])

    let ids = week.map(\.id)
    let refused = BlockError.protectionActive(until: ISO8601DateFormatter().date(from: "2026-11-02T13:00:00Z")!)
    #expect(throws: refused) { try store.removeFocusWindows(ids, now: monday, calendar: utc) }
    #expect(throws: refused) {
        try store.replaceFocusWindows(ids, with: FocusHours(days: "mon-fri", time: "10:00-11:00"), now: monday, calendar: utc)
    }

    let evening = monday.addingTimeInterval(8 * 3600)
    #expect(throws: BlockError.noSuchWindow("nope")) { try store.removeFocusWindows([ids[0], "nope"], now: evening, calendar: utc) }
    #expect(try store.blockStatus(now: evening, calendar: utc).windows.count == 5)
    let replaced = try store.replaceFocusWindows(ids, with: FocusHours(days: "mon-wed", time: "09:00-12:00"), now: evening,
                                                 calendar: utc)
    #expect(try store.blockStatus(now: evening, calendar: utc).windows.map(\.id) == replaced.map(\.id))
}

@Test func exceptionsAreTemporaryAndRefusedInStrictSessions() throws {
    let store = try Store(url: freshURL())
    let reddit = try store.addBlockPreset(.reddit, now: monday)[0]
    #expect(throws: BlockError.notBlocking) {
        try store.requestBlockException(ruleId: reddit.id, reason: "Check a thread", now: monday, calendar: utc)
    }
    try startFocus(store)
    let t = monday.addingTimeInterval(60)
    #expect(throws: BlockError.missingReason) { try store.requestBlockException(ruleId: reddit.id, reason: "  ", now: t, calendar: utc) }
    #expect(throws: BlockError.noSuchRule("made-up")) {
        try store.requestBlockException(ruleId: "made-up", reason: "Check a thread", now: t, calendar: utc)
    }
    let open = try store.requestBlockException(ruleId: reddit.id, reason: "Reply to a mod", now: t, calendar: utc)
    #expect(open.expiresAt == t.addingTimeInterval(5 * 60))
    #expect(try store.requestBlockException(ruleId: reddit.id, reason: "Again", now: t.addingTimeInterval(60), calendar: utc) == open)
    #expect(!(try store.blockPolicy(now: open.expiresAt.addingTimeInterval(-1), calendar: utc).blocked.contains { $0.id == reddit.id }))
    #expect(try store.blockPolicy(now: open.expiresAt, calendar: utc).blocked.contains { $0.id == reddit.id })

    try store.stop(now: monday.addingTimeInterval(600))
    try startFocus(store, strict: true, at: monday.addingTimeInterval(660))
    #expect(throws: BlockError.strictSession) {
        try store.requestBlockException(ruleId: reddit.id, reason: "Just once", now: monday.addingTimeInterval(720), calendar: utc)
    }
}

@Test func hitsCountOnlyRulesInForceAndCollapseBursts() throws {
    let store = try Store(url: freshURL())
    let x = try store.addBlockPreset(.x, now: monday)[0]
    #expect(try !store.recordBlockHit(ruleId: x.id, now: monday, calendar: utc))
    try startFocus(store)
    #expect(try store.recordBlockHit(ruleId: x.id, now: monday.addingTimeInterval(60), calendar: utc))
    #expect(try !store.recordBlockHit(ruleId: x.id, now: monday.addingTimeInterval(65), calendar: utc))
    #expect(try store.recordBlockHit(ruleId: x.id, now: monday.addingTimeInterval(75), calendar: utc))
    #expect(try !store.recordBlockHit(ruleId: "made-up", now: monday.addingTimeInterval(90), calendar: utc))
    #expect(try store.blockStatus(now: monday.addingTimeInterval(90), calendar: utc).hitsToday == [x.id: 2])
}

@Test func handEditedRulesThatDontParseAreIgnored() throws {
    let store = try Store(url: freshURL())
    try store.addBlockPreset(.x, now: monday)
    try store.db.write { db in
        for (kind, value) in [("domain", "Not A Domain"), ("domain", "WWW.REDDIT.COM"), ("app", "com.apple.finder")] {
            try db.execute(sql: "INSERT INTO blockRule (id, kind, value, enabled, createdAt, updatedAt) VALUES (?, ?, ?, 1, ?, ?)",
                           arguments: [UUID().uuidString, kind, value, monday, monday])
        }
    }
    #expect(try store.blockStatus(now: monday, calendar: utc).rules.map(\.target.value) == ["x.com", "twitter.com"])
}

@Test func browserConnectionsLapseWithoutHeartbeats() throws {
    let store = try Store(url: freshURL())
    try store.recordBrowserHello(clientId: "profile-a", extensionVersion: "0.3.0", hostAccess: true, now: monday)
    try store.recordBrowserHeartbeat(clientId: "profile-a", now: monday.addingTimeInterval(100))
    let status = try store.blockStatus(now: monday.addingTimeInterval(219), calendar: utc)
    #expect(status.liveBrowsers(at: monday.addingTimeInterval(219)).map(\.id) == ["profile-a"])
    #expect(status.liveBrowsers(at: monday.addingTimeInterval(220)).isEmpty)
}
