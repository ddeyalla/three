import SwiftUI
import ThreeCore

struct NotchView: View {
    @Environment(AppModel.self) private var model
    let commands: NotchCommands
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let session = model.running, session.kind == .focus {
                HStack(spacing: Space.md) {
                    VStack(alignment: .leading, spacing: Space.hairline) {
                        Text(model.runningTask?.task.title ?? "Focus block")
                            .font(Typo.body)
                            .lineLimit(1)
                            .help(model.runningTask?.task.title ?? "Focus block")
                        HStack(spacing: Space.xs) {
                            Circle().fill(model.runningTask?.category.color ?? Theme.idle)
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                            Text(model.runningTask?.category.name ?? "Focus")
                                .lineLimit(1)
                        }
                        .font(Typo.meta)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Space.xs)
                    VStack(alignment: .trailing, spacing: Space.hairline) {
                        Text(Format.clock(session.remaining(at: model.now)))
                            .font(Typo.heading)
                            .monospacedDigit()
                        Text(session.isPaused ? "Paused" : session.remaining(at: model.now) < 0 ? "Overrun" : "Remaining")
                            .font(Typo.meta)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: Space.sm) {
                    Button(session.isPaused ? "Resume" : "Pause",
                           systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                        commands.perform(.pauseResume, sessionID: session.id)
                    }
                    .help(session.isPaused ? "Resume this focus block" : "Pause this focus block")
                    Button("Finish") { commands.perform(.finish, sessionID: session.id) }
                        .help("Finish this block and open reflection")
                    Spacer(minLength: Space.xs)
                    Button("Open Three", systemImage: "macwindow") {
                        commands.perform(.openMain, sessionID: session.id)
                    }
                    .labelStyle(.iconOnly)
                    .help("Open Three’s main window")
                    Button("Hide controls", systemImage: "xmark", action: dismiss)
                        .labelStyle(.iconOnly)
                        .keyboardShortcut(.cancelAction)
                        .help("Hide for this focus block (Esc)")
                }
                .disabled(model.reflectionPresentation != nil)
                if let error = model.error {
                    Text(error).font(Typo.meta).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .font(Typo.body)
        .buttonStyle(.glass)
        .controlSize(.regular)
        .padding(Space.md)
        .frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
        .preferredColorScheme(.dark)
    }
}

struct NotchSettingsSection: View {
    @Environment(AppModel.self) private var model
    let controller: NotchController

    var body: some View {
        @Bindable var preference = controller.preference
        Section {
            Toggle("Notch focus controls", isOn: $preference.isEnabled)
            Button("Show Controls", action: controller.showControls)
                .disabled(!preference.isEnabled || controller.placement == nil
                          || model.running?.kind != .focus || model.reflectionPresentation != nil)
        } footer: {
            Text(controller.availabilityText)
                .font(Typo.meta)
                .foregroundStyle(.secondary)
        }
        .font(Typo.body)
    }
}
