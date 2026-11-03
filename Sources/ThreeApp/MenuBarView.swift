import AppKit
import SwiftUI
import ThreeCore

@MainActor
struct MenuBarStatus {
    let symbol: String
    let time: String?
    let spokenLabel: String

    init(model: AppModel, reduceMotion: Bool) {
        if !model.deferredReflections.isEmpty {
            symbol = reduceMotion || Int(model.now.timeIntervalSince1970).isMultiple(of: 2) ? "circlebadge.fill" : "circlebadge"
        } else if model.blocking.isEnforcing {
            symbol = "hand.raised.fill"
        } else {
            symbol = model.running?.kind == .break ? "cup.and.saucer.fill" : "timer"
        }
        if let running = model.running {
            let clock = Format.clock(running.remaining(at: model.now))
            time = running.kind == .break ? "Break \(clock)" : running.isPaused ? "Paused \(clock)" : clock
        } else { time = nil }
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
        spokenLabel = parts.joined(separator: ", ")
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    let openMain: () -> Void
    let openSettings: () -> Void

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
            } else if model.isTodayClosed {
                Button("Review closed day") {
                    model.reviewingDay = model.snapshot.day
                    openMain()
                }
                .buttonStyle(.glass)
            } else if let next = model.selectedTask {
                Button { model.start(next) } label: {
                    Label("Start \(next.task.title)", systemImage: "play.fill").lineLimit(1)
                }
                .buttonStyle(.primary(next.category.color))
            }

            if model.blocking.policy.isActive {
                BlockingRow(openSettings: openSettings)
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

            if !model.setup.onboardingDismissed {
                SetupIntroduction(openConnect: {
                    model.settingsTab = .connect
                    openSettings()
                }, openSetup: openSettings)
            }
            if case .failed(let message) = model.setup.shortcut.status {
                Text(message).font(Typo.meta).foregroundStyle(Theme.overrun)
                Button("Shortcut settings…") { model.settingsTab = .setup; openSettings() }
                    .buttonStyle(.plain)
            }
            if let error = model.notificationError {
                Text(error).font(Typo.meta).foregroundStyle(Theme.overrun)
            }
            QuickAddField(defaultDay: nil, placeholder: "Capture to inbox", claimsKeyboardShortcut: false)
            ErrorNote()

            Divider()
            HStack {
                Button("Open Three") {
                    openMain()
                }
                Spacer()
                Button("Settings…") { openSettings() }
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
    let openSettings: () -> Void

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
        if !options.contains(where: { $0.availableRule != nil }) {
            // A disabled Menu still reaches the menu bar enabled, with an empty submenu.
            Button("Unblock for 5 Minutes") {}.disabled(true)
        } else {
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
        }
    }
}
