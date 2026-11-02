import SwiftUI
import ThreeCore

/// A list in the tasks pane: a one-line summary with an optional control, then the content, scrolling.
struct PaneList<Accessory: View, Content: View>: View {
    let subtitle: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .center, spacing: Space.sm) {
                    Text(subtitle)
                        .font(Typo.body)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    accessory
                }
                .frame(minHeight: 22)
                content
            }
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.never)
    }
}

extension PaneList where Accessory == EmptyView {
    init(subtitle: String, @ViewBuilder content: () -> Content) {
        self.init(subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

/// Quiet guidance where a list is empty.
private struct EmptyNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Typo.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.xs)
    }
}

/// A card in Inbox, Upcoming or Done: click for details, hover for quick scheduling.
struct ListTaskCard: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    @State private var hovering = false

    var body: some View {
        TaskCard(row: row, selected: model.expandedTaskId == row.id, expanded: model.expandedTaskId == row.id,
                 onTap: { model.toggleExpanded(row) }) {
            HStack(spacing: Space.md) {
                if hovering, row.task.status.isOpen {
                    let today = model.snapshot.day
                    if model.day(of: row.id) != today {
                        Button { model.schedule(row, on: today) } label: { Image(systemName: "sun.max") }
                            .help("Do it today")
                    }
                    if model.day(of: row.id) != today.adding(days: 1) {
                        Button { model.schedule(row, on: today.adding(days: 1)) } label: { Image(systemName: "sunrise") }
                            .help("Tomorrow")
                    }
                }
                Text(row.task.status == .done ? Format.duration(row.focusedSeconds) : "\(row.task.blockMinutes)m")
            }
            .buttonStyle(.plain)
        }
        .onHover { hovering = $0 }
        .contextMenu { TaskMenuItems(row: row) }
    }
}

private struct Cards: View {
    let rows: [TaskRow]

    var body: some View {
        GlassEffectContainer(spacing: Space.sm) {
            VStack(spacing: Space.sm) { ForEach(rows) { ListTaskCard(row: $0) } }
        }
    }
}

struct InboxList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PaneList(subtitle: subtitle) {
            QuickAddField(defaultDay: nil, placeholder: "Capture anything")
            if model.inbox.isEmpty {
                EmptyNote("Nothing waiting. Ideas, errands and someday tasks land here until you give them a day.")
            } else {
                Cards(rows: model.inbox)
            }
        }
    }

    private var subtitle: String {
        model.inbox.isEmpty ? "Clear" : "\(model.inbox.count) waiting · \(Format.duration(TimeInterval(model.inbox.reduce(0) { $0 + $1.task.blockMinutes } * 60)))"
    }
}

struct UpcomingList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PaneList(subtitle: "The next seven days") {
            QuickAddField(defaultDay: model.snapshot.day.adding(days: 1), placeholder: "Plan ahead: \"Review PR wed\"")
            ForEach(model.upcoming, id: \.day) { day in
                DaySection(snapshot: day)
                    .padding(.top, Space.sm)
            }
        }
    }
}

private struct DaySection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DaySnapshot

    private var rows: [TaskRow] { snapshot.tasks.filter { $0.task.status != .dropped } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(snapshot.day == model.snapshot.day.adding(days: 1)
                     ? "Tomorrow" : snapshot.day.startDate.formatted(.dateTime.weekday(.wide)))
                    .font(Typo.heading)
                Text(snapshot.day.startDate.formatted(.dateTime.day().month(.abbreviated)))
                    .font(Typo.body)
                    .foregroundStyle(.secondary)
                Spacer()
                if !rows.isEmpty {
                    Text("\(rows.count) of \(Rules.idealTasks) · \(Format.duration(TimeInterval(snapshot.plannedMinutes * 60)))")
                        .font(Typo.body)
                        .monospacedDigit()
                        .foregroundStyle(rows.count > Rules.idealTasks ? AnyShapeStyle(Theme.overrun) : AnyShapeStyle(.secondary))
                }
            }
            if rows.isEmpty {
                Text("Nothing planned")
                    .font(Typo.body)
                    .foregroundStyle(.tertiary)
            } else {
                Cards(rows: rows)
            }
        }
    }
}

/// Finished tasks from the last 30 days, by the day you finished them.
struct DoneList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.logbook.reduce(0) { $0 + $1.tasks.count }
        PaneList(subtitle: count == 0 ? "The last 30 days" : "\(count) done in the last 30 days") {
            if model.logbook.isEmpty {
                EmptyNote("Tick a task's circle when it's done and it lands here, with the time it took.")
            }
            ForEach(model.logbook, id: \.day) { day in
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.dayName(day.day, today: model.snapshot.day)).font(Typo.heading)
                        Spacer()
                        Text(Format.duration(day.tasks.reduce(0) { $0 + $1.focusedSeconds }))
                            .font(Typo.body)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Cards(rows: day.tasks)
                }
                .padding(.top, Space.sm)
            }
        }
    }
}

/// Every tag with the focus time it has collected, most recently worked first.
struct TagsList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PaneList(subtitle: model.tagSummaries.isEmpty ? "Time spent on each thread of work" : "Time spent, all time") {
            if model.tagSummaries.isEmpty {
                EmptyNote("Tag a product, project or feature with @name in quick add, like \"Fix signup @onboarding\". Each tag adds up its focus time across days and weeks.")
            } else {
                GlassEffectContainer(spacing: Space.sm) {
                    VStack(spacing: Space.sm) {
                        ForEach(model.tagSummaries) { TagCard(summary: $0) }
                    }
                }
            }
        }
    }
}

private struct TagCard: View {
    @Environment(AppModel.self) private var model
    let summary: TagSummary

    private var expanded: Bool { model.expandedTaskId == summary.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.hairline) {
                    Text("@\(summary.tag.name)")
                        .font(Typo.body)
                        .lineLimit(1)
                    Text(detail)
                        .font(Typo.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.sm)
                Text(Format.duration(summary.seconds))
                    .font(Typo.body)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
            .onTapGesture { model.expandedTaskId = expanded ? nil : summary.id }
            if expanded {
                VStack(alignment: .leading, spacing: Space.xs + Space.hairline) {
                    ForEach(summary.work) { w in
                        HStack(spacing: Space.sm) {
                            Image(systemName: w.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                            Text(w.title)
                                .foregroundStyle(w.done ? .secondary : .primary)
                                .lineLimit(1)
                            Spacer(minLength: Space.sm)
                            Text(Format.duration(w.seconds))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(Typo.body)
                .padding(.bottom, Space.xs)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .contentShape(.rect(cornerRadius: Radius.card))
        .glassEffect(expanded ? .regular.tint(.white.opacity(0.08)).interactive() : .regular.interactive(), in: .rect(cornerRadius: Radius.card))
        .contextMenu {
            Button("Archive") { model.perform { try model.store.updateTag(summary.tag.id, archived: true) } }
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        var parts = [summary.daysWorked == 1 ? "1 day" : "\(summary.daysWorked) days"]
        if summary.recentSeconds >= 60 { parts.append("\(Format.duration(summary.recentSeconds)) past week") }
        return parts.joined(separator: " · ")
    }
}
