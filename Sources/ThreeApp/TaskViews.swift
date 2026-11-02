import SwiftUI
import ThreeCore

/// One task as a glass card: completion circle, title, a quiet detail line, and its steps when open.
struct TaskCard<Trailing: View>: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    var running = false
    var selected = false
    var showSteps = false
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
            if showSteps {
                StepList(row: row)
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
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 14)
                TextField(row.steps.isEmpty ? "Break it down: add a first step" : "Add a step", text: $draft)
                    .textFieldStyle(.plain)
                    .onSubmit(add)
            }
        }
        .font(.callout)
    }

    private func add() {
        let title = draft
        model.perform { try model.store.addStep(to: row.id, title: title) }
        if model.error == nil { draft = "" }
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
                    model.capture(text, defaultDay: defaultDay)
                    if model.error == nil { text = "" }
                }
            if !text.isEmpty { preview }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .glassEffect(.regular.tint(.white.opacity(focused ? 0.06 : 0)).interactive(), in: .rect(cornerRadius: 14))
        .help("#category, a duration like 45m, and today, tomorrow, a weekday or inbox")
        .onChange(of: model.quickAddRequest) { focused = true }
    }

    private var preview: some View {
        let category = model.liveCategories.first { $0.name == parsed.category } ?? model.liveCategories.first
        let minutes = parsed.minutes ?? model.snapshot.preferences.defaultBlockMinutes
        return HStack(spacing: 8) {
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
        Button("Show details") { model.inspect(row) }
        if row.task.status.isOpen, model.day(of: row.id) == model.snapshot.day {
            Button("Start now") { model.start(row) }.disabled(model.running?.kind == .focus)
        }
        Menu("Schedule") { ScheduleMenuItems(row: row) }
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

/// The inspector: everything about one task.
struct TaskInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let row = model.task(model.inspectedTaskId) {
            TaskDetail(row: row).id(row.id)
        } else {
            ContentUnavailableView("No task selected", systemImage: "checklist",
                                   description: Text("Select a task to see its steps and notes."))
        }
    }
}

private struct TaskDetail: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    @State private var title = ""
    @State private var notes = ""
    @State private var saveNotes: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.plain)
                    .onSubmit { save(title: title) }
            }
            Section {
                Picker("Category", selection: Binding(
                    get: { row.category.id },
                    set: { id in model.perform { try model.store.updateTask(row.id, category: id) } })) {
                    ForEach(model.liveCategories) { c in
                        Label { Text(c.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(c.color) }.tag(c.id)
                    }
                }
                Picker("Block", selection: Binding(
                    get: { row.task.blockMinutes },
                    set: { m in model.perform { try model.store.updateTask(row.id, blockMinutes: m) } })) {
                    ForEach(Array(Set([15, 25, 30, 45, 60, 90, 120, 180, row.task.blockMinutes])).sorted(), id: \.self) {
                        Text("\($0) min").tag($0)
                    }
                }
                LabeledContent("When") {
                    Menu(whenLabel) { ScheduleMenuItems(row: row) }
                        .fixedSize()
                }
                if row.focusedSeconds >= 60 {
                    LabeledContent("Focused", value: Format.duration(row.focusedSeconds))
                }
            }
            Section("Steps") {
                StepList(row: row)
            }
            Section("Notes") {
                TextField("Links, context, what done looks like", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(4...14)
                    .onChange(of: notes) { scheduleNotesSave() }
            }
            Section {
                if row.task.status.isOpen, model.day(of: row.id) == model.snapshot.day {
                    Button("Start focus") { model.start(row) }
                        .disabled(model.running?.kind == .focus)
                }
                Button("Delete task", role: .destructive) {
                    model.perform { try model.store.removeTask(row.id) }
                    model.inspectedTaskId = nil
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            title = row.task.title
            notes = row.task.notes
        }
        .onDisappear {
            saveNotes?.cancel()
            if notes != row.task.notes { save(notes: notes) }
            if title != row.task.title { save(title: title) }
        }
    }

    private var whenLabel: String {
        model.day(of: row.id).map { Format.dayName($0, today: model.snapshot.day) } ?? "Inbox"
    }

    private func scheduleNotesSave() {
        saveNotes?.cancel()
        let text = notes
        saveNotes = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, text != row.task.notes else { return }
            save(notes: text)
        }
    }

    private func save(title: String? = nil, notes: String? = nil) {
        if let title, title.trimmingCharacters(in: .whitespaces).isEmpty { return }
        model.perform { try model.store.updateTask(row.id, title: title, notes: notes) }
    }
}
