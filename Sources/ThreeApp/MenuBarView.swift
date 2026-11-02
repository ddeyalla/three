import AppKit
import SwiftUI
import ThreeCore

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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
        VStack(alignment: .leading, spacing: 14) {
            if let running = model.running {
                VStack(alignment: .leading, spacing: 4) {
                    Text(running.kind == .break ? "Break" : (model.runningTask?.task.title ?? "Focus"))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(Format.clock(running.remaining(at: model.now)))
                        .font(.system(size: 34, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(running.remaining(at: model.now) <= 0 ? Theme.overrun : .primary)
                }
                HStack(spacing: 8) {
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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.snapshot.tasks.filter { $0.task.status != .dropped }) { row in
                        HStack(spacing: 8) {
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
                        .font(.system(size: 13))
                    }
                }
            }

            QuickAddField(defaultDay: nil, placeholder: "Capture to inbox")
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
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
        .preferredColorScheme(.dark)
    }
}
