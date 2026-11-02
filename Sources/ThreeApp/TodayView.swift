import SwiftUI
import ThreeCore

/// The middle pane: what the dial is about, the dial, the time left and the controls, centred.
struct NowPane: View {
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                TimerSection()
                    .padding(Space.xl)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollIndicators(.never)
        }
    }
}

// MARK: Timer

private struct TimerSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Space.md) {
            VStack(spacing: Space.xs) {
                Text(heading)
                    .font(Typo.focus)
                    .lineLimit(1)
                if let row = model.running?.kind == .break ? nil : (model.runningTask ?? model.selectedTask) {
                    TaskDetailLine(row: row)
                }
            }
            DialView(size: 240)
            VStack(spacing: Space.sm) {
                Text(readout)
                    .font(Typo.display)
                    .foregroundStyle((model.remaining ?? 1) <= 0 ? Theme.overrun : .primary)
                    .contentTransition(.numericText(countsDown: true))
                Text(span)
                    .font(Typo.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.xs)
                    .glassEffect(.regular, in: .capsule)
            }
            Controls()
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity)
    }

    private var heading: String {
        if let running = model.running {
            if running.kind == .break { return "Break" }
            return model.runningTask?.task.title ?? "Focus"
        }
        return model.selectedTask?.task.title ?? (model.snapshot.tasks.isEmpty ? "What are your three today?" : "All done for today")
    }

    private var readout: String {
        Format.clock(model.remaining ?? TimeInterval(model.dialMinutes * 60))
    }

    private var span: String {
        if let running = model.running {
            if running.isPaused { return "Paused" }
            if running.remaining(at: model.now) <= 0 { return "Ended \(Format.time(running.plannedEnd))" }
            return Format.span(running.startedAt, running.plannedEnd)
        }
        return Format.span(model.now, model.now.addingTimeInterval(TimeInterval(model.dialMinutes * 60)))
    }
}

private struct Controls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                if let running = model.running {
                    if running.kind == .focus {
                        Button("+5") { model.extend(5) }
                            .buttonStyle(.glass)
                            .help("Add 5 minutes")
                        Button { model.togglePause() } label: {
                            Label(running.isPaused ? "Resume" : "Pause",
                                  systemImage: running.isPaused ? "play.fill" : "pause.fill")
                                .frame(minWidth: 96)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(model.accent)
                        Button("Finish") { model.finishEarly() }
                            .buttonStyle(.glass)
                    } else {
                        Button("End break") { model.stop() }
                            .buttonStyle(.glass)
                        if let next = model.snapshot.nextTask {
                            Button { model.start(next) } label: {
                                Label("Start next", systemImage: "play.fill")
                            }
                            .buttonStyle(.glassProminent)
                            .tint(next.category.color)
                            .help("Start \(next.task.title)")
                        }
                    }
                } else {
                    Button { model.start() } label: {
                        Label("Start", systemImage: "play.fill").frame(minWidth: 112)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(model.accent)
                    .disabled(model.selectedTask == nil)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }
}

// MARK: Tasks

/// Today in the tasks pane: the day's summary, its tasks and a field to add one.
struct TodayList: View {
    @Environment(AppModel.self) private var model

    private var rows: [TaskRow] { model.snapshot.tasks.filter { $0.task.status != .dropped } }

    var body: some View {
        PaneList(subtitle: summary) {
            let snap = model.snapshot
            if snap.plan?.status == .draft, !snap.tasks.isEmpty {
                Button("Commit") { model.perform { try model.store.commit(day: snap.day) } }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("Lock in today's plan")
            }
        } content: {
            list
        }
    }

    private var summary: String {
        let snap = model.snapshot
        var parts = [snap.day.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))]
        if snap.activeTaskCount > 0 { parts.append("\(snap.doneCount) of \(snap.activeTaskCount) done") }
        let focus = snap.focusSeconds(at: model.now)
        if focus >= 60 { parts.append("\(Format.duration(focus)) focused") }
        return parts.joined(separator: " · ")
    }

    private var list: some View {
        GlassEffectContainer(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    TodayTaskCard(row: row, index: index, count: rows.count)
                }
                if model.snapshot.activeTaskCount < Rules.maxTasks {
                    QuickAddField(defaultDay: model.snapshot.day,
                                  placeholder: rows.isEmpty ? "Add your first task" : "Add a task")
                }
                if model.snapshot.activeTaskCount > Rules.idealTasks {
                    Text(model.snapshot.activeTaskCount == Rules.maxTasks
                         ? "Five is the limit. Move one to the inbox to add another."
                         : "Three is the sweet spot. Are all of these today?")
                        .font(Typo.meta)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Space.xs)
                        .padding(.top, Space.xs)
                }
            }
        }
    }
}

private struct TodayTaskCard: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    let index: Int
    let count: Int

    private var isRunning: Bool { model.running?.taskId == row.id }
    private var isSelected: Bool { model.running == nil && model.selectedTask?.id == row.id }

    var body: some View {
        TaskCard(row: row, running: isRunning, selected: isSelected, expanded: isRunning || isSelected,
                 onTap: { if row.task.status.isOpen && model.running == nil { model.select(row) } }) {
            trailing
        }
        .contextMenu {
            TaskMenuItems(row: row)
            Divider()
            Button("Move up") { model.perform { try model.store.moveTask(row.id, to: index - 1) } }.disabled(index == 0)
            Button("Move down") { model.perform { try model.store.moveTask(row.id, to: index + 1) } }.disabled(index == count - 1)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch row.task.status {
        case .carried:
            Label("Tomorrow", systemImage: "arrow.turn.up.right")
        case .done:
            Text(Format.duration(row.focusedSeconds))
        default:
            let focused = model.snapshot.focusedSeconds(of: row, at: model.now)
            if focused >= 60 {
                Text("\(Int(focused / 60)) / \(row.task.blockMinutes)m")
            } else {
                Text("\(row.task.blockMinutes)m")
            }
        }
    }
}
