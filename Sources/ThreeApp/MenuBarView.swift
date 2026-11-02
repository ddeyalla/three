import AppKit
import SwiftUI
import ThreeCore

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// macOS draws a menu bar extra as one template symbol and a plain title, dropping a `Label`'s text, a second image,
    /// sizes and opacity (docs/menu-bar-design.md). So the symbol shows the most pressing state and the time stays beside it.
    var body: some View {
        HStack {
            Image(systemName: symbol)
            if let time { Text(time) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    /// A saved reflection's dot, else the hand while something is really blocked, else the timer.
    private var symbol: String {
        if !model.deferredReflections.isEmpty {
            // Swapping the symbol is the pulse: the menu bar ignores opacity.
            return reduceMotion || Int(model.now.timeIntervalSince1970).isMultiple(of: 2) ? "circlebadge.fill" : "circlebadge"
        }
        // Never pulses: blocking is a state, not a reminder.
        if model.blocking.isEnforcing { return "hand.raised.fill" }
        return model.running?.kind == .break ? "cup.and.saucer.fill" : "timer"
    }

    /// "24:13", "Paused 24:13", "+03:12" or "Break 4:12": worded to stand alone, since the symbol may be showing
    /// the reminder or blocking instead.
    private var time: String? {
        guard let running = model.running else { return nil }
        let clock = Format.clock(running.remaining(at: model.now))
        if running.kind == .break { return "Break \(clock)" }
        return running.isPaused ? "Paused \(clock)" : clock
    }

    private var spokenLabel: String {
        var parts: [String]
        if let running = model.running, let time {
            parts = running.kind == .break ? [time] : [model.runningTask?.task.title ?? "Focus", time]
        } else if let next = model.snapshot.nextTask {
            parts = ["Next: \(next.task.title)"]
        } else {
            parts = [model.snapshot.tasks.isEmpty ? "Plan today" : "Three"]
        }
        if !model.deferredReflections.isEmpty { parts.append("Saved reflection awaiting review") }
        if model.blocking.isEnforcing { parts.append(model.blocking.headline) }
        return parts.joined(separator: ", ")
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if let saved = model.deferredReflections.first {
                VStack(alignment: .leading, spacing: Space.sm) {
                    if model.deferredReflections.count > 1 {
                        Text("\(model.deferredReflections.count) saved reflections")
                            .font(Typo.meta)
                            .foregroundStyle(.secondary)
                    }
                    Text(saved.task?.task.title ?? "Focus block")
                        .font(Typo.heading)
                        .lineLimit(1)
                    Text("Made progress · Okay saved automatically")
                        .font(Typo.meta)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Space.sm) {
                        Button("Review reflection") { model.reviewReflection(saved) }
                            .disabled(model.reflectionPresentation != nil)
                        Button("Dismiss") { model.dismissReflection(saved) }
                    }
                    .buttonStyle(.glass)
                    .font(Typo.body)
                }
            }
            if let running = model.running {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(running.kind == .break ? "Break" : (model.runningTask?.task.title ?? "Focus"))
                        .font(Typo.focus)
                        .lineLimit(1)
                    Text(Format.clock(running.remaining(at: model.now)))
                        .font(Typo.display)
                        .foregroundStyle(running.remaining(at: model.now) <= 0 ? Theme.overrun : .primary)
                }
                HStack(spacing: Space.sm) {
                    if running.kind == .focus {
                        Button(running.isPaused ? "Resume" : "Pause") { model.togglePause() }
                            .buttonStyle(.primary(model.accent))
                        Button("+5") { model.extend(5) }.buttonStyle(.glass)
                        Button("Finish") { model.finishEarly() }.buttonStyle(.glass)
                    } else {
                        Button("End break") { model.stop() }.buttonStyle(.glass)
                    }
                }
            } else if let next = model.snapshot.nextTask {
                Button { model.start(next) } label: {
                    Label("Start \(next.task.title)", systemImage: "play.fill").lineLimit(1)
                }
                .buttonStyle(.primary(next.category.color))
            }

            if model.blocking.policy.isActive {
                BlockingRow()
            }

            if !model.snapshot.tasks.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(model.snapshot.tasks.filter { $0.task.status != .dropped }) { row in
                        HStack(spacing: Space.sm) {
                            Image(systemName: row.task.status == .done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(row.category.color)
                            Text(row.task.title)
                                .lineLimit(1)
                                .foregroundStyle(row.task.status.isOpen ? .primary : .secondary)
                            Spacer()
                            Text("\(row.task.blockMinutes)m")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(Typo.body)
                    }
                }
            }

            QuickAddField(defaultDay: nil, placeholder: "Capture to inbox", claimsKeyboardShortcut: false)
            ErrorNote()

            Divider()
            HStack {
                Button("Open Three") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(Typo.body)
            .foregroundStyle(.secondary)
        }
        .padding(Space.lg)
        .frame(width: 300)
        .preferredColorScheme(.dark)
    }
}

/// While blocking is on: until when, why and what covers it, with the one route to open a rule for five minutes.
private struct BlockingRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let state = model.blocking
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: state.isDegraded ? "exclamationmark.circle.fill" : "hand.raised.fill")
                .foregroundStyle(state.isDegraded ? AnyShapeStyle(Theme.overrun) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.hairline) {
                Text(state.headline)
                    .font(Typo.body)
                    .monospacedDigit()
                Text(state.detail)
                    .font(Typo.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Space.xs)
            Menu {
                if !state.blockedSites.isEmpty && state.workingProfiles.isEmpty {
                    Button("Set Up Chrome…") { openBlockingSettings(chrome: true) }
                }
                if !state.unblockOptions.isEmpty {
                    UnblockMenu(model: model)
                }
                Button("Blocking Settings…") { openBlockingSettings(chrome: false) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Blocking options")
            .accessibilityLabel("Blocking options")
        }
    }

    private func openBlockingSettings(chrome: Bool) {
        model.settingsTab = .blocking
        if chrome { model.chromeSetupRequested = true }
        openSettings()
        NSApp.activate()
    }
}

/// Unblock for 5 Minutes, as the Focus menu and the menu-bar popover both list it.
struct UnblockMenu: View {
    let model: AppModel

    var body: some View {
        let options = model.blocking.unblockOptions
        Menu("Unblock for 5 Minutes") {
            ForEach(options) { option in
                switch option {
                case .available(let rule):
                    Button(rule.name) { model.requestUnblock(rule) }
                case .covered(let rule, let parent):
                    Button("\(rule.name) (also blocked by \(parent.name))") {}.disabled(true)
                case .alreadyOpen(let rule, let until):
                    Button("\(rule.name) · open until \(Format.time(until))") {}.disabled(true)
                }
            }
        }
        .disabled(options.isEmpty)
    }
}
