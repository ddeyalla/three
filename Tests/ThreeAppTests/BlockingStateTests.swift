import Foundation
import Testing
import ThreeCore
@testable import ThreeApp

/// Every case reads a fresh Store at fixed instants with an explicit calendar, so nothing depends on today.
@MainActor
struct BlockingStateTests {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// A Monday morning, inside the 10:00-13:00 focus hours some cases add.
    private let monday = ISO8601DateFormatter().date(from: "2026-11-02T10:30:00Z")!
    /// The same Monday evening, outside any focus hours here.
    private var evening: Date { monday.addingTimeInterval(9 * 3600) }

    private func store() throws -> Store {
        try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-blocking-\(UUID().uuidString).sqlite"))
    }

    private func state(_ store: Store, at now: Date) throws -> BlockingState {
        BlockingState(status: try store.blockStatus(now: now, calendar: utc), now: now)
    }

    @discardableResult
    private func focus(_ store: Store, at now: Date, strict: Bool = false) throws -> Session {
        let task = try store.addTask(NewTask(title: "Write PRD", category: "Coding", blockMinutes: 60, strict: strict), source: .app)
        return try store.startFocus(taskId: task.id, minutes: 25, now: now)
    }

    private func site(_ store: Store, _ name: String) throws -> BlockRule {
        try store.addBlockRule(.domain(BlockDomain(parsing: name)), now: monday)
    }

    @Test func offExplainsWhatTurnsBlockingOn() throws {
        let s = try store()
        var off = try state(s, at: evening)
        #expect(off.value == "Off" && off.detail == "Add a website or app to block during focus.")
        #expect(!off.isEnforcing && !off.isDegraded && off.unblockable.isEmpty)

        try site(s, "reddit.com")
        off = try state(s, at: evening)
        #expect(off.detail == "Turns on when you start a focus session.")

        try s.addFocusHours(FocusHours(days: "mon-fri", time: "10:00-13:00"), now: monday)
        off = try state(s, at: evening)
        let tuesdayTen = ISO8601DateFormatter().date(from: "2026-11-03T10:00:00Z")!
        #expect(off.policy.nextChange == tuesdayTen)
        #expect(off.detail == "Turns on with your next focus session, or \(Format.until(tuesdayTen, now: evening)).")
    }

    @Test func sitesWithoutAWorkingProfileAreNamedAsNotBlocked() throws {
        let s = try store()
        try site(s, "reddit.com")
        try focus(s, at: monday)
        let t = monday.addingTimeInterval(60)

        var on = try state(s, at: t)
        #expect(on.policy.isActive && on.isDegraded && !on.isEnforcing)
        #expect(on.headline == "Websites aren't blocked" && on.value == "On, websites not blocked")
        #expect(on.detail == "Chrome isn't connected, so websites aren't blocked · This focus session")

        // Heard from too long ago: a heartbeat stopped arriving.
        try s.recordBrowserHello(clientId: "stale", extensionVersion: ChromeExtension.version, hostAccess: true,
                                 now: t.addingTimeInterval(-BrowserConnection.liveFor - 1))
        on = try state(s, at: t)
        #expect(on.isDegraded && on.workingProfiles.isEmpty)

        try s.recordBrowserHello(clientId: "no-access", extensionVersion: ChromeExtension.version, hostAccess: false, now: t)
        on = try state(s, at: t)
        #expect(on.isDegraded && on.chromeProblem.contains("all sites"))

        try s.recordBrowserHello(clientId: "old", extensionVersion: "0.0.1", hostAccess: true, now: t)
        on = try state(s, at: t)
        #expect(on.isDegraded && on.chromeProblem.contains("needs an update"))

        try s.recordBrowserHello(clientId: "good", extensionVersion: ChromeExtension.version, hostAccess: true, now: t)
        on = try state(s, at: t)
        let until = monday.addingTimeInterval(25 * 60)
        #expect(on.isEnforcing && !on.isDegraded && on.workingProfiles.map(\.id) == ["good"])
        #expect(on.value == "On until \(Format.until(until, now: t))" && on.headline == "Blocking until \(Format.until(until, now: t))")
        #expect(on.detail == "This focus session · Chrome (1 profile)")
    }

    @Test func appRulesAreEnforcedWithoutChrome() throws {
        let s = try store()
        try s.addBlockRule(.app(AppBundleID(parsing: "com.example.blocked")), now: monday)
        try focus(s, at: monday)
        let t = monday.addingTimeInterval(60)
        var on = try state(s, at: t)
        #expect(on.isEnforcing && on.coverage == "Apps only")

        try site(s, "x.com")
        on = try state(s, at: t)
        #expect(on.isEnforcing && !on.isDegraded && on.coverage == "Apps only. Websites aren't blocked.")

        try s.recordBrowserHello(clientId: "a", extensionVersion: ChromeExtension.version, hostAccess: true, now: t)
        try s.recordBrowserHello(clientId: "b", extensionVersion: ChromeExtension.version, hostAccess: true, now: t)
        #expect(try state(s, at: t).coverage == "Chrome (2 profiles) and apps")
    }

    @Test func exceptionsAndStrictTasksChangeWhatCanBeUnblocked() throws {
        let s = try store()
        let reddit = try site(s, "reddit.com")
        try focus(s, at: monday)
        let t = monday.addingTimeInterval(60)
        #expect(try state(s, at: t).unblockable.map(\.id) == [reddit.id])

        let open = try s.requestBlockException(ruleId: reddit.id, reason: "Reply to a mod", now: t, calendar: utc)
        let excepted = try state(s, at: t)
        // Still on, but nothing is in force, so there is nothing to enforce or warn about.
        #expect(excepted.policy.isActive && excepted.policy.blocked.isEmpty)
        #expect(!excepted.isEnforcing && !excepted.isDegraded && excepted.unblockable.isEmpty)
        #expect(excepted.detail == "This focus session · reddit.com open until \(Format.time(open.expiresAt))")

        try s.stop(now: t.addingTimeInterval(60))
        try focus(s, at: t.addingTimeInterval(120), strict: true)
        try s.recordBrowserHello(clientId: "a", extensionVersion: ChromeExtension.version, hostAccess: true, now: t.addingTimeInterval(180))
        let strict = try state(s, at: t.addingTimeInterval(180))
        #expect(strict.policy.strict && strict.unblockable.isEmpty)
        #expect(strict.detail.contains(" · Unblocking off for this task"))
    }

    @Test func theReasonNamesWhateverKeepsBlockingOnLongest() throws {
        let s = try store()
        try s.addBlockRule(.app(AppBundleID(parsing: "com.example.blocked")), now: monday)
        try focus(s, at: evening)
        #expect(try state(s, at: evening.addingTimeInterval(60)).reason == "This focus session")
        // Past the planned 25 minutes, protection lasts at most 15 more, whatever the timer does.
        let over = try state(s, at: evening.addingTimeInterval(30 * 60))
        #expect(over.reason == "Focus session past its end" && over.policy.until == evening.addingTimeInterval(40 * 60))
        try s.pause(now: evening.addingTimeInterval(31 * 60))
        #expect(try state(s, at: evening.addingTimeInterval(32 * 60)).reason == "Paused focus session")
        try s.stop(now: evening.addingTimeInterval(33 * 60))

        try s.addFocusHours(FocusHours(days: "mon", time: "10:00-13:00"), now: monday)
        try focus(s, at: monday)
        #expect(try state(s, at: monday.addingTimeInterval(60)).reason == "Focus hours")
    }

    @Test func chromeLinkNamesEachSetupStateHonestly() throws {
        let launcher = "/Applications/Three.app/Contents/Helpers/three-native-host"
        let now = monday
        func link(_ manifest: ChromeSetup.ManifestStatus, _ browsers: [BrowserConnection] = [], running: Bool = true) -> ChromeLink {
            ChromeLink(manifest: manifest, launcher: launcher, browsers: browsers, chromeRunning: running, now: now)
        }
        let s = try store()
        func profile(_ id: String, version: String = ChromeExtension.version, access: Bool = true, seen: Date = now) throws -> BrowserConnection {
            try s.recordBrowserHello(clientId: id, extensionVersion: version, hostAccess: access, now: seen)
            return try s.blockStatus(now: now, calendar: utc).browsers.first { $0.id == id }!
        }
        let ours = ChromeSetup.ManifestStatus.installed(path: launcher)

        #expect(link(.missing) == ChromeLink(manifest: .missing, launcher: launcher, browsers: [], chromeRunning: false, now: now))
        #expect(link(.missing).value == "Not set up" && link(.missing).action == .setUp)
        #expect(link(.foreign).action == .none)
        #expect(link(.installed(path: "/elsewhere/three-native-host")).value == "Set up for another copy of Three")
        #expect(link(ours).value == "Waiting for the extension")

        let stale = try profile("stale", seen: now.addingTimeInterval(-600))
        #expect(link(ours, [stale], running: false).value == "Chrome isn't open")
        #expect(link(ours, [stale], running: true).value == "Not connected")
        #expect(link(ours, [try profile("old", version: "0.0.1")]).value == "Extension needs an update")
        #expect(link(ours, [try profile("closed", access: false)]).value == "Needs access to all sites")

        let good = try profile("good")
        let connected = link(ours, [good, try profile("closed2", access: false)])
        #expect(connected.value == "Connected in 1 profile" && connected.action == .remove && connected.detail != nil)
        #expect(link(.missing, [good]).value == "Connected in 1 profile")
    }
}
