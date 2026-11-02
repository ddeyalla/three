import AppKit
import SwiftUI
import ThreeCore

enum SettingsTab: Hashable {
    case timer, categories, blocking, connect
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Tab("Timer", systemImage: "timer", value: .timer) { TimerSettings() }
            Tab("Categories", systemImage: "circle.grid.2x2", value: .categories) { CategorySettings() }
            Tab("Blocking", systemImage: "hand.raised", value: .blocking) { BlockingSettings() }
            Tab("Connect", systemImage: "point.3.connected.trianglepath.dotted", value: .connect) { ConnectSettings() }
        }
        .frame(width: 520, height: 460)
        .preferredColorScheme(.dark)
    }
}

// MARK: Timer

private struct TimerSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("chime") private var chime = true

    var body: some View {
        let p = model.snapshot.preferences
        Form {
            Section {
                stepper("Focus session", p.sessionMinutes, 5...240, step: 5) { $0.sessionMinutes = $1 }
                stepper("New task block", p.defaultBlockMinutes, 5...480, step: 5) { $0.defaultBlockMinutes = $1 }
            } footer: {
                Text("A session is one sitting on the dial. A block is the total time a task gets today.")
                    .foregroundStyle(.secondary)
            }
            Section {
                stepper("Short break", p.shortBreakMinutes, 1...60, step: 1) { $0.shortBreakMinutes = $1 }
                stepper("Long break", p.longBreakMinutes, 1...120, step: 5) { $0.longBreakMinutes = $1 }
                stepper("Long break after", p.longBreakAfterMinutes, 15...600, step: 5) { $0.longBreakAfterMinutes = $1 }
            } footer: {
                Text("The command-line tool uses these too.").foregroundStyle(.secondary)
            }
            Section {
                Toggle("Chime when a block ends", isOn: $chime)
            }
        }
        .formStyle(.grouped)
    }

    private func stepper(_ title: String, _ value: Int, _ range: ClosedRange<Int>, step: Int,
                         _ set: @escaping (inout Preferences, Int) -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("\(value) min").monospacedDigit()
                Stepper(title, value: Binding(get: { value }, set: { new in
                    var p = model.snapshot.preferences
                    set(&p, new)
                    model.perform { try model.store.setPreferences(p) }
                }), in: range, step: step)
                .labelsHidden()
            }
        }
    }
}

// MARK: Categories

private struct CategorySettings: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""

    var body: some View {
        Form {
            Section {
                ForEach(model.snapshot.categories.filter { !$0.archived }) { CategoryRow(category: $0) }
                HStack {
                    TextField("New category", text: $newName)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Type #name in quick add to file a task. Archiving keeps old tasks' colours.")
                    .foregroundStyle(.secondary)
            }
            let archived = model.snapshot.categories.filter(\.archived)
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { c in
                        HStack {
                            Circle().fill(c.color).frame(width: 10, height: 10)
                            Text(c.name).foregroundStyle(.secondary)
                            Spacer()
                            Button("Restore") { model.perform { try model.store.updateCategory(c.id, archived: false) } }
                        }
                    }
                }
            }
            if let error = model.error {
                Text(error).foregroundStyle(Theme.now)
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let palette = ["#F2766B", "#6E9BF2", "#E5A84B", "#4FBF8B", "#A58AF0", "#5CC6D0", "#E57BB5", "#B8A27A"]
        let color = palette[model.snapshot.categories.count % palette.count]
        let name = newName
        model.perform { try model.store.addCategory(name: name, colorHex: color) }
        if model.error == nil { newName = "" }
    }
}

private struct CategoryRow: View {
    @Environment(AppModel.self) private var model
    let category: ThreeCore.Category
    @State private var name = ""

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("Colour", selection: Binding(
                get: { category.color },
                set: { color in
                    guard let hex = color.hexString, hex != category.colorHex else { return }
                    model.perform { try model.store.updateCategory(category.id, colorHex: hex) }
                }), supportsOpacity: false)
                .labelsHidden()
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .onSubmit { if name != category.name { model.perform { try model.store.updateCategory(category.id, name: name) } } }
            Button {
                model.perform { try model.store.updateCategory(category.id, archived: true) }
            } label: {
                Image(systemName: "archivebox")
            }
            .buttonStyle(.borderless)
            .help("Archive")
        }
        .onAppear { name = category.name }
        .onChange(of: category.name) { name = category.name }
    }
}

extension Color {
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

// MARK: Connect

private struct ConnectSettings: View {
    @State private var linked = FileManager.default.fileExists(atPath: ConnectSettings.linkPath)
    @State private var copied: String?

    static let linkPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/three").path
    static let helperPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/three").path

    private let agentNote = """
    I use Three (a focus planner) through its `three` CLI. Useful commands:
    three today --json | three inbox | three upcoming
    three capture "Title #category 45m tomorrow"   (no day goes to the inbox)
    three plan "Title:Category:60" … --commit | three schedule i1 today
    three start [n] | pause | resume | extend 10 | stop | done n
    three step add n "first small step" | three step done n 1
    Keep a day to three tasks (five at most). Only tighten my plan, never loosen it.
    """

    var body: some View {
        Form {
            Section {
                LabeledContent("Command-line tool") {
                    if linked {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Install", action: install)
                    }
                }
                copyRow("~/.local/bin/three", value: "three today")
            } footer: {
                Text("The CLI and this app share one database, so changes show up instantly in both.")
                    .foregroundStyle(.secondary)
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste this into CLAUDE.md or AGENTS.md so Claude Code or Codex can plan and run your day.")
                        .foregroundStyle(.secondary)
                    Text(agentNote)
                        .font(Typo.code)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.25), in: .rect(cornerRadius: 8))
                    Button(copied == "agent" ? "Copied" : "Copy instructions") { copy(agentNote, id: "agent") }
                }
            } header: {
                Text("AI agents")
            }
            Section("Coming next") {
                LabeledContent("MCP server", value: "v0.4")
                LabeledContent("Calendar sync", value: "v0.5")
            }
        }
        .formStyle(.grouped)
    }

    private func copyRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Button(copied == value ? "Copied" : "Copy \"\(value)\"") { copy(value, id: value) }
                .buttonStyle(.borderless)
        }
    }

    private func copy(_ text: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = id
    }

    private func install() {
        let link = URL(fileURLWithPath: Self.linkPath)
        try? FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: link)
        try? FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: Self.helperPath)
        linked = FileManager.default.fileExists(atPath: Self.linkPath)
    }
}
