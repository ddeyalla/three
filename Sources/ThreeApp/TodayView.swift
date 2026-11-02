import SwiftUI
import ThreeCore

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            NowPane()
                .frame(width: 500)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            DayTimelineView()
        }
        .background {
            ZStack {
                Theme.canvas
                RadialGradient(colors: [model.accent.opacity(0.16), model.accent.opacity(0.05), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 900)
                    .animation(.easeOut(duration: 0.4), value: model.accent)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 960, minHeight: 720)
    }
}

private struct NowPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header()
            if let plan = model.snapshot.plan, plan.status == .draft, !model.snapshot.tasks.isEmpty {
                DraftBanner()
            }
            TaskList()
            Spacer(minLength: 8)
            TimerSection()
                .frame(maxWidth: .infinity)
            if let error = model.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(Theme.now)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 24)
    }
}

private struct Header: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let snap = model.snapshot
        VStack(alignment: .leading, spacing: 6) {
            Text(snap.day.startDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.primary)
            Text("\(snap.doneCount)/\(snap.activeTaskCount) DONE  ·  \(Format.duration(snap.focusSeconds(at: model.now)).uppercased()) FOCUS  ·  \(Format.duration(TimeInterval(snap.plannedMinutes * 60)).uppercased()) PLANNED")
                .font(Theme.stat())
                .foregroundStyle(Theme.secondary)
                .monospacedDigit()
        }
    }
}

private struct DraftBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let snap = model.snapshot
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Draft plan")
                    .font(.headline)
                Text("\(snap.activeTaskCount) tasks · \(Format.duration(TimeInterval(snap.plannedMinutes * 60)))")
                    .font(Theme.stat())
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button("Commit") { model.perform { try model.store.commit(day: snap.day) } }
                .buttonStyle(.glassProminent)
                .tint(model.accent)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

// MARK: Tasks

private struct TaskList: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    private var rows: [TaskRow] { model.snapshot.tasks.filter { $0.task.status != .dropped } }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    TaskCard(row: row, index: index, count: rows.count)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                        .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.04), value: appeared)
                }
                if model.snapshot.activeTaskCount < Rules.maxTasks {
                    TaskComposer()
                }
                if model.snapshot.activeTaskCount > Rules.idealTasks {
                    Text(model.snapshot.activeTaskCount == Rules.maxTasks
                         ? "Five is the limit. Drop one to add another."
                         : "Three is the sweet spot. Are all of these today?")
                        .font(.caption)
                        .foregroundStyle(Color.orange.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            }
        }
        .onAppear { appeared = true }
    }
}

private struct TaskCard: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    let index: Int
    let count: Int

    private var isRunning: Bool { model.running?.taskId == row.id }
    private var isSelected: Bool { model.running == nil && model.selectedTask?.id == row.id }
    private var isClosed: Bool { !row.task.status.isOpen }

    var body: some View {
        Button {
            if !isClosed && model.running == nil { model.select(row) }
        } label: {
            HStack(spacing: 12) {
                Capsule()
                    .fill(row.category.color)
                    .frame(width: 4, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isClosed ? Theme.tertiary : Theme.primary)
                        .strikethrough(row.task.status == .done, color: Theme.tertiary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Theme.stat(10))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                if isRunning {
                    Text("NOW")
                        .font(Theme.stat(10))
                        .foregroundStyle(row.category.color)
                }
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(isRunning || isSelected ? .regular.tint(row.category.color.opacity(0.22)).interactive()
                                                  : .regular.interactive(),
                         in: .rect(cornerRadius: 14))
            .opacity(isClosed ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if !isClosed && model.running == nil { model.start(row) }
        })
        .contextMenu { menu }
    }

    private var subtitle: String {
        var parts = [row.category.name.uppercased(), "\(row.task.blockMinutes)M"]
        if row.focusedSeconds >= 60 { parts.append("\(Format.duration(row.focusedSeconds).uppercased()) DONE") }
        if row.task.status == .carried { parts.append("TOMORROW") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var trailing: some View {
        switch row.task.status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(row.category.color)
        case .carried:
            Image(systemName: "arrow.uturn.forward")
                .foregroundStyle(Theme.tertiary)
        default:
            ProgressRing(progress: row.progress, color: row.category.color)
        }
    }

    @ViewBuilder private var menu: some View {
        if row.task.status.isOpen {
            Button("Start now") { model.start(row) }.disabled(model.running?.kind == .focus)
            Button("Mark done") { model.perform { try model.store.setTaskStatus(row.id, .done) } }
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
        } else {
            Button("Reopen") { model.perform { try model.store.setTaskStatus(row.id, .todo) } }
        }
        Divider()
        Button("Move up") { model.perform { try model.store.moveTask(row.id, to: index - 1) } }.disabled(index == 0)
        Button("Move down") { model.perform { try model.store.moveTask(row.id, to: index + 1) } }.disabled(index == count - 1)
        Divider()
        Button("Remove", role: .destructive) { model.perform { try model.store.removeTask(row.id) } }
    }
}

private struct ProgressRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 20, height: 20)
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
                .foregroundStyle(Theme.tertiary)
                .frame(width: 4)
                .padding(.trailing, 4)
            TextField("Add a task", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit(add)
            Menu {
                ForEach(model.snapshot.categories) { c in
                    Button(c.name) { categoryId = c.id }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(category?.color ?? Theme.idle).frame(width: 7, height: 7)
                    Text(category?.name ?? "")
                }
                .font(.system(size: 12))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            Menu {
                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { m in
                    Button("\(m) min") { minutes = m }
                }
            } label: {
                Text("\(minutes)m").font(Theme.stat(11)).monospacedDigit()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
        }
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(.white.opacity(focused ? 0.04 : 0)), in: .rect(cornerRadius: 14))
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

// MARK: Timer

private struct TimerSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Text(heading)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
            DialView(size: 210)
            VStack(spacing: 6) {
                Text(readout)
                    .font(.system(size: 38, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle((model.remaining ?? 1) <= 0 ? Color.orange : Theme.primary)
                Text(span)
                    .font(Theme.stat(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
            }
            Controls()
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
        if let remaining = model.remaining { return Format.clock(remaining) }
        return Format.clock(TimeInterval(model.dialMinutes * 60))
    }

    private var span: String {
        if let running = model.running {
            if running.isPaused { return "PAUSED" }
            return "\(Format.time(running.startedAt)) → \(Format.time(running.plannedEnd))"
        }
        return "\(Format.time(model.now)) → \(Format.time(model.now.addingTimeInterval(TimeInterval(model.dialMinutes * 60))))"
    }
}

private struct Controls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let running = model.running {
                    if running.kind == .focus {
                        Button { model.extend(5) } label: { Text("+5").frame(width: 34) }
                            .buttonStyle(.glass)
                            .help("Add 5 minutes")
                        Button { model.togglePause() } label: {
                            Label(running.isPaused ? "Resume" : "Pause",
                                  systemImage: running.isPaused ? "play.fill" : "pause.fill")
                                .frame(width: 120)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(model.accent)
                        Button { model.finishEarly() } label: { Text("Finish").frame(width: 54) }
                            .buttonStyle(.glass)
                    } else {
                        Button { model.stop() } label: { Text("End break").frame(width: 90) }
                            .buttonStyle(.glass)
                        if let next = model.snapshot.nextTask {
                            Button { model.start(next) } label: {
                                Label("Start \(next.task.title)", systemImage: "play.fill")
                                    .lineLimit(1)
                                    .frame(maxWidth: 200)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(next.category.color)
                        }
                    }
                } else {
                    Button { model.start() } label: {
                        Label("Start", systemImage: "play.fill").frame(width: 140)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(model.accent)
                    .disabled(model.selectedTask == nil)
                }
            }
            .controlSize(.large)
        }
    }
}
