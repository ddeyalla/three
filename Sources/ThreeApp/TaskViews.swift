import SwiftUI
import ThreeCore

/// One task as a glass card: completion circle, title, a quiet detail line, and its steps when open.
struct TaskCard<Trailing: View>: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    var running = false
    var selected = false
    /// Shows steps and notes in place.
    var expanded = false
    /// Runs when the title row is clicked. Steps and notes below it stay clickable on their own.
    var onTap: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    private var isClosed: Bool { !row.task.status.isOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CompletionButton(row: row)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.task.title)
                        .font(.body.weight(running || selected ? .medium : .regular))
                        .foregroundStyle(isClosed ? .secondary : .primary)
                        .lineLimit(1)
                    detail
                }
                Spacer(minLength: 8)
                trailing
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
            .onTapGesture(perform: onTap)
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    StepList(row: row)
                    NotesField(row: row)
                }
                .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(.rect(cornerRadius: 14))
        .glassEffect(glass, in: .rect(cornerRadius: 14))
        .opacity(isClosed ? 0.7 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected || running ? .isSelected : [])
    }

    private var glass: Glass {
        if running { return .regular.tint(row.category.color.opacity(0.3)).interactive() }
        if selected { return .regular.tint(.white.opacity(0.08)).interactive() }
        return .regular.interactive()
    }

    private var detail: some View {
        HStack(spacing: 6) {
            Circle().fill(row.category.color).frame(width: 6, height: 6)
            Text(row.category.name)
            if !row.steps.isEmpty {
                Text("·")
                Label("\(row.steps.filter(\.done).count)/\(row.steps.count)", systemImage: "checklist")
                    .labelStyle(.titleAndIcon)
            }
            if !row.task.notes.isEmpty {
                Image(systemName: "text.alignleft").accessibilityLabel("Has notes")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

/// The one way to mark a task done, or undo it.
struct CompletionButton: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow

    private var isDone: Bool { row.task.status == .done }

    var body: some View {
        Button {
            model.perform { try model.store.setTaskStatus(row.id, isDone ? .todo : .done) }
        } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(row.task.status == .carried ? AnyShapeStyle(.tertiary) : AnyShapeStyle(row.category.color))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(row.task.status == .carried)
        .help(isDone ? "Mark not done" : model.running?.taskId == row.id ? "Mark done and end this block" : "Mark done")
        .accessibilityLabel(isDone ? "Done" : "Not done")
    }
}

/// A task's checklist, with a field to add the next step.
struct StepList: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    @State private var draft = ""
    @State private var adding = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(row.steps) { step in
                HStack(spacing: 8) {
                    Button {
                        model.perform { try model.store.setStep(step.id, done: !step.done) }
                    } label: {
                        Image(systemName: step.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(step.done ? AnyShapeStyle(row.category.color) : AnyShapeStyle(.secondary))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    Text(step.title)
                        .foregroundStyle(step.done ? .secondary : .primary)
                        .strikethrough(step.done, color: .secondary)
                        .lineLimit(2)
                }
                .contextMenu {
                    Button("Delete step", role: .destructive) { model.perform { try model.store.removeStep(step.id) } }
                }
            }
            // A button first, so opening a card never drops a cursor into it.
            if adding {
                HStack(spacing: 8) {
                    Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 14)
                    TextField("Next small step", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onAppear { focused = true }
                        .onSubmit(add)
                        .onExitCommand { adding = false; draft = "" }
                }
            } else {
                Button {
                    adding = true
                } label: {
                    Label(row.steps.isEmpty ? "Break it down" : "Add a step", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .onChange(of: focused) { if !focused && draft.isEmpty { adding = false } }
    }

    private func add() {
        let title = draft
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { adding = false; return }
        model.perform { try model.store.addStep(to: row.id, title: title) }
        if model.error == nil { draft = ""; focused = true }
    }
}

/// Todoist-style quick add: "Call the bank #admin 15m tomorrow". Shows what it understood as you type.
struct QuickAddField: View {
    @Environment(AppModel.self) private var model
    let defaultDay: DayKey?
    var placeholder = "Add a task"
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: QuickAdd {
        QuickAdd.parse(text, categories: model.liveCategories.map(\.name), today: model.snapshot.day)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    if model.capture(text, defaultDay: defaultDay) { text = "" }
                }
            if !text.isEmpty { preview }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .glassEffect(.regular.tint(.white.opacity(focused ? 0.06 : 0)).interactive(), in: .rect(cornerRadius: 14))
        .help("#category, a duration like 45m, and today, tomorrow, a weekday or inbox")
        .onChange(of: model.quickAddRequest) { claimQuickAdd() }
        .onAppear { claimQuickAdd() }
    }

    /// ⌘N may switch views first, so a field that appears afterwards still takes the request.
    private func claimQuickAdd() {
        guard model.quickAddPending else { return }
        model.quickAddPending = false
        DispatchQueue.main.async { focused = true }
    }

    private var preview: some View {
        let category = model.liveCategories.first { $0.name == parsed.category } ?? model.liveCategories.first
        let minutes = parsed.minutes ?? model.snapshot.preferences.defaultBlockMinutes
        return HStack(spacing: 8) {
            Text(parsed.title.isEmpty ? "No title yet" : parsed.title)
                .lineLimit(1)
                .foregroundStyle(parsed.title.isEmpty ? AnyShapeStyle(Theme.overrun) : AnyShapeStyle(.secondary))
            HStack(spacing: 4) {
                Circle().fill(category?.color ?? Theme.idle).frame(width: 6, height: 6)
                Text(category?.name ?? "")
            }
            Text("\(minutes)m")
            Text(whenLabel)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private var whenLabel: String {
        switch parsed.when {
        case .day(let d)?: Format.dayName(d, today: model.snapshot.day)
        case .inbox?: "Inbox"
        case nil: defaultDay.map { Format.dayName($0, today: model.snapshot.day) } ?? "Inbox"
        }
    }
}

/// Today, Tomorrow, the rest of the week, or back to the inbox.
struct ScheduleMenuItems: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow

    var body: some View {
        let today = model.snapshot.day
        ForEach(0..<7, id: \.self) { offset in
            let day = today.adding(days: offset)
            Button(Format.dayName(day, today: today)) { model.schedule(row, on: day) }
                .disabled(model.day(of: row.id) == day)
        }
        Divider()
        Button("Inbox") { model.schedule(row, on: nil) }
            .disabled(model.day(of: row.id) == nil && model.inbox.contains { $0.id == row.id })
    }
}

/// Edit menu items shared by every task card.
struct TaskMenuItems: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow

    var body: some View {
        if row.task.status.isOpen, model.day(of: row.id) == model.snapshot.day {
            Button("Start now") { model.start(row) }.disabled(model.running?.kind == .focus)
        }
        if row.task.status.isOpen || row.task.status == .dropped {
            Menu("Schedule") { ScheduleMenuItems(row: row) }
        }
        Menu("Block") {
            ForEach([15, 25, 30, 45, 60, 90, 120], id: \.self) { m in
                Button("\(m) min") { model.perform { try model.store.updateTask(row.id, blockMinutes: m) } }
            }
        }
        Menu("Category") {
            ForEach(model.liveCategories) { c in
                Button(c.name) { model.perform { try model.store.updateTask(row.id, category: c.id) } }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.perform { try model.store.removeTask(row.id) } }
    }
}

/// Notes in place, saved shortly after you stop typing.
struct NotesField: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    @State private var text = ""
    @State private var save: Task<Void, Never>?

    var body: some View {
        TextField("Notes", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1...8)
            .onAppear { text = row.task.notes }
            .onChange(of: row.id) { text = row.task.notes }
            .onChange(of: text) {
                save?.cancel()
                let value = text, id = row.id
                guard value != row.task.notes else { return }
                save = Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    model.perform { try model.store.updateTask(id, notes: value) }
                }
            }
    }
}

/// The last thing that went wrong, with a way to wave it off. Shown wherever an action can fail.
struct ErrorNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let error = model.error {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.overrun)
                Text(error).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { model.error = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
            }
            .font(.callout)
        }
    }
}
