import AppKit
import SwiftUI
import ThreeCore

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The menu bar draws one symbol from a label (its first image), so the item shows one thing by priority: a saved
    /// reflection's dot, else the blocking hand while something is really blocked, else the timer.
    var body: some View {
        if !model.deferredReflections.isEmpty {
            Image(systemName: "circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 6, height: 6)
                .opacity(reminderBright ? 1 : 0.35)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1), value: reminderBright)
                .accessibilityLabel("Saved reflection awaiting review")
        } else if model.blocking.isEnforcing {
            // Never pulses: blocking is a state, not a reminder.
            Image(systemName: "hand.raised.fill")
                .accessibilityLabel(model.blocking.headline)
        } else {
            title
        }
    }

    private var reminderBright: Bool { reduceMotion || Int(model.now.timeIntervalSince1970).isMultiple(of: 2) }

    @ViewBuilder private var title: some View {
        if let running = model.running {
            let title = running.kind == .break ? "Break" : (model.runningTask?.task.title ?? "Focus")
            Label("\(short(title)) · \(running.isPaused ? "paused" : Format.clock(running.remaining(at: model.now)))",
                  systemImage: running.kind == .break ? "cup.and.saucer.fill" : "timer")
                .monospacedDigit()
        } else if let next = model.snapshot.nextTask {
            Label("Next: \(short(next.task.title))", systemImage: "timer")
        } else {
            Label(model.snapshot.tasks.isEmpty ? "Plan today" : "Three", systemImage: "timer")
        }
    }

    private func short(_ s: String) -> String { s.count > 22 ? String(s.prefix(21)) + "…" : s }
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
                            .buttonStyle(.glassProminent)
                            .tint(model.accent)
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
                .buttonStyle(.glassProminent)
                .tint(next.category.color)
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
                if state.isDegraded {
                    Button("Set Up Chrome…") { openBlockingSettings(chrome: true) }
                }
                if !state.unblockable.isEmpty || !state.policy.exceptions.isEmpty {
                    Menu("Unblock for 5 Minutes") {
                        ForEach(state.unblockable) { rule in
                            if let parent = state.policy.coveringRule(for: rule) {
                                Button("\(rule.name) (also blocked by \(parent.name))") {}.disabled(true)
                            } else {
                                Button(rule.name) { model.requestUnblock(rule) }
                            }
                        }
                        ForEach(state.policy.exceptions, id: \.id) { e in
                            if let rule = state.status.rules.first(where: { $0.id == e.ruleId }) {
                                Button("\(rule.name) · open until \(Format.time(e.expiresAt))") {}.disabled(true)
                            }
                        }
                    }
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
