import AppKit
import SwiftUI
import ThreeCore
import UniformTypeIdentifiers

/// Settings → Blocking: what's blocked, when, and how Chrome is connected. Adding is always allowed; removing waits
/// until blocking is off, and the Store refuses it anyway if blocking starts between showing and clicking.
struct BlockingSettings: View {
    @Environment(AppModel.self) private var model
    @State private var site = ""
    @State private var siteNote: SiteNote?
    @State private var appNote: String?
    @State private var hoursNote: String?
    @State private var chromeNote: String?
    @State private var editing: HoursEditor?
    @State private var settingUpChrome = false
    @State private var confirmingRemoval = false
    @FocusState private var siteFocused: Bool

    private struct SiteNote: Equatable {
        var message: String
        var suggestion: BlockDomain?
        var isProblem = true
    }

    private var state: BlockingState { model.blocking }
    private var locked: Bool { state.policy.isActive }
    /// "You can remove this after 1:00 PM." while blocking is on, else nil.
    private var lockHelp: String? {
        guard locked else { return nil }
        return state.policy.until.map { "You can remove this after \(Format.until($0, now: state.now))." } ?? "You can remove this once blocking ends."
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Blocking") {
                    Text(state.value).monospacedDigit()
                }
                Text(state.detail)
                    .font(Typo.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            websites
            apps
            hours
            chrome
            Section("Not covered") {
                Text("Safari, Firefox and other browsers, Chrome profiles without the extension, Guest and Incognito windows, videos embedded in other sites, and apps that show web pages. To keep Safari closed during focus, add it under Apps.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { FocusHoursSheet(editor: $0) }
        .sheet(isPresented: $settingUpChrome) { ChromeSetupSheet() }
        .onAppear(perform: claimChromeSetup)
        .onChange(of: model.chromeSetupRequested) { claimChromeSetup() }
    }

    private func claimChromeSetup() {
        guard model.chromeSetupRequested else { return }
        model.chromeSetupRequested = false
        settingUpChrome = true
    }

    private var lockFooter: Text? {
        guard locked, let until = state.policy.until else { return nil }
        return Text("You can add rules now. Removing them waits until blocking ends at \(Format.until(until, now: state.now)).")
    }

    // MARK: Websites

    private var siteRules: [BlockRule] { state.status.rules.filter(\.isSite) }

    private var websites: some View {
        Section {
            ForEach(siteRules) { rule in
                RuleRow(rule: rule, detail: siteDetail(rule), locked: locked, lockHelp: lockHelp) {
                    siteNote = remove(rule).map { SiteNote(message: $0) }
                }
            }
            let suggested = BlockPreset.allCases.filter { preset in
                !preset.domains.allSatisfy { d in siteRules.contains { $0.enabled && $0.domain?.covers(d) == true } }
            }
            if !suggested.isEmpty {
                LabeledContent("Suggested") {
                    HStack(spacing: Space.sm) {
                        ForEach(suggested, id: \.self) { preset in
                            Button(preset.name) { addPreset(preset) }
                                .help("Adds \(preset.domains.map(\.rawValue).joined(separator: " and "))")
                        }
                    }
                }
            }
            LabeledContent("Add a website") {
                HStack(spacing: Space.sm) {
                    TextField("Website", text: $site, prompt: Text("example.com"))
                        .labelsHidden()
                        .autocorrectionDisabled()
                        .focused($siteFocused)
                        .onSubmit { addSite(site) }
                        .onChange(of: site) { siteNote = nil }
                    Button("Add") { addSite(site) }
                        .disabled(site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let note = siteNote {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    if note.isProblem { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.overrun) }
                    Text(note.message).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.xs)
                    if let suggestion = note.suggestion {
                        Button("Block \(suggestion.rawValue)") { add(suggestion) }
                    }
                }
            }
        } header: {
            Text("Websites")
        } footer: {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("A website includes its subdomains, so youtube.com also covers music.youtube.com. Blocked in Chrome profiles with the Three extension, even while Three is closed.")
                lockFooter
            }
            .foregroundStyle(.secondary)
        }
    }

    private func siteDetail(_ rule: BlockRule) -> String? {
        guard case .domain(let d) = rule.target else { return nil }
        if !rule.enabled { return "Off" }
        return d.label == d.rawValue ? nil : d.label
    }

    private func addPreset(_ preset: BlockPreset) {
        do {
            try model.store.addBlockPreset(preset)
            siteNote = nil
        } catch {
            siteNote = SiteNote(message: error.localizedDescription)
        }
        model.refreshBlocking()
    }

    private func addSite(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            add(try BlockDomain(parsing: text))
        } catch BlockError.invalidDomain(.pathRule(let suggestion)) {
            siteNote = SiteNote(message: "Blocking part of a site comes later.", suggestion: suggestion)
        } catch {
            siteNote = SiteNote(message: error.localizedDescription)
        }
    }

    /// The Store hands back the rule that now covers the site, so a rule that existed before is a duplicate.
    private func add(_ domain: BlockDomain) {
        do {
            let before = Set(try model.store.blockStatus().rules.filter(\.enabled).map(\.id))
            let rule = try model.store.addBlockRule(.domain(domain))
            if before.contains(rule.id) {
                siteNote = SiteNote(message: rule.target == .domain(domain)
                                    ? "\(domain) is already on your list."
                                    : "\(domain) is already covered by \(rule.target.value).", isProblem: false)
            } else {
                site = ""
                siteNote = nil
                siteFocused = true
            }
        } catch {
            siteNote = SiteNote(message: error.localizedDescription)
        }
        model.refreshBlocking()
    }

    // MARK: Apps

    private var appRules: [BlockRule] { state.status.rules.filter { !$0.isSite } }

    private var apps: some View {
        Section {
            ForEach(appRules) { rule in
                RuleRow(rule: rule, detail: appDetail(rule), locked: locked, lockHelp: lockHelp) { appNote = remove(rule) }
            }
            Button("Choose App…", action: chooseApps)
            if let appNote {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.overrun)
                    Text(appNote).fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Apps")
        } footer: {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Blocked apps are hidden, never quit, so nothing in them is lost. Hiding works only while Three is open.")
                lockFooter
            }
            .foregroundStyle(.secondary)
        }
    }

    private func appDetail(_ rule: BlockRule) -> String? {
        guard let id = rule.bundleID else { return nil }
        if !rule.enabled { return "Off" }
        if InstalledApp(id) == nil { return "Not installed" }
        if id.rawValue.lowercased().hasPrefix("com.google.chrome") { return "Hides all of Chrome during focus, including Three's block page" }
        return nil
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Block"
        panel.message = "Choose apps to hide during focus."
        guard panel.runModal() == .OK else { return }
        var notes: [String] = []
        let before = Set((try? model.store.blockStatus().rules.filter(\.enabled).map(\.id)) ?? [])
        for url in panel.urls {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            guard let id = Bundle(url: url)?.bundleIdentifier else {
                notes.append("\(name) can't be blocked.")
                continue
            }
            guard id != Bundle.main.bundleIdentifier else {
                notes.append("Three can't block itself.")
                continue
            }
            do {
                let rule = try model.store.addBlockRule(.app(AppBundleID(parsing: id)))
                if before.contains(rule.id) { notes.append("\(name) is already on your list.") }
            } catch BlockError.protectedApp {
                notes.append(id.lowercased().hasPrefix("com.deyalla.three") ? "Three can't block itself." : "Three can't block \(name). Your Mac needs it.")
            } catch {
                notes.append(error.localizedDescription)
            }
        }
        appNote = notes.isEmpty ? nil : notes.joined(separator: " ")
        model.refreshBlocking()
    }

    // MARK: Removing

    /// The Store's refusal, if blocking started since the button was drawn.
    private func remove(_ rule: BlockRule) -> String? {
        defer { model.refreshBlocking() }
        do {
            try model.store.removeBlockRule(rule.id)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Focus hours

    private var hours: some View {
        Section {
            ForEach(FocusHoursGroup.groups(state.status.windows)) { group in
                HStack(spacing: Space.sm) {
                    Button { editing = HoursEditor(group: group) } label: {
                        HStack {
                            Text(FocusHoursGroup.dayLabel(group.days))
                            Spacer(minLength: Space.sm)
                            Text(group.timeLabel)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(locked)
                    .help(lockHelp ?? "Edit these hours")
                    RemoveButton(name: FocusHoursGroup.dayLabel(group.days), locked: locked, lockHelp: lockHelp) {
                        do {
                            try model.store.removeFocusWindows(group.ids)
                            hoursNote = nil
                        } catch {
                            hoursNote = error.localizedDescription
                        }
                        model.refreshBlocking()
                    }
                }
            }
            Button("Add Focus Hours…") { editing = HoursEditor(group: nil) }
            if let hoursNote {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.overrun)
                    Text(hoursNote).fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Focus hours")
        } footer: {
            Text("Blocking also stays on between sessions and during breaks inside these hours. Times follow your Mac's time zone.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        let setup = ChromeSetup.forThisApp
        let link = ChromeLink(manifest: setup.manifestStatus(), launcher: setup.launcher.path, browsers: state.status.browsers,
                              chromeRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty,
                              now: state.now)
        return Section {
            LabeledContent("Connection") {
                HStack(spacing: Space.sm) {
                    Text(link.value).foregroundStyle(.secondary)
                    switch link.action {
                    case .setUp: Button("Set Up Chrome…") { settingUpChrome = true }
                    case .remove:
                        Button("Remove Connection…") { confirmingRemoval = true }
                            .disabled(locked)
                            .help(lockHelp ?? "Stop Chrome from asking Three what to block")
                    case .none: EmptyView()
                    }
                }
            }
            if let detail = link.detail {
                Text(detail)
                    .font(Typo.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let chromeNote {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.overrun)
                    Text(chromeNote).fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Chrome")
        } footer: {
            Text("The extension checks addresses on your Mac. Three saves only which rule matched and when, never the address.")
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Remove the Chrome connection?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) { removeConnection(setup) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Chrome will stop blocking sites until you set it up again.")
        }
    }

    /// ChromeSetup has no blocking check of its own, so ask the Store at the moment of removal.
    private func removeConnection(_ setup: ChromeSetup) {
        do {
            let policy = try model.store.blockPolicy()
            guard !policy.isActive else { throw BlockError.protectionActive(until: policy.until) }
            try setup.removeConnection()
            chromeNote = nil
        } catch {
            chromeNote = error.localizedDescription
        }
        model.refreshBlocking()
    }
}

private struct RuleRow: View {
    let rule: BlockRule
    let detail: String?
    let locked: Bool
    let lockHelp: String?
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            icon
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: Space.hairline) {
                Text(rule.name)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(Typo.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .help(rule.bundleID?.rawValue ?? "")
            Spacer(minLength: Space.sm)
            RemoveButton(name: rule.name, locked: locked, lockHelp: lockHelp, action: remove)
        }
    }

    @ViewBuilder private var icon: some View {
        if let id = rule.bundleID {
            if let app = InstalledApp(id) {
                Image(nsImage: app.icon).resizable().scaledToFit()
            } else {
                Image(systemName: "app.dashed").foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: "globe").foregroundStyle(.secondary)
        }
    }
}

private struct RemoveButton: View {
    let name: String
    let locked: Bool
    let lockHelp: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .disabled(locked)
        .help(lockHelp ?? "Remove \(name)")
        .accessibilityLabel("Remove \(name)")
    }
}

// MARK: Focus hours sheet

struct HoursEditor: Identifiable {
    let id = UUID()
    /// nil adds new hours.
    let group: FocusHoursGroup?
}

private struct FocusHoursSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let editor: HoursEditor
    @State private var days: Set<Weekday>
    @State private var from: Date
    @State private var to: Date
    @State private var error: String?

    init(editor: HoursEditor) {
        self.editor = editor
        let g = editor.group
        _days = State(initialValue: Set(g?.days ?? [.monday, .tuesday, .wednesday, .thursday, .friday]))
        _from = State(initialValue: (g?.start ?? ClockTime(minutes: 600)!).date)
        _to = State(initialValue: (g?.end ?? ClockTime(minutes: 780)!).date)
    }

    private var start: ClockTime { ClockTime(from) }
    private var end: ClockTime { ClockTime(to) }

    /// What stops Add, said where the person looks, never as a red error.
    private var problem: String? {
        if days.isEmpty { return "Pick at least one day." }
        if start == end { return "Start and end need to be different." }
        let others = model.blocking.status.windows.filter { !(editor.group?.ids.contains($0.id) ?? false) }
        if days.allSatisfy({ d in others.contains { $0.weekday == d && $0.start == start && $0.end == end } }) {
            return "These hours are already set."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(editor.group == nil ? "Add focus hours" : "Edit focus hours")
                .font(Typo.heading)
            Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.md) {
                GridRow {
                    Text("Days").foregroundStyle(.secondary)
                    HStack(spacing: Space.xs) {
                        ForEach(Weekday.localOrder, id: \.self) { day in
                            Toggle(day.veryShort, isOn: Binding(
                                get: { days.contains(day) },
                                set: { on in if on { days.insert(day) } else { days.remove(day) } }))
                                .toggleStyle(.button)
                                .accessibilityLabel(day.full)
                        }
                    }
                }
                GridRow {
                    Text("From").foregroundStyle(.secondary)
                    DatePicker("From", selection: $from, displayedComponents: .hourAndMinute).labelsHidden()
                }
                GridRow {
                    Text("To").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        DatePicker("To", selection: $to, displayedComponents: .hourAndMinute).labelsHidden()
                        if end < start {
                            Text("Ends the next day at \(end.formatted)")
                                .font(Typo.meta)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let message = error ?? problem {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    if error != nil { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.overrun) }
                    Text(message)
                        .foregroundStyle(error == nil ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Space.sm) {
                if let group = editor.group {
                    Button("Remove") { attempt { try model.store.removeFocusWindows(group.ids) } }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editor.group == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .font(Typo.body)
        .padding(Space.xl)
        .frame(width: 420)
        .onChange(of: days) { error = nil }
        .onChange(of: from) { error = nil }
        .onChange(of: to) { error = nil }
    }

    private func save() {
        attempt {
            let hours = try FocusHours(days: days, start: start, end: end)
            if let group = editor.group {
                try model.store.replaceFocusWindows(group.ids, with: hours)
            } else {
                try model.store.addFocusHours(hours)
            }
        }
    }

    private func attempt(_ change: () throws -> Void) {
        do {
            try change()
            model.refreshBlocking()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Chrome setup sheet

/// Three steps the person takes in any order. Nothing is written until they click Add Connection.
private struct ChromeSetupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var copied = false
    /// Bumped after a write; reading it in `body` makes the step re-read the files.
    @State private var revision = 0

    var body: some View {
        let setup = ChromeSetup.forThisApp
        let current = revision >= 0 && setup.isCurrent
        let link = ChromeLink(manifest: setup.manifestStatus(), launcher: setup.launcher.path, browsers: model.blocking.status.browsers,
                              chromeRunning: true, now: model.blocking.now)
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("Set up Chrome")
                .font(Typo.heading)
            step(1, "Let Chrome talk to Three") {
                Text("Three adds two things on this Mac:")
                    .foregroundStyle(.secondary)
                bullet("A connection file Chrome reads, so only the Three extension can ask Three what to block", path: setup.manifestURL.path)
                bullet("A copy of the extension for Chrome to load", path: setup.extensionFolder.path)
                DisclosureGroup("Show connection file") {
                    Text((try? setup.manifestData()).flatMap { String(data: $0, encoding: .utf8) } ?? "")
                        .font(Typo.code)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if current {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button(setup.manifestStatus() == .missing ? "Add Connection" : "Update Connection") { install(setup) }
                        .buttonStyle(.borderedProminent)
                }
                if let error {
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.overrun)
                        Text(error).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            step(2, "Load the extension in each Chrome profile") {
                Text("In Chrome, open chrome://extensions, turn on Developer mode, click Load unpacked and choose the extension folder. Repeat in every profile you use for work.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.sm) {
                    Button(copied ? "Copied" : "Copy chrome://extensions") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("chrome://extensions", forType: .string)
                        copied = true
                    }
                    Button("Show Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([setup.extensionFolder]) }
                        .disabled(!FileManager.default.fileExists(atPath: setup.extensionFolder.path))
                }
                Text("Chrome warns that the extension can read and change data on all websites. That's how it stops a blocked site in any tab. It checks each address on your Mac and tells Three only which rule matched. Guest and Incognito windows aren't covered.")
                    .font(Typo.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            step(3, "Check the connection") {
                if link.action == .remove {
                    Label(link.value, systemImage: "checkmark.circle.fill")
                } else {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text(link.value == "Waiting for the extension" || link.value == "Not set up" ? "Waiting for Chrome…" : link.value)
                    }
                }
                if let detail = link.detail {
                    Text(detail)
                        .font(Typo.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(Typo.body)
        .padding(Space.xl)
        .frame(width: 480)
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Text("\(number)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(title)
                content()
            }
        }
    }

    private func bullet(_ text: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(path)
                .font(Typo.code)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func install(_ setup: ChromeSetup) {
        do {
            try setup.install()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        revision += 1
    }
}
