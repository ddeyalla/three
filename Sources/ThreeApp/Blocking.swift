import AppKit
import ThreeCore

/// The blocker as this Mac can enforce it at one instant: the Store's status, read at `now`.
/// Every blocking surface (Settings, the menu bar, Now, the overlay) reads its words from here.
struct BlockingState {
    let status: BlockStatus
    let now: Date
    var failedAppRuleIDs: Set<String> = []

    var policy: BlockPolicy { status.policy }

    /// Live profiles that can act on every site and run this build's extension. Anything less can't redirect a tab.
    var workingProfiles: [BrowserConnection] {
        status.liveBrowsers(at: now).filter { $0.hostAccess && $0.extensionVersion == ChromeExtension.version }
    }

    var blockedSites: [BlockRule] { policy.blocked.filter(\.isSite) }
    var blockedApps: [BlockRule] { policy.blocked.filter { !$0.isSite } }
    var failedApps: [BlockRule] { blockedApps.filter { failedAppRuleIDs.contains($0.id) } }
    private var enforcedApps: [BlockRule] { blockedApps.filter { !failedAppRuleIDs.contains($0.id) } }

    /// Something is really stopped right now: an app (Three hides apps while it runs) or a site in a working profile.
    var isEnforcing: Bool { !enforcedApps.isEmpty || (!blockedSites.isEmpty && !workingProfiles.isEmpty) }

    /// Blocking is on and rules are in force, but nothing on this Mac can enforce them.
    var isDegraded: Bool { policy.isActive && !policy.blocked.isEmpty && !isEnforcing }

    /// What an Unblock for 5 Minutes menu lists: every rule in force, each openable or covered by a broader one, then
    /// the rules already open. Empty while blocking is off or the running task is strict, so those menus offer nothing.
    var unblockOptions: [UnblockOption] {
        guard policy.isActive, !policy.strict else { return [] }
        let blocked = policy.blocked.map { rule in
            policy.coveringRule(for: rule).map { UnblockOption.covered(rule, by: $0) } ?? .available(rule)
        }
        let open = policy.exceptions.compactMap { e in
            status.rules.first { $0.id == e.ruleId }.map { UnblockOption.alreadyOpen($0, until: e.expiresAt) }
        }
        return blocked + open
    }

    /// The rule with this id if it can be opened now. A menu can outlive the state it was drawn from.
    func availableRule(id: String) -> BlockRule? {
        unblockOptions.lazy.compactMap(\.availableRule).first { $0.id == id }
    }

    /// The Settings status value: "Off", "On until 3:45 PM", or that sites aren't being blocked.
    var value: String {
        guard policy.isActive else { return "Off" }
        if isDegraded {
            if failedApps.isEmpty { return "On, websites not blocked" }
            return blockedSites.isEmpty ? "On, apps not hidden" : "On, nothing blocked"
        }
        return policy.until.map { "On until \(Format.until($0, now: now))" } ?? "On"
    }

    /// The menu-bar popover's line while blocking is on.
    var headline: String {
        if isDegraded {
            if failedApps.isEmpty { return "Websites aren't blocked" }
            return blockedSites.isEmpty ? "Apps couldn't be hidden" : "Nothing is blocked"
        }
        return policy.until.map { "Blocking until \(Format.until($0, now: now))" } ?? "Blocking"
    }

    /// One sentence under the value: why it's on, what it covers and any open exceptions; or what turns it on.
    var detail: String {
        guard policy.isActive else {
            guard status.rules.contains(where: \.enabled) else { return "Add a website or app to block during focus." }
            // While off, the only change the clock can bring is the next focus hours.
            guard let next = policy.nextChange else { return "Turns on when you start a focus session." }
            return "Turns on with your next focus session, or \(Format.until(next, now: now))."
        }
        if isDegraded {
            var parts: [String] = []
            if !blockedSites.isEmpty { parts.append(chromeProblem) }
            if let appProblem { parts.append(appProblem) }
            return (parts + [reason]).joined(separator: " · ")
        }
        var parts = [reason]
        if let coverage { parts.append(coverage) }
        if policy.strict { parts.append("Unblocking off for this task") }
        for e in policy.exceptions {
            guard let rule = status.rules.first(where: { $0.id == e.ruleId }) else { continue }
            parts.append("\(rule.name) open until \(Format.time(e.expiresAt))")
        }
        return parts.joined(separator: " · ")
    }

    /// The focus session, when it is what keeps blocking on longest. Otherwise focus hours do.
    var owningFocus: FocusCover? {
        guard let focus = policy.focus, (policy.focusHours?.end).map({ $0 < focus.until }) ?? true else { return nil }
        return focus
    }

    /// Why blocking is on, named for whichever reason keeps it on longest.
    var reason: String {
        guard let focus = owningFocus else { return "Focus hours" }
        return switch focus.phase {
        case .running: "This focus session"
        case .paused: "Paused focus session"
        case .overrun: "Focus session past its end"
        }
    }

    /// What really enforces the rules in force, from live facts only. Chrome can't say how many profiles exist,
    /// so this counts connected ones and never claims all of them.
    var coverage: String? {
        let sites = !blockedSites.isEmpty, apps = !enforcedApps.isEmpty
        let profiles = workingProfiles.count
        let chrome = "Chrome (\(profiles) profile\(profiles == 1 ? "" : "s"))"
        let covered: String? = switch (sites, apps) {
        case (true, true): profiles > 0 ? "\(chrome) and apps" : "Apps only. Websites aren't blocked."
        case (true, false): profiles > 0 ? chrome : nil
        case (false, true): "Apps only"
        case (false, false): nil
        }
        let parts = [covered, appProblem].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var appProblem: String? {
        guard !failedApps.isEmpty else { return nil }
        return "\(failedApps.map(\.name).joined(separator: ", ")) couldn't be hidden"
    }

    /// Why no profile can block sites.
    var chromeProblem: String {
        let live = status.liveBrowsers(at: now)
        if live.isEmpty { return "Chrome isn't connected, so websites aren't blocked" }
        if live.contains(where: { $0.extensionVersion != ChromeExtension.version }) {
            return "The Chrome extension needs an update, so websites aren't blocked"
        }
        return "Chrome hasn't let the extension act on all sites, so websites aren't blocked"
    }

    /// For the menu-bar glyph and Now: "Blocking until 3:45 PM".
    var accessibilityLabel: String { headline }
}

/// One rule in an Unblock for 5 Minutes menu, and whether it can be opened now.
enum UnblockOption: Hashable, Identifiable {
    case available(BlockRule)
    /// A broader rule also blocks this site, so opening it alone wouldn't help.
    case covered(BlockRule, by: BlockRule)
    case alreadyOpen(BlockRule, until: Date)

    var availableRule: BlockRule? {
        guard case .available(let rule) = self else { return nil }
        return rule
    }

    var id: String {
        switch self {
        case .available(let rule), .covered(let rule, _): rule.id
        case .alreadyOpen(let rule, _): "open-\(rule.id)"
        }
    }
}

extension BlockRule {
    var isSite: Bool {
        if case .domain = target { return true }
        return false
    }

    var domain: BlockDomain? {
        if case .domain(let d) = target { return d }
        return nil
    }

    var bundleID: AppBundleID? {
        if case .app(let id) = target { return id }
        return nil
    }

    /// The domain, or the app's name when it's installed.
    var name: String {
        switch target {
        case .domain(let d): d.rawValue
        case .app(let id): InstalledApp(id)?.name ?? id.rawValue
        }
    }
}

/// An app on this Mac, found by bundle identifier through Launch Services.
struct InstalledApp {
    let url: URL

    init?(_ id: AppBundleID) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id.rawValue) else { return nil }
        self.url = url
    }

    var name: String { FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Chrome's connection as Settings shows it, from the manifest file, the profiles heard from and whether Chrome runs.
struct ChromeLink: Equatable {
    enum Action: Equatable { case setUp, remove, none }

    let value: String
    let detail: String?
    let action: Action

    init(manifest: ChromeSetup.ManifestStatus, launcher: String, browsers: [BrowserConnection], chromeRunning: Bool, now: Date) {
        let live = browsers.filter { $0.isLive(at: now) }
        let working = live.filter { $0.hostAccess && $0.extensionVersion == ChromeExtension.version }
        let profiles = { (n: Int) in "\(n) profile\(n == 1 ? "" : "s")" }
        if manifest == .foreign {
            self.init("Can't connect", "Another app's file is where Chrome looks for Three's connection.", .none)
        } else if !working.isEmpty {
            let broken = live.count - working.count
            self.init("Connected in \(profiles(working.count))",
                      broken > 0 ? "\(profiles(broken)) can't block yet. Check the extension in chrome://extensions." : nil,
                      .remove)
        } else if !live.isEmpty {
            if live.contains(where: { $0.extensionVersion != ChromeExtension.version }) {
                self.init("Extension needs an update",
                          "Open chrome://extensions and click the reload button on Three Focus Blocker.", .setUp)
            } else {
                self.init("Needs access to all sites",
                          "In chrome://extensions, open Three Focus Blocker's details and set Site access to On all sites.", .setUp)
            }
        } else if manifest == .missing {
            self.init("Not set up", nil, .setUp)
        } else if case .installed(let path) = manifest, path != launcher {
            self.init("Set up for another copy of Three", "Set it up again so Chrome starts this copy.", .setUp)
        } else if browsers.isEmpty {
            self.init("Waiting for the extension", "Load the extension in Chrome to finish setting up.", .setUp)
        } else if !chromeRunning {
            self.init("Chrome isn't open", nil, .remove)
        } else {
            self.init("Not connected", "Check that Three Focus Blocker is turned on in chrome://extensions.", .setUp)
        }
    }

    private init(_ value: String, _ detail: String?, _ action: Action) {
        self.value = value
        self.detail = detail
        self.action = action
    }
}

/// Focus-hours windows that share a start and end, shown and edited as one row. Stored one per weekday.
struct FocusHoursGroup: Identifiable, Equatable {
    let ids: [String]
    let days: [Weekday]
    let start: ClockTime
    let end: ClockTime

    var id: String { ids.joined(separator: ",") }
    var isOvernight: Bool { end.minutes == 1440 || end <= start }

    static func groups(_ windows: [FocusWindow]) -> [FocusHoursGroup] {
        var order: [String] = []
        var found: [String: [FocusWindow]] = [:]
        for w in windows {
            let key = "\(w.start.minutes)-\(w.end.minutes)"
            if found[key] == nil { order.append(key) }
            found[key, default: []].append(w)
        }
        return order.map { key in
            let ws = found[key]!.sorted { $0.weekday < $1.weekday }
            return FocusHoursGroup(ids: ws.map(\.id), days: ws.map(\.weekday), start: ws[0].start, end: ws[0].end)
        }
    }

    /// "Mon–Fri", "Weekends", "Every day" or "Mon, Wed, Fri", in the Mac's language.
    static func dayLabel(_ days: [Weekday]) -> String {
        let sorted = Array(Set(days)).sorted()
        if sorted.count == 7 { return "Every day" }
        if sorted == [.saturday, .sunday] { return "Weekends" }
        if sorted.count >= 3, sorted.last!.rawValue - sorted.first!.rawValue == sorted.count - 1 {
            return "\(sorted.first!.short)–\(sorted.last!.short)"
        }
        return sorted.map(\.short).joined(separator: ", ")
    }

    /// "10:00 AM – 1:00 PM", with "(next day)" when it runs past midnight.
    var timeLabel: String {
        "\(start.formatted) – \(end.formatted)\(isOvernight ? " (next day)" : "")"
    }
}

extension Weekday {
    /// `Calendar` counts from Sunday at index 0; ISO weekdays put Monday first.
    private var symbolIndex: Int { rawValue % 7 }
    var short: String { Calendar.current.shortWeekdaySymbols[symbolIndex] }
    var veryShort: String { Calendar.current.veryShortWeekdaySymbols[symbolIndex] }
    var full: String { Calendar.current.weekdaySymbols[symbolIndex] }

    /// The week as the Mac's calendar starts it.
    static var localOrder: [Weekday] {
        let first = Weekday(rawValue: (Calendar.current.firstWeekday + 5) % 7 + 1) ?? .monday
        return (0..<7).map { Weekday(rawValue: (first.rawValue - 1 + $0) % 7 + 1)! }
    }
}

extension ClockTime {
    /// The wall-clock time in the Mac's format, such as "10:00 AM".
    var formatted: String {
        let midnight = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(bySettingHour: minutes / 60 % 24, minute: minutes % 60, second: 0, of: midnight) ?? midnight
        return Format.time(date)
    }

    init(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        self = ClockTime(minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))!
    }

    static func windowEnd(_ date: Date) -> ClockTime {
        let time = ClockTime(date)
        return time.minutes == 0 ? ClockTime(minutes: 1440)! : time
    }

    /// Today at this time, for a time picker.
    var date: Date {
        Calendar.current.date(bySettingHour: minutes / 60 % 24, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
}

extension ChromeSetup {
    /// This copy of Three's own helper and extension, and Chrome's data folder. THREE_CHROME_DATA points that folder
    /// elsewhere, so QA and tests never touch a real Chrome profile.
    static var forThisApp: ChromeSetup {
        let app = Bundle.main.bundleURL
        let chrome = ProcessInfo.processInfo.environment["THREE_CHROME_DATA"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome")
        return ChromeSetup(launcher: app.appendingPathComponent("Contents/Helpers/three-native-host"),
                           bundledExtension: app.appendingPathComponent("Contents/Resources/ChromeExtension"),
                           extensionFolder: Store.defaultURL.deletingLastPathComponent().appendingPathComponent("ChromeExtension"),
                           browserDataFolder: chrome)
    }

    /// True when Chrome would start this copy's helper and the folder Chrome loads holds this build's extension.
    var isCurrent: Bool {
        guard manifestStatus() == .installed(path: launcher.path),
              let data = try? Data(contentsOf: extensionFolder.appendingPathComponent("manifest.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["version"] as? String == ChromeExtension.version
    }
}
