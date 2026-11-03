import SwiftUI
import ThreeCore

struct PlanningSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var form = PlanningSettings()

    private var planning: PlanningController { model.planning }
    private var changed: Bool { form != planning.settings }

    var body: some View {
        Form {
            Section {
                Toggle("Scheduled planning", isOn: $form.enabled)
                TextField("Local planning time (HH:mm)", text: $form.localTime)
                TextField("Local command", text: $form.command, axis: .vertical)
                    .font(Typo.code)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("planning-command")
                HStack {
                    Button("Save") { save() }.disabled(!changed)
                    Button("Use Codex default") { form.command = PlanningSettings.defaultCommand }
                    Spacer()
                    Button("Test") {
                        if save() { planning.check(now: Date(), test: true) }
                    }
                    .disabled(planning.checking)
                    if planning.checking {
                        Button("Cancel") { planning.cancel() }
                    }
                }
            } footer: {
                Text("Save applies the switch, time, and command together. Test saves them and runs now. Off by default, with one catch-up after wake while Three is open. Existing plans and timers are preserved. Commands use your home directory and login shell, with a ten-minute limit and 64 KiB per output stream.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Only use a command you trust. It has your account's access and may change files or contact external services. Three restricts the provided MCP planning channel to one draft for today. It does not sandbox arbitrary commands or undo their external actions.")
                    .font(Typo.meta)
                    .foregroundStyle(.secondary)
            }
            if let error = planning.error { Text(error).foregroundStyle(Theme.overrun).textSelection(.enabled) }
            if let run = planning.lastRun {
                Section("Last run") {
                    LabeledContent("Status", value: run.status.rawValue)
                    LabeledContent("Local date", value: run.day.rawValue)
                    LabeledContent("Started", value: run.startedAt.formatted())
                    LabeledContent("Deadline", value: run.deadline.formatted())
                    if let exit = run.exitCode { LabeledContent("Exit status", value: String(exit)) }
                    if let error = run.error { Text(error).foregroundStyle(Theme.overrun).textSelection(.enabled) }
                    if run.status == .running {
                        Text("This claim blocks all other planning commands. After an app crash, an unknown or surviving process group stays blocked. Three never kills a recovered PID.").font(Typo.meta)
                    }
                    if run.outputTruncated { Text("Output was truncated to 64 KiB per stream.").foregroundStyle(.secondary) }
                    DisclosureGroup("Command") { output(run.command) }
                    DisclosureGroup("stdout") { output(run.stdout.isEmpty ? "No stdout captured." : run.stdout) }
                    DisclosureGroup("stderr") { output(run.stderr.isEmpty ? "No stderr captured." : run.stderr) }
                }
            } else {
                Text("No planning command has run.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { planning.refresh(); load() }
        .onChange(of: planning.settings) { load() }
    }

    private func load() { form = planning.settings }

    @discardableResult
    private func save() -> Bool {
        planning.save(form)
        return planning.error == nil
    }

    private func output(_ text: String) -> some View {
        Text(text).font(Typo.code).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}
