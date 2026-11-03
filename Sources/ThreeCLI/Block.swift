import AppKit
import ArgumentParser
import Foundation
import ThreeCore

// `three block`: the agent-facing blocker. It only tightens. Removing rules, shortening hours and unblocking
// belong to the person, in the app, and Store refuses the loosening ones while blocking is on anyway.

struct Block: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Block distracting sites and apps during focus sessions and focus hours.",
        discussion: "This command only adds. Remove rules or change focus hours in the Three app, while blocking is off.",
        subcommands: [BlockStatusCommand.self, BlockAdd.self, BlockHours.self, ConnectChrome.self],
        defaultSubcommand: BlockStatusCommand.self
    )
}

private let uncovered = [
    "Safari and other browsers (add one under --app to hide it during focus)",
    "Chrome profiles without the Three extension",
    "Chrome Incognito and Guest windows",
    "videos embedded in other sites, and apps that show web pages",
    "apps while Three is closed (chosen apps are hidden, never quit, while Three runs)",
]

struct BlockStatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Whether blocking is on, why, and until when.")
    @OptionGroup var common: Common

    func run() throws {
        let status = try store().blockStatus()
        common.json ? try emit(BlockStatusJSON(status, now: Date())) : printBlockStatus(status)
    }
}

struct BlockAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Block sites or apps. Presets: x, reddit, youtube.",
        discussion: """
        three block add reddit news.ycombinator.com com.tinyspeck.slackmacgap /Applications/Music.app
        Each name is an app when it's a .app path, an installed app's bundle identifier, or reverse-DNS such as \
        com.apple.Music (three or more parts, starting with com, org, net, io, edu, gov, app, dev, co or me, \
        with a capital letter after the first part or a last part that isn't a web ending such as .com or .tv). \
        Anything else is a site, so app.zoom.us stays a site.
        Use --app or --site when Three guesses wrong. Bundle identifiers that start with anything else, such as \
        us.zoom.xos, or that are all lowercase and end in a web ending, such as com.apple.news, need --app unless \
        the app is installed.
        A site covers its subdomains. Paths such as youtube.com/shorts aren't supported.
        """
    )
    @Argument(help: "x, reddit, youtube, a site such as example.com, or an app such as com.apple.Music.") var names: [String] = []
    @Option(name: .customLong("app"), help: "Always an app: a bundle identifier or .app path. Repeat for more.") var apps: [String] = []
    @Option(name: .customLong("site"), help: "Always a site, even if it looks like a bundle identifier. Repeat for more.") var sites: [String] = []

    func run() throws {
        guard !names.isEmpty || !apps.isEmpty || !sites.isEmpty else {
            throw ValidationError("Name a site, an app, or a preset (x, reddit, youtube).")
        }
        let targets = try names.flatMap { name -> [BlockTarget] in
            if let preset = BlockPreset(rawValue: name.lowercased()) { return preset.domains.map(BlockTarget.domain) }
            return [try BlockTarget(classifying: name, isInstalledApp: isInstalledApp)]
        } + sites.map { .domain(try BlockDomain(parsing: $0)) } + apps.map(BlockTarget.init(app:))
        let s = try store()
        let rules = try s.addBlockRules(targets)
        for (target, rule) in zip(targets, rules) {
            if rule.target != target {
                print("\(target.value) is already covered by \(rule.target.value).")
            } else if case .app = target {
                print("Blocked app \(target.value)")
            } else {
                print("Blocked site \(target.value)")
            }
        }
        printBlockStatus(try s.blockStatus())
    }
}

/// LaunchServices knows every app on this Mac by bundle identifier, ignoring case.
func isInstalledApp(_ bundleID: String) -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
}

struct BlockHours: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hours",
        abstract: "Weekly focus hours. Blocking stays on between sessions and during breaks inside them.",
        subcommands: [List.self, Add.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        @OptionGroup var common: Common
        func run() throws {
            let windows = try store().blockStatus().windows
            if common.json { return try emit(windows.map(HoursJSON.init)) }
            if windows.isEmpty { return print("No focus hours. Add some: three block hours add mon-fri 10:00-13:00") }
            for line in hoursLines(windows) { print(line) }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add focus hours on some days.",
            discussion: "three block hours add mon-fri 10:00-13:00  ·  three block hours add fri 22:00-02:00 (ends Saturday at 2:00)\nTimes follow this Mac's time zone."
        )
        @Argument(help: "mon-fri, sat,sun, weekdays, weekends or daily.") var days: String
        @Argument(help: "A time range such as 10:00-13:00. An end before the start runs past midnight.") var time: String

        func run() throws {
            let s = try store()
            try s.addFocusHours(FocusHours(days: days, time: time))
            for line in hoursLines(try s.blockStatus().windows) { print(line) }
        }
    }
}

struct ConnectChrome: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect-chrome",
        abstract: "Let the Three extension in Chrome ask this Mac what to block.",
        discussion: "Writes one file, Chrome's native-messaging manifest for com.deyalla.three, and copies the extension next to Three's database. Other files in Chrome's folder are never touched."
    )
    @Option(help: "Chrome's user data folder.")
    var chromeFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Google/Chrome").path

    func run() throws {
        // The real executable, not argv[0]: run through PATH, argv[0] is just "three".
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            throw ValidationError("Can't tell where this three lives.")
        }
        let helpers = executable.deletingLastPathComponent()
        let contents = helpers.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents", app.pathExtension == "app" else {
            throw ValidationError("Run this from the app so Chrome gets a path that lasts: ~/Applications/Three.app/Contents/Helpers/three block connect-chrome")
        }
        let setup = ChromeSetup(launcher: helpers.appendingPathComponent("three-native-host"),
                                bundledExtension: contents.appendingPathComponent("Resources/ChromeExtension"),
                                extensionFolder: Store.defaultURL.deletingLastPathComponent().appendingPathComponent("ChromeExtension"),
                                browserDataFolder: URL(fileURLWithPath: chromeFolder))
        try setup.install()
        print("Wrote \(setup.manifestURL.path)")
        if !["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
            .contains(app.deletingLastPathComponent().path) {
            print("Chrome will start Three from \(app.path). Run this again if you move or rebuild the app.")
        }
        print("""

        Now, in each Chrome profile you use for work:
          1. Open chrome://extensions and turn on Developer mode.
          2. Click Load unpacked and choose \(setup.extensionFolder.path)
        Check it worked with: three block status
        Incognito and Guest windows aren't covered.
        """)
    }
}

// MARK: Output

func hoursLines(_ windows: [FocusWindow]) -> [String] {
    var groups: [(start: ClockTime, end: ClockTime, days: [Weekday])] = []
    for w in windows {
        if let i = groups.firstIndex(where: { $0.start == w.start && $0.end == w.end }) {
            groups[i].days.append(w.weekday)
        } else {
            groups.append((w.start, w.end, [w.weekday]))
        }
    }
    return groups.map { g in
        "\(dayLabel(g.days)) \(g.start)-\(g.end)\(g.end <= g.start ? " (ends the next day)" : "")"
    }
}

/// "Mon-Fri" for a run of three or more days, else "Mon, Wed".
func dayLabel(_ days: [Weekday]) -> String {
    let sorted = days.sorted()
    if sorted.count == 7 { return "Every day" }
    let name = { (d: Weekday) in d.shortName.prefix(1).uppercased() + d.shortName.dropFirst() }
    if sorted.count >= 3, sorted.last!.rawValue - sorted.first!.rawValue == sorted.count - 1 {
        return "\(name(sorted.first!))-\(name(sorted.last!))"
    }
    return sorted.map(name).joined(separator: ", ")
}

func printBlockStatus(_ status: BlockStatus) {
    let p = status.policy, now = Date()
    let time = { (d: Date) in d.formatted(date: Calendar.current.isDate(d, inSameDayAs: now) ? .omitted : .abbreviated, time: .shortened) }
    if p.isActive, let until = p.until {
        let why = switch BrowserState(p).reason {
        case .focus?: "focus on \"\(p.focus?.taskTitle ?? "this task")\""
        case .paused?: "paused focus"
        case .overrun?: "focus past its planned end"
        default: "focus hours"
        }
        let hours = p.focus != nil && p.focusHours != nil ? " and focus hours" : ""
        print("Blocking until \(time(until)) · \(why)\(hours)\(p.strict ? " · strict" : "")")
    } else if !status.rules.contains(where: \.enabled) {
        print("Blocking off · no rules yet. Add some: three block add reddit")
    } else {
        print("Blocking off\(p.nextChange.map { " · focus hours start \($0.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" } ?? "")")
    }
    let sites = status.rules.filter { if case .domain = $0.target { true } else { false } }
    let apps = status.rules.filter { if case .app = $0.target { true } else { false } }
    func list(_ rules: [BlockRule]) -> String {
        rules.map { r in
            var s = r.target.value
            if let n = status.hitsToday[r.id] { s += " (\(n) today)" }
            if !r.enabled { s += " (off)" }
            if let e = p.exceptions.first(where: { $0.ruleId == r.id }) { s += " (open until \(time(e.expiresAt)))" }
            return s
        }.joined(separator: ", ")
    }
    if !sites.isEmpty { print("Sites   \(list(sites))") }
    if !apps.isEmpty { print("Apps    \(list(apps))") }
    if !status.windows.isEmpty { print("Hours   \(hoursLines(status.windows).joined(separator: " · "))") }
    let live = status.liveBrowsers(at: now)
    if live.isEmpty {
        print("Chrome  not connected. Set it up: three block connect-chrome")
    } else {
        let versions = Set(live.map(\.extensionVersion)).sorted().joined(separator: ", ")
        var line = "Chrome  \(live.count) profile\(live.count == 1 ? "" : "s") connected (extension \(versions))"
        if live.contains(where: { $0.extensionVersion != ChromeExtension.version }) { line += ". Reload the extension in chrome://extensions" }
        if live.contains(where: { !$0.hostAccess }) { line += ". A profile hasn't allowed the extension on all sites" }
        print(line)
    }
    print("Not covered: \(uncovered.joined(separator: "; ")).")
}

struct HoursJSON: Encodable {
    let id: String, weekday: String, start: String, end: String
    init(_ w: FocusWindow) { id = w.id; weekday = w.weekday.shortName; start = w.start.description; end = w.end.description }
}

struct BlockStatusJSON: Encodable {
    struct Focus: Encodable {
        let sessionId: String, task: String?, strict: Bool, phase: String, plannedEnd: Date, expiresAt: Date
    }
    struct Span: Encodable { let start: Date, end: Date }
    struct Rule: Encodable {
        let id: String, kind: String, value: String, label: String, enabled: Bool, blocking: Bool, hitsToday: Int
    }
    struct Exception: Encodable { let ruleId: String, expiresAt: Date }
    struct Profile: Encodable { let extensionVersion: String, hostAccess: Bool, lastSeen: Date }
    struct Chrome: Encodable { let connectedProfiles: Int, expectedVersion: String, profiles: [Profile] }

    let active: Bool, reason: String?, until: Date?, nextChange: Date?, strict: Bool
    let focus: Focus?, focusHours: Span?
    let rules: [Rule], exceptions: [Exception], hours: [HoursJSON], chrome: Chrome, notCovered: [String]

    init(_ status: BlockStatus, now: Date) {
        let p = status.policy
        active = p.isActive
        reason = BrowserState(p).reason?.rawValue
        until = p.until
        nextChange = p.nextChange
        strict = p.strict
        focus = p.focus.map {
            Focus(sessionId: $0.sessionId, task: $0.taskTitle, strict: $0.strict, phase: $0.phase.rawValue,
                  plannedEnd: $0.plannedEnd, expiresAt: $0.expiresAt)
        }
        focusHours = p.focusHours.map { Span(start: $0.start, end: $0.end) }
        rules = status.rules.map { r in
            let label = if case .domain(let d) = r.target { d.label } else { r.target.value }
            return Rule(id: r.id, kind: r.target.kind, value: r.target.value, label: label, enabled: r.enabled,
                        blocking: p.blocked.contains { $0.id == r.id }, hitsToday: status.hitsToday[r.id] ?? 0)
        }
        exceptions = p.exceptions.map { Exception(ruleId: $0.ruleId, expiresAt: $0.expiresAt) }
        hours = status.windows.map(HoursJSON.init)
        let live = status.liveBrowsers(at: now)
        chrome = Chrome(connectedProfiles: live.count, expectedVersion: ChromeExtension.version,
                        profiles: live.map { Profile(extensionVersion: $0.extensionVersion, hostAccess: $0.hostAccess, lastSeen: $0.seenAt) })
        notCovered = uncovered
    }
}
