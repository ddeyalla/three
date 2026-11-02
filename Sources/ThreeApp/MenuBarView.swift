import AppKit
import SwiftUI
import ThreeCore

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.xs) {
            if !model.deferredReflections.isEmpty {
                Image(systemName: "circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 6, height: 6)
                    .opacity(reminderBright ? 1 : 0.35)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1), value: reminderBright)
                    .accessibilityLabel("Saved reflection awaiting review")
            }
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
