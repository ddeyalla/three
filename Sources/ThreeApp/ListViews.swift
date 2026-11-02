import SwiftUI
import ThreeCore

/// Title, subtitle, then content in a centred reading column, Todoist-width.
struct ListPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.largeTitle.weight(.bold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                content
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

/// A card in Inbox, Upcoming or a category list: click for details, hover for quick scheduling.
struct ListTaskCard: View {
    @Environment(AppModel.self) private var model
    let row: TaskRow
    @State private var hovering = false

    var body: some View {
        TaskCard(row: row, selected: model.expandedTaskId == row.id, expanded: model.expandedTaskId == row.id,
                 onTap: { model.toggleExpanded(row) }) {
            HStack(spacing: 10) {
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
                Text("\(row.task.blockMinutes)m")
            }
            .buttonStyle(.plain)
        }
        .onHover { hovering = $0 }
        .contextMenu { TaskMenuItems(row: row) }
    }
}

struct InboxView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ListPage(title: "Inbox", subtitle: subtitle) {
            GlassEffectContainer(spacing: 6) {
                VStack(spacing: 6) {
                    QuickAddField(defaultDay: nil, placeholder: "Capture anything. Plan it later.")
                    ForEach(model.inbox) { ListTaskCard(row: $0) }
                }
            }
            if model.inbox.isEmpty {
                Text("Nothing waiting. Ideas, errands and someday tasks land here until you give them a day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        model.inbox.isEmpty ? "Clear" : "\(model.inbox.count) waiting · \(Format.duration(TimeInterval(model.inbox.reduce(0) { $0 + $1.task.blockMinutes } * 60)))"
    }
}

struct UpcomingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ListPage(title: "Upcoming", subtitle: "The next seven days") {
            QuickAddField(defaultDay: model.snapshot.day.adding(days: 1), placeholder: "Plan ahead: \"Review PR #coding 30m wed\"")
            ForEach(model.upcoming, id: \.day) { day in
                DaySection(snapshot: day)
            }
        }
    }
}

private struct DaySection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DaySnapshot

    private var rows: [TaskRow] { snapshot.tasks.filter { $0.task.status != .dropped } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.day == model.snapshot.day.adding(days: 1)
                     ? "Tomorrow" : snapshot.day.startDate.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(snapshot.day.startDate.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if !rows.isEmpty {
                    Text("\(rows.count) of \(Rules.idealTasks) · \(Format.duration(TimeInterval(snapshot.plannedMinutes * 60)))")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(rows.count > Rules.idealTasks ? AnyShapeStyle(Theme.overrun) : AnyShapeStyle(.secondary))
                }
            }
            if rows.isEmpty {
                Text("Nothing planned")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                GlassEffectContainer(spacing: 6) {
                    VStack(spacing: 6) {
                        ForEach(rows) { ListTaskCard(row: $0) }
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

/// Everything open in one category: today, the week ahead, and the inbox.
struct CategoryView: View {
    @Environment(AppModel.self) private var model
    let categoryId: String

    var body: some View {
        let category = model.snapshot.categories.first { $0.id == categoryId }
        let today = model.snapshot.tasks.filter { $0.category.id == categoryId && $0.task.status != .dropped }
        let ahead = model.upcoming.flatMap(\.tasks).filter { $0.category.id == categoryId && $0.task.status.isOpen }
        let inbox = model.inbox.filter { $0.category.id == categoryId }
        ListPage(title: category?.name ?? "Category", subtitle: (today.count + ahead.count + inbox.count) == 1 ? "1 task" : "\(today.count + ahead.count + inbox.count) tasks") {
            group("Today", today)
            group("Upcoming", ahead)
            group("Inbox", inbox)
            if today.isEmpty && ahead.isEmpty && inbox.isEmpty {
                Text("No tasks in this category yet. Add one with #\(category?.name.lowercased().replacingOccurrences(of: " ", with: "") ?? "").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func group(_ title: String, _ rows: [TaskRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                GlassEffectContainer(spacing: 6) {
                    VStack(spacing: 6) { ForEach(rows) { ListTaskCard(row: $0) } }
                }
            }
        }
    }
}
