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

    private var monthKey: String { HistoryMonth(containing: month)?.key ?? "unavailable" }
    private var readKey: ReadKey { ReadKey(month: monthKey, revision: model.snapshot.takenAt, refresh: refresh) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            header
            switch state {
            case .loading:
                ProgressView("Reading history…")
                    .font(Typo.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: Space.md) {
                    Text("History couldn't be read").font(Typo.focus)
                    Text(message).font(Typo.body).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Try Again") { refresh += 1 }
                        .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let report):
                HistorySummary(totals: report.totals)
                Text("Planned time is derived from current task records. Dropped, carried, and deleted tasks are excluded.")
                    .font(Typo.meta)
                    .foregroundStyle(.secondary)
                GeometryReader { geometry in
                    if geometry.size.width >= 760 {
                        HStack(alignment: .top, spacing: Space.xl) {
                            dayList(report).frame(width: 280)
                            Divider()
                            detail(report).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else if selectedDay != nil {
                        VStack(alignment: .leading, spacing: Space.md) {
                            Button("Days in Month", systemImage: "chevron.left") { selectedDay = nil }
                                .buttonStyle(.plain)
                                .font(Typo.body)
                            detail(report)
                        }
                    } else {
                        dayList(report)
                    }
                }
                Text("As of \(report.takenAt.formatted(date: .abbreviated, time: .shortened)) · \(report.timeZoneIdentifier)")
                    .font(Typo.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Space.xl)
        .background(.thinMaterial, in: .rect(cornerRadius: Radius.panel))
        .padding(Space.sm)
        .task(id: readKey) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Button("Today", systemImage: "chevron.left") { model.destination = .today }
                    .font(Typo.body)
                    .buttonStyle(.glass)
                Text("History").font(Typo.title)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { refresh += 1 }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .help("Refresh recorded history and active-session totals")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.md) {
                    monthControls
                    Spacer()
                    monthPicker
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    monthControls
                    monthPicker
                }
            }
        }
    }

    private var monthControls: some View {
        HStack(spacing: Space.md) {
            Button("Previous Month", systemImage: "chevron.left") { moveMonth(-1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            Text(HistoryMonth(containing: month)?.title ?? "Month unavailable")
                .font(Typo.heading)
                .fixedSize()
                .monospacedDigit()
            Button("Next Month", systemImage: "chevron.right") { moveMonth(1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
        }
    }

    private var monthPicker: some View {
        HStack(spacing: Space.md) {
            DatePicker("Go to Month", selection: $month, displayedComponents: .date)
                .environment(\.calendar, HistoryMonth(containing: month)?.calendar ?? Calendar(identifier: .gregorian))
                .labelsHidden()
                .accessibilityLabel("Go to month containing date")
                .font(Typo.body)
                .fixedSize()
            Button("This Month") { month = Date() }
                .buttonStyle(.glass)
                .font(Typo.body)
        }
    }

    private func moveMonth(_ amount: Int) {
        if let next = HistoryMonth(containing: month)?.shifted(by: amount) {
            month = next
        }
    }

    private func dayList(_ report: HistoryReport) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.sm) {
                ForEach(report.days) { day in
                    Button {
                        selectedDay = day.day
                    } label: {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            HStack {
                                Text(historyDayTitle(day.day))
                                    .font(Typo.heading)
                                Spacer(minLength: Space.sm)
                                Text(Format.duration(day.totals.focusSeconds))
                                    .font(Typo.body)
                                    .monospacedDigit()
                            }
                            HistoryCategoryStrip(categories: day.categories)
                            Text(day.sessions.isEmpty && day.tasks.isEmpty ? "No recorded activity" :
                                    "\(day.totals.doneTaskCount) of \(day.totals.plannedTaskCount) tasks done · \(Format.duration(TimeInterval(day.totals.plannedSeconds))) planned")
                                .font(Typo.meta)
                                .foregroundStyle(.secondary)
                        }
                        .padding(Space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .background(selectedDay == day.day ? Theme.rowFill : .clear, in: .rect(cornerRadius: Radius.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedDay == day.day ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder private func detail(_ report: HistoryReport) -> some View {
        if let day = report.days.first(where: { $0.day == selectedDay }) {
            ScrollView {
                HistoryDayDetail(day: day)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Choose a day to see tasks, sessions, and reflections.")
                .font(Typo.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        guard !Task.isCancelled else { return }
        let store = model.store
        guard let range = HistoryMonth(containing: month) else {
            state = .failed("This month is unavailable.")
            return
        }
        let from = range.from, through = range.through, calendar = range.calendar
        if selectedDay.map({ String($0.rawValue.prefix(7)) != monthKey }) == true { selectedDay = nil }
        state = .loading
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

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(historyDayTitle(day.day, full: true))
                    .font(Typo.focus)
                if let plan = day.plan {
                    Text("\(plan.status.rawValue.capitalized) plan\(plan.deletedAt == nil ? "" : " · Deleted")")
                        .font(Typo.meta).foregroundStyle(.secondary)
                }
                HistorySummary(totals: day.totals)
                HistoryCategoryStrip(categories: day.categories)
                ForEach(day.categories) { category in
                    Text("\(category.category?.name ?? "Unknown category") · \(Format.duration(category.focusSeconds)) focused")
                        .font(Typo.meta)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
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
    let row: HistoryTask
    let day: DayKey

    var body: some View {
        DisclosureGroup {
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
        } label: {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(row.task.title).font(Typo.body)
                Text("\(row.task.status == .todo ? "To do" : row.task.status.rawValue.capitalized)\(row.task.deletedAt == nil ? "" : " · Deleted") · \(row.category?.name ?? "Unknown category")\(row.category?.archived == true ? " · Archived category" : "")")
                    .font(Typo.meta).foregroundStyle(.secondary)
                Text("\(Format.duration(row.focusSeconds)) focused · \(Format.duration(TimeInterval(row.derivedPlannedSeconds))) derived planned")
                    .font(Typo.meta).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(Space.md)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
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

private func historyDayTitle(_ day: DayKey, full: Bool = false) -> String {
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
