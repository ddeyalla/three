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
    /// Set on an ordered list: the title row becomes a drag handle and VoiceOver gets the moves.
    var reorder: CardReorder?
    @ViewBuilder var trailing: Trailing

    private var isClosed: Bool { !row.task.status.isOpen }
    private var isTravelling: Bool { reorder?.dragging.wrappedValue == row.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.md) {
                CompletionButton(row: row)
                Button(action: onTap) {
                    VStack(alignment: .leading, spacing: Space.hairline) {
                        Text(row.task.title)
                            .font(Typo.body)
                            .foregroundStyle(isClosed ? .secondary : .primary)
                            .lineLimit(1)
                        TaskDetailLine(row: row)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(row.task.title)
                .accessibilityLabel(row.task.title)
                .accessibilityValue(expanded ? "Details expanded" : "Details collapsed")
                .accessibilityActions {
                    if let up = reorder?.moveUp { Button("Move Up", action: up) }
                    if let down = reorder?.moveDown { Button("Move Down", action: down) }
                }
                trailing
                    .font(Typo.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .modifier(CardDragSource(row: row, reorder: reorder) { dragPreview })
            if expanded {
                VStack(alignment: .leading, spacing: Space.sm) {
                    StepList(row: row)
                    TagAdder(row: row)
                    NotesField(row: row)
                }
                .padding(.leading, Space.xl + Space.md)
                .padding(.bottom, Space.xs)
            }
        }
        // Inside the glass: a GlassEffectContainer ignores opacity applied to the card from outside.
        .opacity(isTravelling ? 0.5 : 1)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .contentShape(.rect(cornerRadius: Radius.card))
        .glassEffect(glass, in: .rect(cornerRadius: Radius.card))
        .opacity(isClosed ? 0.7 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected || running ? .isSelected : [])
    }

    /// The collapsed title row, even when the card is open.
    private var dragPreview: some View {
        HStack(spacing: Space.md) {
            Image(systemName: row.task.status == .done ? "checkmark.circle.fill" : "circle")
                .imageScale(.large)
                .foregroundStyle(row.category.color)
            Text(row.task.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(Typo.body)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(width: 288)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
    }

    private var glass: Glass {
        if running { return .regular.tint(row.category.color.opacity(0.3)).interactive() }
        if selected { return .regular.tint(.white.opacity(0.08)).interactive() }
        return .regular.interactive()
    }
}

/// What a card on an ordered list needs: where to report that it is being dragged, and its menu moves.
struct CardReorder {
    var dragging: Binding<String?>
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
}

/// Makes a title row the drag handle for its card. The list reads `dragging` to know a card is in flight.
private struct CardDragSource<Preview: View>: ViewModifier {
    let row: TaskRow
    let reorder: CardReorder?
    @ViewBuilder var preview: () -> Preview

    func body(content: Content) -> some View {
        if let reorder {
            content
                .draggable(TodayTaskDrag(taskId: row.id), preview: preview)
                .dragConfiguration(.init(operationsWithinApp: .init(allowCopy: false, allowMove: true),
                                         operationsOutsideApp: .init(allowCopy: false)))
                .onDragSessionUpdated { session in
                    switch session.phase {
                    case .initial, .active:
                        if reorder.dragging.wrappedValue != row.id { reorder.dragging.wrappedValue = row.id }
                    case .ended:
                        if reorder.dragging.wrappedValue == row.id { reorder.dragging.wrappedValue = nil }
                    default:
                        break
                    }
                }
        } else {
            content
        }
    }
}

/// The quiet line under a task: category, tags, step count, and whether it has notes.
struct TaskDetailLine: View {
    let row: TaskRow

    /// In a narrow card the step count and notes mark give way first, then the tags.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(tags: true, extras: true)
            line(tags: true, extras: false)
            line(tags: false, extras: false)
        }
        .font(Typo.meta)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }

    private func line(tags: Bool, extras: Bool) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(row.category.color).frame(width: 6, height: 6)
            Text(row.category.name)
            if tags { ForEach(row.tags) { Text("@\($0.name)") } }
            if extras, !row.steps.isEmpty {
                Text("·")
                Label("\(row.steps.filter(\.done).count)/\(row.steps.count)", systemImage: "checklist")
                    .labelStyle(.titleAndIcon)
            }
            if extras, !row.task.notes.isEmpty {
                Image(systemName: "text.alignleft").accessibilityLabel("Has notes")
            }
        }
        .fixedSize(horizontal: tags, vertical: true)
    }
}

/// Pick one, as a row of glass capsules each sized to its label. The chosen one lightens and its text turns primary;
/// none of them is a prominent button. Used for the reflection panel's answers and for switching the tasks pane.
struct ChoiceCapsules<Value: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    struct Option: Identifiable {
        var value: Value
        var title: String
        /// Shown instead of the title, which stays as the accessibility label.
        var symbol: String?
        var id: Value { value }

        init(_ value: Value, _ title: String, symbol: String? = nil) {
            self.value = value
            self.title = title
            self.symbol = symbol
        }
    }

    @Binding var selection: Value
    let options: [Option]

    var body: some View {
        GlassEffectContainer(spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                ForEach(options) { option in
                    let chosen = selection == option.value
                    Button { selection = option.value } label: {
                        Group {
                            if let symbol = option.symbol {
                                Image(systemName: symbol).accessibilityLabel(option.title)
                            } else {
                                Text(option.title)
                            }
                        }
                        .font(Typo.body)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .monospacedDigit()
                        .foregroundStyle(chosen ? .primary : .secondary)
                        .padding(.horizontal, option.symbol == nil ? Space.md : 0)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(chosen ? .regular.tint(.white.opacity(0.15)).interactive() : .regular.interactive(), in: .capsule)
                    .help(option.symbol == nil ? "" : option.title)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selection)
    }
}

/// The one way to mark a task done, or undo it.
struct CompletionButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: TaskRow

    private var isDone: Bool { row.task.status == .done }

    var body: some View {
        Button {
            model.perform { try model.store.setTaskStatus(row.id, isDone ? .todo : .done) }
        } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(Typo.body)
                .imageScale(.large)
                .foregroundStyle(row.task.status == .carried ? AnyShapeStyle(.tertiary) : AnyShapeStyle(row.category.color))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .frame(width: Space.xl, height: Space.xl)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(row.task.status == .carried)
        .help(isDone ? "Mark not done" : model.running?.taskId == row.id ? "Mark done and end this block" : "Mark done")
        .accessibilityLabel("\(isDone ? "Mark not done" : "Mark done"): \(row.task.title)")
    }
}

/// A task's checklist, with a field to add the next step.
struct StepList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: TaskRow
    @State private var draft = ""
    @State private var adding = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs + 2) {
            ForEach(row.steps) { step in
                Button {
                    model.perform { try model.store.setStep(step.id, done: !step.done) }
                } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: step.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(step.done ? AnyShapeStyle(row.category.color) : AnyShapeStyle(.secondary))
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        Text(step.title)
                            .foregroundStyle(step.done ? .secondary : .primary)
                            .strikethrough(step.done, color: .secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: Space.xl, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(step.title)
                .accessibilityValue(step.done ? "Done" : "Not done")
                .contextMenu {
                    Button("Delete step", role: .destructive) { model.perform { try model.store.removeStep(step.id) } }
                }
            }
            // A button first, so opening a card never drops a cursor into it.
            if adding {
                HStack(spacing: Space.sm) {
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
        .font(Typo.body)
        .onChange(of: focused) { if !focused && draft.isEmpty { adding = false } }
    }

    private func add() {
        let title = draft
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { adding = false; return }
        model.perform { try model.store.addStep(to: row.id, title: title) }
        if model.error == nil { draft = ""; focused = true }
    }
}

/// "Add a tag" until clicked, then a field: type one or more names, with or without "@".
struct TagAdder: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    @State private var draft = ""
    @State private var adding = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if adding {
                HStack(spacing: Space.sm) {
                    Image(systemName: "number").foregroundStyle(.secondary).frame(width: 14)
                    TextField("onboarding, launch", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onAppear { focused = true }
                        .onSubmit(add)
                        .onExitCommand { adding = false; draft = "" }
                }
            } else {
                Button { adding = true } label: {
                    Label(row.tags.isEmpty ? "Add a tag" : "Add another tag", systemImage: "number")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Tags group work across days, like a product or a feature, and add up its time")
            }
        }
        .font(Typo.body)
        .onChange(of: focused) { if !focused && draft.isEmpty { adding = false } }
    }

    private func add() {
        let names = draft.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        guard !names.isEmpty else { adding = false; return }
        model.perform { for name in names { try model.store.addTag(name, to: row.id) } }
        if model.error == nil { draft = ""; adding = false }
    }
}

/// Todoist-style quick add: "Call the bank #admin 15m tomorrow". Shows what it understood as you type.
struct QuickAddField: View {
    @Environment(AppModel.self) private var model
    let defaultDay: DayKey?
    var placeholder = "Add a task"
    var claimsKeyboardShortcut = true
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: QuickAdd {
        QuickAdd.parse(text, categories: model.liveCategories.map(\.name), today: model.snapshot.day)
    }

    /// What it understood sits on its own line under the field, so a narrow pane never squeezes what you type.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.md) {
                Image(systemName: "plus")
                    .font(Typo.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        if model.capture(text, defaultDay: defaultDay) { text = "" }
                    }
            }
            .frame(height: 36)
            if !text.isEmpty {
                preview
                    .padding(.leading, 18 + Space.md)
                    .padding(.bottom, Space.sm)
            }
        }
        .font(Typo.body)
        .padding(.horizontal, Space.md)
        .glassEffect(.regular.tint(.white.opacity(focused ? 0.06 : 0)).interactive(), in: .rect(cornerRadius: Radius.card))
        .focusedValue(\.todayFocus, .entry)
        .help("#category, @tag, a duration like 45m, and today, tomorrow, a weekday or inbox")
        .onChange(of: model.quickAddRequest) { claimQuickAdd() }
        .onAppear { claimQuickAdd() }
    }

    /// ⌘N may switch views first, so a field that appears afterwards still takes the request.
    private func claimQuickAdd() {
        guard claimsKeyboardShortcut, model.quickAddPending else { return }
        model.quickAddPending = false
        DispatchQueue.main.async { focused = true }
    }

    private var preview: some View {
        let category = model.liveCategories.first { $0.name == parsed.category } ?? model.liveCategories.first
        let minutes = parsed.minutes ?? model.snapshot.preferences.defaultBlockMinutes
        return HStack(spacing: Space.sm) {
            if parsed.title.isEmpty {
                Text("No title yet").foregroundStyle(Theme.overrun)
            }
            HStack(spacing: Space.xs) {
                Circle().fill(category?.color ?? Theme.idle).frame(width: 6, height: 6)
                Text(category?.name ?? "")
            }
            ForEach(parsed.tags, id: \.self) { Text("@\($0)") }
            Spacer(minLength: 0)
            Text("\(minutes)m")
            Text(whenLabel)
        }
        .lineLimit(1)
        .font(Typo.meta)
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
            ForEach([15, 25, 30, 45, 60, 90, 120, 180, 240], id: \.self) { m in
                Button(Format.duration(TimeInterval(m * 60))) { model.perform { try model.store.updateTask(row.id, blockMinutes: m) } }
            }
        }
        Menu("Category") {
            ForEach(model.liveCategories) { c in
                Button(c.name) { model.perform { try model.store.updateTask(row.id, category: c.id) } }
            }
        }
        if !model.liveTags.isEmpty || !row.tags.isEmpty {
            Menu("Tags") {
                ForEach(Array(Set(model.liveTags + row.tags)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { tag in
                    let on = row.tags.contains { $0.id == tag.id }
                    Toggle("@\(tag.name)", isOn: Binding(get: { on }, set: { add in
                        model.perform { add ? try model.store.addTag(tag.name, to: row.id) : try model.store.removeTag(tag.id, from: row.id) }
                    }))
                }
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
            .font(Typo.body)
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
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.overrun)
                Text(error).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.xs)
                Button { model.error = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss error")
            }
            .font(Typo.body)
        }
    }
}
