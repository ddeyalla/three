import SwiftUI
import ThreeCore

struct HistoryMonth {
    let calendar: Calendar
    let start: Date
    let from: DayKey
    let through: DayKey
    var key: String { String(from.rawValue.prefix(7)) }

    init?(containing date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return nil }
        self.calendar = calendar
        start = interval.start
        from = DayKey(interval.start, calendar: calendar)
        through = DayKey(last, calendar: calendar)
    }

    func shifted(by amount: Int) -> Date? { calendar.date(byAdding: .month, value: amount, to: start) }

    var title: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: start)
    }
}

/// The History section of the Review sheet: the honest focus record, one month at a time.
/// Days with recorded activity on the left, newest first; the chosen day's tasks and sessions on the right.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var month = Date()
    @State private var selectedDay: DayKey?
    @State private var refresh = 0
    @State private var state = LoadState.loading

    private enum LoadState {
        case loading
        case loaded(HistoryReport)
        case failed(String)
    }

    private struct ReadKey: Equatable {
        let month: String
        let revision: Date
        let refresh: Int
    }

    private var range: HistoryMonth? { HistoryMonth(containing: month) }
    private var monthKey: String { range?.key ?? "unavailable" }
    private var isThisMonth: Bool { HistoryMonth(containing: Date())?.key == monthKey }
    private var readKey: ReadKey { ReadKey(month: monthKey, revision: model.snapshot.takenAt, refresh: refresh) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.md) {
                monthControls
                switch state {
                case .loading:
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed:
                    Spacer()
                case .loaded(let report):
                    monthTotals(report.totals)
                    dayList(report)
                }
            }
            .padding(Space.lg)
            .frame(width: 270)
            .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            Group {
                switch state {
                case .loading: Color.clear
                case .failed(let message):
                    VStack(spacing: Space.md) {
                        Text("History couldn't be read").font(Typo.focus)
                        Text(message).font(Typo.body).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Try Again") { refresh += 1 }
                            .buttonStyle(.glass)
                            .font(Typo.body)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded(let report):
                    detail(report)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: readKey) { await load() }
    }

    private var monthControls: some View {
        HStack(spacing: Space.sm) {
            Button("Previous Month", systemImage: "chevron.left") { moveMonth(-1) }
                .labelStyle(.iconOnly)
            Text(range?.title ?? "Month unavailable")
                .font(Typo.heading)
                .lineLimit(1)
                .monospacedDigit()
            Button("Next Month", systemImage: "chevron.right") { moveMonth(1) }
                .labelStyle(.iconOnly)
                .disabled(isThisMonth)
            Spacer(minLength: 0)
            if !isThisMonth {
                Button("Now") { month = Date() }
                    .font(Typo.body)
                    .help("Back to this month")
            }
        }
        .buttonStyle(.glass)
    }

    private func monthTotals(_ totals: HistoryTotals) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("\(Format.duration(totals.focusSeconds)) focused")
                .font(Typo.title).monospacedDigit()
            Text("\(totals.doneTaskCount) of \(totals.plannedTaskCount) tasks done · \(Format.duration(TimeInterval(totals.plannedSeconds))) planned · \(Format.duration(totals.breakSeconds)) breaks")
                .font(Typo.meta).foregroundStyle(.secondary).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func moveMonth(_ amount: Int) {
        if let next = range?.shifted(by: amount) {
            month = next
        }
    }

    /// Days with any recorded task or session, newest first. Empty days stay out of the list.
    private func activeDays(_ report: HistoryReport) -> [HistoryDay] {
        report.days.filter { !$0.sessions.isEmpty || !$0.tasks.isEmpty }.sorted { $0.day > $1.day }
    }

    @ViewBuilder private func dayList(_ report: HistoryReport) -> some View {
        let days = activeDays(report)
        if days.isEmpty {
            Text(isThisMonth ? "Nothing recorded this month yet." : "Nothing recorded this month.")
                .font(Typo.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Space.sm)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(days) { day in
                        Button {
                            selectedDay = day.day
                        } label: {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                HStack {
                                    Text(historyDayTitle(day.day)).font(Typo.body)
                                    Spacer(minLength: Space.sm)
                                    Text(Format.duration(day.totals.focusSeconds))
                                        .font(Typo.body)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                HistoryCategoryStrip(categories: day.categories)
                            }
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, Space.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                            .background(shownDay(report) == day.day ? Theme.rowFill : .clear,
                                        in: .rect(cornerRadius: Radius.block))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(shownDay(report) == day.day ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// The chosen day, or the most recent day with activity so the detail is never blank.
    private func shownDay(_ report: HistoryReport) -> DayKey? {
        let days = activeDays(report)
        if let selectedDay, days.contains(where: { $0.day == selectedDay }) { return selectedDay }
        return days.first?.day
    }

    @ViewBuilder private func detail(_ report: HistoryReport) -> some View {
        if let day = report.days.first(where: { $0.day == shownDay(report) }) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    // The plan's own status reaches closed days older than the recent summaries the model keeps.
                    HistoryDayDetail(day: day, closed: day.plan?.status == .closed || model.dayCloses.contains { $0.day == day.day },
                                     openDayReview: { model.reviewingDay = day.day })
                    Text("As of \(report.takenAt.formatted(date: .abbreviated, time: .shortened)) · \(report.timeZoneIdentifier). Planned time is derived from current task records; dropped, carried and deleted tasks are excluded.")
                        .font(Typo.meta)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: Space.sm) {
                Image(systemName: "clock.arrow.circlepath").font(Typo.title).foregroundStyle(.tertiary)
                Text("Focus sessions and planned tasks show up here, day by day.")
                    .font(Typo.body).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        guard !Task.isCancelled else { return }
        let store = model.store
        guard let range else {
            state = .failed("This month is unavailable.")
            return
        }
        let from = range.from, through = range.through, calendar = range.calendar
        if selectedDay.map({ String($0.rawValue.prefix(7)) != monthKey }) == true { selectedDay = nil }
        // Refresh in place; only a new month (or a failure) shows the spinner.
        if case .loaded(let shown) = state, shown.from == from {} else { state = .loading }
        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try store.historyReport(from: from, through: through, calendar: calendar)
            }.value
            guard !Task.isCancelled else { return }
            state = .loaded(report)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

private struct HistorySummary: View {
    let totals: HistoryTotals

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.xl) { metrics }
            VStack(alignment: .leading, spacing: Space.sm) { metrics }
        }
        .font(Typo.body)
        .monospacedDigit()
    }

    @ViewBuilder private var metrics: some View {
        Text("\(Format.duration(totals.focusSeconds)) focused")
        Text("\(Format.duration(TimeInterval(totals.plannedSeconds))) planned")
            .foregroundStyle(.secondary)
        Text("\(Format.duration(totals.breakSeconds)) on breaks")
            .foregroundStyle(.secondary)
    }
}

private struct HistoryCategoryStrip: View {
    let categories: [HistoryCategory]

    private var focused: [HistoryCategory] { categories.filter { $0.focusSeconds > 0 } }

    var body: some View {
        GeometryReader { geometry in
            let total = focused.reduce(0) { $0 + $1.focusSeconds }
            let available = max(0, geometry.size.width - CGFloat(max(0, focused.count - 1)) * Space.hairline)
            HStack(spacing: Space.hairline) {
                ForEach(focused) { item in
                    Capsule()
                        .fill(item.category?.color ?? Theme.idle)
                        .frame(width: total > 0 ? available * item.focusSeconds / total : 0)
                }
            }
        }
        .frame(height: Space.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(focused.isEmpty ? "No recorded focus" : focused.map {
            "\($0.category?.name ?? "Unknown category") \(Format.duration($0.focusSeconds))"
        }.joined(separator: ", "))
    }
}

private struct HistoryDayDetail: View {
    let day: HistoryDay
    let closed: Bool
    let openDayReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Text(historyDayTitle(day.day, full: true))
                        .font(Typo.focus)
                    Spacer()
                    if closed {
                        Button("Day Review", systemImage: "arrow.up.forward", action: openDayReview)
                            .buttonStyle(.glass)
                            .font(Typo.body)
                            .help("Open this day's close summary and carry offers")
                    }
                }
                if let plan = day.plan {
                    Text("\(plan.status.rawValue.capitalized) plan\(plan.deletedAt == nil ? "" : " · Deleted")")
                        .font(Typo.meta).foregroundStyle(.secondary)
                }
                HistorySummary(totals: day.totals)
                HistoryCategoryStrip(categories: day.categories)
                Text(day.categories.map { "\($0.category?.name ?? "Unknown category") \(Format.duration($0.focusSeconds))" }
                        .joined(separator: " · "))
                    .font(Typo.meta)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if day.tasks.isEmpty && day.sessions.isEmpty {
                Text("No tasks or sessions were recorded for this day.")
                    .font(Typo.body).foregroundStyle(.secondary)
            }
            if !day.tasks.isEmpty {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Tasks").font(Typo.heading)
                    ForEach(day.tasks) { HistoryTaskDetail(row: $0, day: day.day) }
                }
            }
            if !day.sessions.isEmpty {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Sessions").font(Typo.heading)
                    Text("Focus belongs to the local date the session started. Pauses are excluded; historical pause intervals are unavailable.")
                        .font(Typo.meta).foregroundStyle(.secondary)
                    ForEach(day.sessions) { HistorySessionDetail(row: $0) }
                }
            }
        }
        .padding(.trailing, Space.sm)
    }
}

private struct HistoryTaskDetail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: HistoryTask
    let day: DayKey
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The whole header toggles; the chevron sits trailing and centred on it, like a macOS disclosure row.
            Button { expanded.toggle() } label: {
                HStack(spacing: Space.md) {
                    header
                    Spacer(minLength: Space.sm)
                    Image(systemName: "chevron.right")
                        .font(Typo.meta)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: expanded)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Hide details" : "Show details")
            .accessibilityValue(row.task.title)
            .help(expanded ? "Hide details" : "Show details")
            if expanded { details }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(row.task.title).font(Typo.body)
            Text("\(row.task.status == .todo ? "To do" : row.task.status.rawValue.capitalized)\(row.task.deletedAt == nil ? "" : " · Deleted") · \(row.category?.name ?? "Unknown category")\(row.category?.archived == true ? " · Archived category" : "")")
                .font(Typo.meta).foregroundStyle(.secondary)
            Text("\(Format.duration(row.focusSeconds)) focused · \(Format.duration(TimeInterval(row.derivedPlannedSeconds))) derived planned")
                .font(Typo.meta).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("\(row.task.blockMinutes)m task block · \(row.task.strict ? "Strict" : "Standard")")
                .font(Typo.meta).foregroundStyle(.secondary).monospacedDigit()
            if let planned = row.plannedDay, planned != day {
                Text("Currently planned for \(planned.rawValue). Focus shown here belongs to this day's sessions.")
                    .font(Typo.meta).foregroundStyle(.secondary)
            }
            if !row.tags.isEmpty {
                Text(row.tags.map { "@\($0.name)" }.joined(separator: " "))
                    .font(Typo.meta).foregroundStyle(.secondary)
            }
            if !row.task.notes.isEmpty { Text(row.task.notes).font(Typo.body).textSelection(.enabled) }
            ForEach(row.steps) { step in
                Label(step.title, systemImage: step.done ? "checkmark.circle" : "circle")
                    .font(Typo.body)
            }
            if let reference = row.task.linearRef {
                if let issue = LinearIssueLink(reference) {
                    Link(issue.title, destination: issue.url).font(Typo.body)
                } else {
                    Text(reference).font(Typo.meta).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .padding(.top, Space.sm)
    }
}

private struct HistorySessionDetail: View {
    let row: HistorySession

    private var status: String {
        if row.session.isPaused { return "Paused" }
        if row.session.isRunning { return "Running" }
        return row.session.endReason == .completed ? "Completed" : "Stopped"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(row.session.kind == .break ? "Break" : row.task?.title ?? "Unlinked focus session")
                .font(Typo.heading)
            Text("\(row.session.startedAt.formatted(date: .abbreviated, time: .shortened)) → \(row.session.endedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? status)")
                .font(Typo.meta).foregroundStyle(.secondary).monospacedDigit()
            Text("\(status) · \(Format.duration(row.actualSeconds)) actual · \(Format.duration(TimeInterval(row.session.plannedSeconds))) planned")
                .font(Typo.body).monospacedDigit()
            if row.session.pausedSeconds > 0 {
                Text("\(Format.duration(TimeInterval(row.session.pausedSeconds))) of recorded pauses excluded")
                    .font(Typo.meta).foregroundStyle(.secondary).monospacedDigit()
            }
            if row.session.kind == .focus {
                Text("\(row.session.outcome.map { $0 == .progress ? "Made progress" : $0.rawValue.capitalized } ?? "Outcome unavailable") · \(rating)")
                    .font(Typo.meta).foregroundStyle(.secondary)
                if let note = row.session.note, !note.isEmpty {
                    Text(note).font(Typo.body).textSelection(.enabled)
                }
                if row.session.reflectionPending {
                    Text("Saved reflection awaiting review").font(Typo.meta).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
    }

    private var rating: String {
        switch row.session.focusRating {
        case .scattered: "Scattered"
        case .okay: "Okay"
        case .focused: "Focused"
        case nil: "Focus rating unavailable"
        }
    }
}

func historyDayTitle(_ day: DayKey, full: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    let date = formatter.date(from: day.rawValue)!
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate(full ? "EEEE MMMM d yyyy" : "EEE d")
    return formatter.string(from: date)
}
