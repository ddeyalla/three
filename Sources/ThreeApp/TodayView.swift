import SwiftUI
import ThreeCore

struct TodayView: View {
    var body: some View {
        HStack(spacing: 0) {
            NowPane()
                .frame(width: 440)
            DayTimelineView()
        }
    }
}

/// Header on top; the timer and the day's tasks centred in the space below, scrolling only when they don't fit.
private struct NowPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Header()
                    Spacer(minLength: 24)
                    TimerSection()
                    TaskList()
                        .padding(.top, 28)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .frame(minHeight: geo.size.height)
            }
            .scrollIndicators(.never)
        }
    }
}

private struct Header: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let snap = model.snapshot
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.largeTitle.weight(.bold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if snap.plan?.status == .draft, !snap.tasks.isEmpty {
                Button("Commit plan") { model.perform { try model.store.commit(day: snap.day) } }
                    .buttonStyle(.glass)
                    .help("Lock in today's plan")
            }
        }
    }

    private var summary: String {
        let snap = model.snapshot
        var parts = [snap.day.startDate.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if snap.activeTaskCount > 0 { parts.append("\(snap.doneCount) of \(snap.activeTaskCount) done") }
        let focus = snap.focusSeconds(at: model.now)
        if focus >= 60 { parts.append("\(Format.duration(focus)) focused") }
        return parts.joined(separator: " · ")
    }
}

// MARK: Timer

private struct TimerSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Text(heading)
                .font(.title3.weight(.medium))
                .lineLimit(1)
            DialView(size: 220)
            VStack(spacing: 8) {
                Text(readout)
                    .font(.system(size: 40, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle((model.remaining ?? 1) <= 0 ? Theme.overrun : .primary)
                    .contentTransition(.numericText(countsDown: true))
                Text(span)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
            }
            Controls()
                .padding(.top, 4)
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
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
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
            .controlSize(.large)
        }
    }
}

// MARK: Tasks

private struct TaskList: View {
    @Environment(AppModel.self) private var model

    private var rows: [TaskRow] { model.snapshot.tasks.filter { $0.task.status != .dropped } }

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
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
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
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
