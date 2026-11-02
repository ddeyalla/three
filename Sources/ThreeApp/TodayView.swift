import SwiftUI
import ThreeCore

struct TodayView: View {
    var body: some View {
        HStack(spacing: 0) {
            NowPane()
                .frame(width: 440)
            Divider()
            DayTimelineView()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .frame(minWidth: 900, minHeight: 680)
    }
}

private struct NowPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header()
            TimerSection()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            TaskList()
            if let error = model.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(Theme.now)
                    .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 20)
    }
}

private struct Header: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let snap = model.snapshot
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snap.day.startDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.title2.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if snap.plan?.status == .draft, !snap.tasks.isEmpty {
                Button("Commit plan") { model.perform { try model.store.commit(day: snap.day) } }
                    .controlSize(.small)
                    .help("Lock in today's plan")
            }
        }
    }

    private var summary: String {
        let snap = model.snapshot
        guard snap.activeTaskCount > 0 else { return "Nothing planned yet" }
        var parts = ["\(snap.doneCount) of \(snap.activeTaskCount) done"]
        let focus = snap.focusSeconds(at: model.now)
        if focus >= 60 { parts.append("\(Format.duration(focus)) focused") }
        if snap.plan?.status == .draft { parts.append("draft") }
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
            VStack(spacing: 2) {
                Text(readout)
                    .font(.system(size: 40, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle((model.remaining ?? 1) <= 0 ? Theme.overrun : .primary)
                    .contentTransition(.numericText(countsDown: true))
                Text(span)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Controls()
                .padding(.top, 4)
        }
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
            if running.remaining(at: model.now) <= 0 { return "Over by \(Format.duration(-running.remaining(at: model.now)))" }
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
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                TaskRowView(row: row, index: index, count: rows.count)
            }
            if model.snapshot.activeTaskCount < Rules.maxTasks {
                TaskComposer()
            }
            if model.snapshot.activeTaskCount > Rules.idealTasks {
                Text(model.snapshot.activeTaskCount == Rules.maxTasks
                     ? "Five is the limit. Drop one to add another."
                     : "Three is the sweet spot. Are all of these today?")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, -10)
    }
}

private struct TaskRowView: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    let index: Int
    let count: Int
    @State private var hovering = false

    private var isRunning: Bool { model.running?.taskId == row.id }
    private var isSelected: Bool { model.running == nil && model.selectedTask?.id == row.id }
    private var isClosed: Bool { !row.task.status.isOpen }

    var body: some View {
        HStack(spacing: 10) {
            CompletionButton(row: row)
            Text(row.task.title)
                .font(.body.weight(isRunning || isSelected ? .medium : .regular))
                .foregroundStyle(isClosed ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(fill, in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if !isClosed && model.running == nil { model.start(row) } }
        .onTapGesture { if !isClosed && model.running == nil { model.select(row) } }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected || isRunning ? .isSelected : [])
    }

    private var fill: Color {
        if isRunning { return row.category.color.opacity(0.16) }
        if isSelected { return Theme.rowFill }
        return hovering && !isClosed ? Theme.rowHover : .clear
    }

    @ViewBuilder private var trailing: some View {
        switch row.task.status {
        case .carried:
            Label("Tomorrow", systemImage: "arrow.turn.up.right").labelStyle(.titleAndIcon)
        case .done:
            Text(Format.duration(row.focusedSeconds))
        default:
            if row.focusedSeconds >= 60 {
                Text("\(Int(row.focusedSeconds / 60)) / \(row.task.blockMinutes)m")
            } else {
                Text("\(row.task.blockMinutes)m")
            }
        }
    }

    @ViewBuilder private var menu: some View {
        if row.task.status.isOpen {
            Button("Start now") { model.start(row) }.disabled(model.running?.kind == .focus)
            Button("Push to tomorrow") { model.perform { try model.store.pushToTomorrow(row.id) } }
            Menu("Block") {
                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { m in
                    Button("\(m) min") { model.perform { try model.store.updateTask(row.id, blockMinutes: m) } }
                }
            }
            Menu("Category") {
                ForEach(model.snapshot.categories) { c in
                    Button(c.name) { model.perform { try model.store.updateTask(row.id, category: c.id) } }
                }
            }
        }
        Divider()
        Button("Move up") { model.perform { try model.store.moveTask(row.id, to: index - 1) } }.disabled(index == 0)
        Button("Move down") { model.perform { try model.store.moveTask(row.id, to: index + 1) } }.disabled(index == count - 1)
        Divider()
        Button("Remove", role: .destructive) { model.perform { try model.store.removeTask(row.id) } }
    }
}

/// The one way to mark a task done, or undo it.
private struct CompletionButton: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow

    private var isDone: Bool { row.task.status == .done }

    var body: some View {
        Button {
            model.perform { try model.store.setTaskStatus(row.id, isDone ? .todo : .done) }
        } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(row.task.status == .carried ? AnyShapeStyle(.tertiary) : AnyShapeStyle(row.category.color))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(row.task.status == .carried || model.running?.taskId == row.id)
        .help(isDone ? "Mark not done" : "Mark done")
        .accessibilityLabel(isDone ? "Done" : "Not done")
    }
}

private struct TaskComposer: View {
    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var categoryId: String?
    @State private var minutes = 60
    @FocusState private var focused: Bool

    private var category: ThreeCore.Category? {
        model.snapshot.categories.first { $0.id == categoryId } ?? model.snapshot.categories.first
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("Add a task", text: $title)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(add)
            if focused || !title.isEmpty {
                Menu {
                    ForEach(model.snapshot.categories) { c in
                        Button(c.name) { categoryId = c.id }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(category?.color ?? Theme.idle).frame(width: 7, height: 7)
                        Text(category?.name ?? "")
                    }
                }
                .menuIndicator(.hidden)
                .fixedSize()
                Menu {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { m in
                        Button("\(m) min") { minutes = m }
                    }
                } label: {
                    Text("\(minutes)m").monospacedDigit()
                }
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .font(.body)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(focused ? Theme.rowFill : .clear, in: .rect(cornerRadius: 8))
    }

    private func add() {
        guard let category, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.perform {
            try model.store.addTask(NewTask(title: title, category: category.id, blockMinutes: minutes),
                                    day: model.snapshot.day, source: .app)
        }
        if model.error == nil { title = "" }
    }
}
