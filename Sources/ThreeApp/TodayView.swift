import SwiftUI
import ThreeCore

/// The middle pane: one column of what the dial is about, how long is left, and what to do.
struct NowPane: View {
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                TimerSection(dial: DialView.diameter(fitting: geo.size))
                    .padding(Space.xl)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height,
                           alignment: Alignment(horizontal: .center, vertical: .optical))
            }
        }
    }
}

private extension VerticalAlignment {
    /// Two parts of the spare height above the column and three below, so it reads as centred.
    enum Optical: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height * 0.4 }
    }

    static let optical = VerticalAlignment(Optical.self)
}

// MARK: Timer

/// What Now shows. Every group in the column reads this instead of re-deriving it from the timer.
private enum NowState {
    /// Nothing running; Start would time this task.
    case ready(TaskRow)
    /// A focus block, running, paused or past its end. A block started without a task has none.
    case focus(Session, TaskRow?)
    case rest(Session, next: TaskRow?)
    /// Nothing open and nothing done yet.
    case empty
    /// Nothing open, and at least one task done.
    case allDone

    @MainActor init(_ model: AppModel) {
        if let running = model.running {
            self = running.kind == .focus ? .focus(running, model.runningTask) : .rest(running, next: model.snapshot.nextTask)
        } else if let task = model.selectedTask {
            self = .ready(task)
        } else {
            self = model.snapshot.doneCount > 0 ? .allDone : .empty
        }
    }

    /// The task whose title, category and current step lead the column.
    var task: TaskRow? {
        switch self {
        case .ready(let task): task
        case .focus(_, let task): task
        default: nil
        }
    }

    /// Whether there is a time to read: empty and finished days show the dial as a picture only.
    var isTiming: Bool {
        switch self {
        case .empty, .allDone: false
        default: true
        }
    }

    var isPaused: Bool {
        if case .focus(let session, _) = self { return session.isPaused }
        return false
    }
}

private struct TimerSection: View {
    @Environment(AppModel.self) private var model
    let dial: CGFloat

    var body: some View {
        let state = NowState(model)
        VStack(spacing: Space.xl) {
            what(state)
            VStack(spacing: 0) {
                DialView(size: dial)
                if state.isTiming {
                    Text(readout)
                        .font(Typo.display)
                        .foregroundStyle(readoutStyle(state))
                        .contentTransition(.numericText(countsDown: true))
                        .padding(.top, Space.md)
                    status(state)
                        .font(Typo.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.top, Space.xs)
                }
            }
            if case .allDone = state {} else {
                Controls(state: state)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func what(_ state: NowState) -> some View {
        VStack(spacing: Space.sm) {
            VStack(spacing: Space.hairline) {
                Text(title(state))
                    .font(Typo.title)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 420)
                    .help(state.task?.task.title ?? "")
                    .accessibilityAddTraits(.isHeader)
                subtitle(state)
            }
            if let task = state.task, !task.steps.isEmpty {
                CurrentStep(row: task)
            }
        }
    }

    private func title(_ state: NowState) -> String {
        switch state {
        case .ready(let task): task.task.title
        case .focus(_, let task): task?.task.title ?? "Focus"
        case .rest: "Break"
        case .empty: "What are your three today?"
        case .allDone: "All done for today"
        }
    }

    @ViewBuilder private func subtitle(_ state: NowState) -> some View {
        switch state {
        case .ready(let task), .focus(_, let task?):
            HStack(spacing: Space.xs) {
                Circle().fill(task.category.color).frame(width: 6, height: 6)
                Text(task.category.name)
            }
            .font(Typo.meta)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        case .rest(_, let next?):
            Text("Up next · \(next.task.title)")
                .font(Typo.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .empty:
            Text("Add a task, then start a block.")
                .font(Typo.body)
                .foregroundStyle(.secondary)
        case .allDone:
            Text(model.dayProgress.joined(separator: " · "))
                .font(Typo.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        default:
            EmptyView()
        }
    }

    private var readout: String {
        Format.clock(model.remaining ?? TimeInterval(model.dialMinutes * 60))
    }

    private func readoutStyle(_ state: NowState) -> AnyShapeStyle {
        if (model.remaining ?? 1) <= 0 { return AnyShapeStyle(Theme.overrun) }
        return state.isPaused ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }

    /// One plain line under the time left: the span, Paused, or when an overrunning block was due to end.
    /// While something is really being blocked, a quiet "· Blocking" follows it.
    private func status(_ state: NowState) -> some View {
        HStack(spacing: 0) {
            timing(state)
            if model.blocking.isEnforcing {
                Text(" · \(Image(systemName: "hand.raised.fill")) Blocking")
                    .help("\(model.blocking.headline). \(model.blocking.detail)")
                    .accessibilityLabel(model.blocking.headline)
            }
        }
    }

    @ViewBuilder private func timing(_ state: NowState) -> some View {
        if state.isPaused {
            Label("Paused", systemImage: "pause.fill")
        } else if let running = model.running {
            Text(running.remaining(at: model.now) <= 0
                 ? "Ended \(Format.time(running.plannedEnd))"
                 : Format.span(running.startedAt, running.plannedEnd))
        } else {
            Text(Format.span(model.now, model.now.addingTimeInterval(TimeInterval(model.dialMinutes * 60))))
        }
    }
}

/// The first unchecked step of the task Now is about. Clicking ticks it off and brings up the next.
private struct CurrentStep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: TaskRow

    private var current: Int? { row.steps.firstIndex { !$0.done } }

    var body: some View {
        Group {
            if let index = current {
                let step = row.steps[index]
                let position = "\(index + 1) of \(row.steps.count)"
                Button {
                    model.perform { try model.store.setStep(step.id, done: true) }
                } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "square")
                            .foregroundStyle(.secondary)
                        Text(step.title)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                        Text(position)
                            .font(Typo.meta)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .frame(minHeight: Space.xl)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Mark this step done")
                .accessibilityLabel("Current step: \(step.title), \(position)")
                .accessibilityHint("Marks this step done")
            } else {
                HStack(spacing: Space.sm) {
                    Image(systemName: "checkmark.square.fill")
                        .foregroundStyle(row.category.color)
                    Text("All \(row.steps.count) steps done")
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: Space.xl)
                .accessibilityElement(children: .combine)
            }
        }
        .font(Typo.body)
        .frame(maxWidth: 360)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: current)
    }
}

private struct Controls: View {
    @Environment(AppModel.self) private var model
    let state: NowState

    var body: some View {
        GlassEffectContainer(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                switch state {
                case .focus(let running, _):
                    Button("+5") { model.extend(5) }
                        .buttonStyle(.glass)
                        .help("Add 5 minutes (⌘+)")
                    Button { model.togglePause() } label: {
                        Label(running.isPaused ? "Resume" : "Pause",
                              systemImage: running.isPaused ? "play.fill" : "pause.fill")
                            .frame(minWidth: 96)
                    }
                    .buttonStyle(.primary(model.accent))
                    .help(running.isPaused ? "Resume (⇧⌘P)" : "Pause (⇧⌘P)")
                    Button("Finish") { model.finishEarly() }
                        .buttonStyle(.glass)
                        .help("Reflect on this block (⇧⌘Return)")
                case .rest(_, let next):
                    Button("End break") { model.stop() }
                        .buttonStyle(.glass)
                    if let next {
                        Button { model.start(next) } label: {
                            Label("Start next", systemImage: "play.fill")
                        }
                        .buttonStyle(.primary(next.category.color))
                        .help("Start \(next.task.title)")
                    }
                case .ready:
                    Button { model.start() } label: {
                        Label("Start", systemImage: "play.fill").frame(minWidth: 112)
                    }
                    .buttonStyle(.primary(model.accent))
                    .help("Start focus (⌘Return)")
                case .empty:
                    Button { model.requestQuickAdd(on: .today) } label: {
                        Label("Add Task", systemImage: "plus").frame(minWidth: 112)
                    }
                    .buttonStyle(.primary(Theme.idle))
                    .help("Add a task (⌘N)")
                case .allDone:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: Tasks

/// Today in the tasks pane: the day's summary, its tasks and a field to add one.
/// Cards drag by their title row; the order is the day's priority.
struct TodayList: View {
    @Environment(AppModel.self) private var model
    /// The card whose title row is being dragged, as its drag session reports it.
    @State private var draggingTaskId: String?
    /// The gap that card would drop into while it is over the list.
    @State private var dropGap: Int?
    @State private var cardFrames: [String: CGRect] = [:]
    private nonisolated static let space = "today-list"

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
        .focusedSceneValue(\.todayList, true)
    }

    private var summary: String {
        let date = model.snapshot.day.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return ([date] + model.dayProgress).joined(separator: " · ")
    }

    private var list: some View {
        let rows = model.todayRows
        return GlassEffectContainer(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.sm) {
                if let summary = model.snapshot.draftSummary {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(summary).font(Typo.body)
                        Text("Review each task. Edit its title or block, drag to reorder, or drop it from the menu. Commit when ready. Starting focus also commits this draft.")
                            .font(Typo.meta)
                            .foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                    .padding(.bottom, Space.sm)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    TodayTaskCard(row: row, index: index, count: rows.count, dragging: $draggingTaskId)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                            cardFrames[row.id] = $0
                        }
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
                if !model.carryover.isEmpty { CarryoverReview() }
            }
            .coordinateSpace(.named(Self.space))
            .overlay(alignment: .topLeading) { insertionMark(rows.map(\.id)) }
            // Present only while a Today card is in flight: a drop target here at any other time
            // would hide the Tasks pane's own drop target from pane drags.
            .overlay { if draggingTaskId != nil { dropZone } }
        }
        .onChange(of: rows.map(\.id)) { _, ids in
            cardFrames = cardFrames.filter { ids.contains($0.key) }
            if let id = draggingTaskId, !ids.contains(id) {
                draggingTaskId = nil
                dropGap = nil
            }
        }
    }

    private func gap(at y: CGFloat) -> Int {
        TodayOrder.gap(at: y, ids: model.todayRows.map(\.id), frames: cardFrames)
    }

    /// Covers the cards, quick add and the note, above any text field, so a card can't drop into one.
    private var dropZone: some View {
        Color.clear
            .contentShape(.rect)
            .dropDestination(for: TodayTaskDrag.self) { items, session in
                defer { dropGap = nil }
                guard items.count == 1, let id = items.first?.taskId else { return }
                model.moveTodayTask(id, toGap: gap(at: session.location.y))
            }
            .dropConfiguration { _ in DropConfiguration(operation: .move) }
            .onDropSessionUpdated { session in
                switch session.phase {
                case .entering, .active: dropGap = gap(at: session.location.y)
                default: dropGap = nil
                }
            }
            .allowsHitTesting(false)
    }

    /// A neutral line in the gap the card would land in, shown only where the order would change.
    @ViewBuilder private func insertionMark(_ ids: [String]) -> some View {
        let frames = ids.compactMap { cardFrames[$0] }
        if let id = draggingTaskId, let gap = dropGap, frames.count == ids.count, let first = frames.first,
           TodayOrder.destination(of: id, gap: gap, in: ids) != nil {
            let y = gap == 0 ? first.minY - Space.xs
                : gap >= frames.count ? frames[frames.count - 1].maxY + Space.xs
                : (frames[gap - 1].maxY + frames[gap].minY) / 2
            Capsule()
                .fill(.primary.opacity(0.5))
                .frame(width: first.width - 2 * Space.md, height: 2)
                .offset(x: first.minX + Space.md, y: y - 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct TodayTaskCard: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    let index: Int
    let count: Int
    let dragging: Binding<String?>
    @State private var editing = false

    private var isRunning: Bool { model.running?.taskId == row.id }
    private var isSelected: Bool { model.running == nil && model.selectedTask?.id == row.id }

    var body: some View {
        TaskCard(row: row, running: isRunning, selected: isSelected,
                 expanded: isRunning || isSelected || model.expandedTaskId == row.id,
                 onTap: {
                     if row.task.status.isOpen && model.running == nil { model.select(row) }
                     else { model.toggleExpanded(row) }
                 },
                 reorder: CardReorder(dragging: dragging,
                                      moveUp: index > 0 ? { model.moveTodayTask(row.id, by: -1) } : nil,
                                      moveDown: index < count - 1 ? { model.moveTodayTask(row.id, by: 1) } : nil)) {
            TaskDurationLabel(row: row)
            Button { editing = true } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .help("Edit task")
                .accessibilityLabel("Edit \(row.task.title)")
            Menu { actions } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Actions for \(row.task.title)")
        }
        .sheet(isPresented: $editing) { TaskEditor(row: row) }
        .contextMenu { actions }
        .focusedValue(\.todayFocus, .card(row.id))
    }

    @ViewBuilder private var actions: some View {
        TaskMenuItems(row: row)
        Divider()
        Button("Move Up") { model.moveTodayTask(row.id, by: -1) }.disabled(index == 0)
        Button("Move Down") { model.moveTodayTask(row.id, by: 1) }.disabled(index == count - 1)
    }
}

private struct TaskDurationLabel: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow

    var body: some View {
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

private struct CarryoverReview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Unfinished from earlier days").font(Typo.heading)
            Text("Accept adds a copy to today and keeps the earlier record. Dismiss drops the earlier task. Nothing moves until you choose.")
                .font(Typo.meta)
                .foregroundStyle(.secondary)
            ForEach(model.carryover) { row in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(row.task.title).font(Typo.body)
                    TaskDetailLine(row: row)
                    HStack {
                        Text("\(row.task.blockMinutes)m").foregroundStyle(.secondary)
                        Spacer()
                        Button("Dismiss") { model.perform { try model.store.setTaskStatus(row.id, .dropped) } }
                            .help("Drop \(row.task.title) on its original day")
                        Button("Accept today") { model.perform { try model.store.carryTask(row.id, to: model.snapshot.day) } }
                            .disabled(model.snapshot.activeTaskCount >= Rules.maxTasks || model.running?.taskId == row.id)
                    }
                    .font(Typo.body)
                }
                .padding(Space.sm)
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
            }
        }
        .padding(.top, Space.md)
    }
}
