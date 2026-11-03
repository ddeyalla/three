import Charts
import SwiftUI
import ThreeCore

/// The Trends section of the Review sheet: four weeks from the shared stats read. A row of headline
/// numbers, then the five charts. Method notes and raw values sit behind each chart's Details.
struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var state = LoadState.loading
    @State private var refresh = 0
    @State private var tagId = ""

    private enum LoadState {
        case loading
        case loaded(StatsReport)
        case failed(String)
    }

    private struct ReadKey: Equatable {
        var revision: Date
        var refresh: Int
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: Space.md) {
                    Text("Trends couldn't be read").font(Typo.focus)
                    Text(message).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Try Again") { refresh += 1 }.buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let report):
                content(report)
            }
        }
        .font(Typo.body)
        .task(id: ReadKey(revision: model.snapshot.takenAt, refresh: refresh)) { await load() }
    }

    private func content(_ report: StatsReport) -> some View {
        let selected = report.tags.first { $0.id == tagId }
        let metrics = selected?.metrics ?? report.metrics
        let days = selected?.days ?? report.days
        let weeks = selected?.weeks ?? report.weeks
        let empty = metrics.quality.focusSessionCount == 0 && metrics.derivedPlannedSeconds == 0
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Last four weeks").font(Typo.heading)
                        Text("\(trendsShortDate(report.from)) – \(trendsShortDate(report.through)) · today and this week are partial")
                            .font(Typo.meta).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !report.tags.isEmpty {
                        Picker("Tag", selection: $tagId) {
                            Text("All tags").tag("")
                            ForEach(report.tags) { tag in Text("@\(tag.tag.name)").tag(tag.id) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                HStack(spacing: Space.md) {
                    TrendsTile(value: streakValue(report.streak), label: "day streak · all tags")
                    TrendsTile(value: Format.duration(metrics.focusSeconds), label: "focused")
                    TrendsTile(value: shortPercent(metrics.completion), label: "plan completion")
                    TrendsTile(value: shortPercent(metrics.quality.focusedShare), label: "rated focused")
                }
                if empty {
                    VStack(spacing: Space.sm) {
                        Image(systemName: "chart.bar").font(Typo.title).foregroundStyle(.tertiary)
                        Text("No focus sessions or planned tasks in these four weeks.")
                            .foregroundStyle(.secondary)
                        Text("Plan a task and run a focus block; the charts fill in from there.")
                            .font(Typo.meta).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    TrendsFocusChart(days: days, accent: model.accent)
                    TrendsCompletionChart(weeks: weeks, metrics: metrics, accent: model.accent)
                    TrendsAccuracyChart(days: days, metrics: metrics, accent: model.accent)
                    TrendsQualityChart(weeks: weeks, metrics: metrics, accent: model.accent)
                    TrendsBlocksChart(days: days, weeks: weeks, metrics: metrics, accent: model.accent)
                }
                DisclosureGroup("What these numbers include") {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(streakText(report.streak) + ". Streak uses all tags. A committed plan needs a task finished on that plan's day. An incomplete today retains yesterday's streak.")
                        Text("\(Format.duration(TimeInterval(metrics.derivedPlannedSeconds))) derived planned time.")
                        Text("\(metrics.commitmentSnapshotPlanCount) plans with commitment records · \(metrics.legacyCommittedPlanCount) older plans excluded from completion and accuracy.")
                        Text("Recorded break choices · \(metrics.breaks.takenCount) taken · \(metrics.breaks.skippedCount) skipped · \(metrics.breaks.missingDecisionCount) unknown after ended focus · \(metrics.breaks.pendingFocusSessionCount) pending focus.")
                        Text(report.provenance.actualTime)
                        Text(report.provenance.plannedTime)
                        Text(report.provenance.completion)
                        Text(report.provenance.accuracy)
                        Text(report.provenance.breaks)
                        Text(report.provenance.tags)
                        Text(report.provenance.coverage)
                        Text("Older plans without commitment records and unrecorded break choices remain unavailable. Complete activity coverage is unknown. Zero means no matching recorded rows, not proof of no activity. Active-session totals are frozen at the last refresh.")
                        Text("Missing task references: \(report.missingData.missingTaskReferenceCount). Missing category references: \(report.missingData.missingCategoryReferenceCount).")
                        Text("As of \(report.takenAt.formatted(date: .abbreviated, time: .shortened)) · \(report.timeZoneIdentifier)")
                    }
                    .font(Typo.meta).foregroundStyle(.secondary).textSelection(.enabled).monospacedDigit()
                    .padding(.top, Space.sm)
                }
                .font(Typo.meta)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.xl)
        }
    }

    private func load() async {
        guard !Task.isCancelled else { return }
        let store = model.store
        let calendar = Calendar.current
        // Refresh in place once something is shown; the spinner is for the first read only.
        if case .loaded = state {} else { state = .loading }
        do {
            let report = try await Task.detached(priority: .userInitiated) { try store.stats(calendar: calendar) }.value
            guard !Task.isCancelled else { return }
            if !report.tags.contains(where: { $0.id == tagId }) { tagId = "" }
            state = .loaded(report)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

private struct TrendsTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(value).font(Typo.title).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Typo.meta).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }
}

private struct TrendsFocusChart: View {
    let days: [StatsDay]
    let accent: Color

    var body: some View {
        TrendsCard(title: "Daily focus", headline: "Bars are minutes focused; the dashed line is the seven-day average") {
            Chart(days) { day in
                BarMark(x: .value("Day", day.day.rawValue), y: .value("Focus minutes", day.metrics.focusMinutes))
                    .foregroundStyle(accent.opacity(0.6))
                    .accessibilityLabel(dayLabel(day))
                    .accessibilityValue("\(Format.duration(day.metrics.focusSeconds)) focus")
                if let average = day.sevenDayAverageMinutes {
                    LineMark(x: .value("Day", day.day.rawValue), y: .value("Seven-day average minutes", average))
                        .foregroundStyle(.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .accessibilityLabel("\(dayLabel(day)), seven-day average")
                        .accessibilityValue("\(average.formatted(.number.precision(.fractionLength(1)))) minutes")
                }
            }
            .chartXScale(domain: days.map { $0.day.rawValue })
            .chartXAxis { trendsDateAxis(days.map(\.day)) }
            .chartYAxisLabel("Minutes")
            .frame(height: 160)
        } details: {
            Text("The line is the trailing seven-day average, including recorded zero days. The first six averages are unavailable.")
            ForEach(days) { day in
                Text("\(dayLabel(day)) · \(Format.duration(day.metrics.focusSeconds)) · Average \(day.sevenDayAverageMinutes.map { "\($0.formatted(.number.precision(.fractionLength(1)))) min" } ?? "unavailable, fewer than seven included dates")")
            }
        }
    }
}

private struct TrendsCompletionChart: View {
    let weeks: [StatsWeek]
    let metrics: StatsMetrics
    let accent: Color

    var body: some View {
        TrendsCard(title: "Plan completion", headline: metrics.completion.value == nil
                   ? "Unavailable until a committed plan has a recorded commitment snapshot with tasks"
                   : "\(ratioText(metrics.completion)) · \(metrics.completedTaskCount) of \(metrics.committedPlannedTaskCount) committed tasks done") {
            Chart(weeks) { week in
                if let percent = week.metrics.completion.percent {
                    BarMark(x: .value("Week starting", week.weekStarting.rawValue), y: .value("Completion percent", percent))
                        .foregroundStyle(accent)
                        .accessibilityLabel(weekLabel(week))
                        .accessibilityValue("\(ratioText(week.metrics.completion)), \(week.metrics.completedTaskCount) of \(week.metrics.committedPlannedTaskCount) tasks")
                }
            }
            .chartXScale(domain: weeks.map { $0.weekStarting.rawValue })
            .chartXAxis { trendsDateAxis(weeks.map(\.weekStarting)) }
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("Percent")
            .frame(height: 140)
        } details: {
            Text("Done original commitment tasks divided by all original commitment tasks, including later drops and carries. Closed days use frozen outcomes. Drafts and legacy plans without snapshots are excluded.")
            ForEach(weeks) { week in
                Text("\(weekLabel(week)) · \(ratioText(week.metrics.completion)) · \(week.metrics.completedTaskCount) of \(week.metrics.committedPlannedTaskCount) tasks")
            }
        }
    }
}

private struct TrendsAccuracyChart: View {
    let days: [StatsDay]
    let metrics: StatsMetrics
    let accent: Color

    var body: some View {
        TrendsCard(title: "Actual vs planned time", headline: metrics.actualToPlanned.value == nil
                   ? "Unavailable: no committed planned time with a snapshot is recorded"
                   : "\(ratioText(metrics.actualToPlanned)) · \(Format.duration(metrics.accuracyFocusSeconds)) actual of \(Format.duration(TimeInterval(metrics.committedPlannedSeconds))) planned") {
            Chart {
                RuleMark(y: .value("Equal actual and planned", 100))
                    .foregroundStyle(Theme.idle)
                    .lineStyle(StrokeStyle(dash: [4, 3]))
                    .accessibilityLabel("100 percent means actual equals planned")
                ForEach(days) { day in
                    if let percent = day.metrics.actualToPlanned.percent {
                        PointMark(x: .value("Day", day.day.rawValue), y: .value("Actual / planned percent", percent))
                            .foregroundStyle(accent)
                            .accessibilityLabel(dayLabel(day))
                            .accessibilityValue(ratioText(day.metrics.actualToPlanned))
                    }
                }
            }
            .chartXScale(domain: days.map { $0.day.rawValue })
            .chartXAxis { trendsDateAxis(days.map(\.day)) }
            .chartYAxisLabel("Percent")
            .frame(height: 140)
        } details: {
            Text("Recorded focus on dates with commitment snapshots divided by original committed planned time. 100% means equal time. Unplanned focus on those dates counts in actual time; the ratio can exceed 100%. Legacy dates and drafts are excluded.")
            ForEach(days) { day in
                Text("\(dayLabel(day)) · \(ratioText(day.metrics.actualToPlanned)) · \(Format.duration(day.metrics.accuracyFocusSeconds)) actual / \(Format.duration(TimeInterval(day.metrics.committedPlannedSeconds))) committed planned")
            }
        }
    }
}

private struct TrendsQualityChart: View {
    let weeks: [StatsWeek]
    let metrics: StatsMetrics
    let accent: Color

    var body: some View {
        TrendsCard(title: "Focus quality", headline: metrics.quality.ratedSessionCount == 0
                   ? "No focus ratings recorded yet. Rate a session in its reflection to see this"
                   : "\(ratioText(metrics.quality.focusedShare)) rated focused · \(metrics.quality.focusedSessionCount) of \(metrics.quality.ratedSessionCount) rated · \(metrics.quality.missingRatingCount) unrated") {
            Chart(weeks) { week in
                if let percent = week.metrics.quality.focusedShare.percent {
                    BarMark(x: .value("Week starting", week.weekStarting.rawValue), y: .value("Focused percent", percent))
                        .foregroundStyle(accent)
                        .accessibilityLabel(weekLabel(week))
                        .accessibilityValue(qualityText(week.metrics.quality))
                }
            }
            .chartXScale(domain: weeks.map { $0.weekStarting.rawValue })
            .chartXAxis { trendsDateAxis(weeks.map(\.weekStarting)) }
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("Percent focused")
            .frame(height: 140)
        } details: {
            Text("Weekly focused ratings divided by recorded focus-session ratings. Sessions without ratings remain unavailable and do not count as scattered. The category breakdown reflects current task records.")
            ForEach(weeks) { week in
                Text("\(weekLabel(week)) · \(qualityText(week.metrics.quality))")
            }
            ForEach(metrics.categoryQuality) { category in
                Text("\(category.category?.name ?? "Unknown category") · \(qualityText(category.quality))")
            }
        }
    }
}

private struct TrendsBlocksChart: View {
    let days: [StatsDay]
    let weeks: [StatsWeek]
    let metrics: StatsMetrics
    let accent: Color

    var body: some View {
        TrendsCard(title: "Distraction pull", headline: metrics.blocks.hitsPerFocusHour.value == nil
                   ? "Unavailable: no focus time is recorded"
                   : "\(rateText(metrics.blocks.hitsPerFocusHour)) block hits and \(rateText(metrics.blocks.unblocksPerFocusHour)) unblocks per focus hour") {
            Chart(weeks) { week in
                if let hits = week.metrics.blocks.hitsPerFocusHour.value {
                    LineMark(x: .value("Week starting", week.weekStarting.rawValue), y: .value("Hits per focus hour", hits), series: .value("Event", "Hits"))
                        .foregroundStyle(accent)
                        .symbol(.circle)
                        .accessibilityLabel("\(weekLabel(week)), recorded hits per focus hour")
                        .accessibilityValue(rateText(week.metrics.blocks.hitsPerFocusHour))
                }
                if let unblocks = week.metrics.blocks.unblocksPerFocusHour.value {
                    LineMark(x: .value("Week starting", week.weekStarting.rawValue), y: .value("Unblocks per focus hour", unblocks), series: .value("Event", "Unblocks"))
                        .foregroundStyle(.primary)
                        .lineStyle(StrokeStyle(dash: [4, 3]))
                        .symbol(.square)
                        .accessibilityLabel("\(weekLabel(week)), recorded unblocks per focus hour")
                        .accessibilityValue(rateText(week.metrics.blocks.unblocksPerFocusHour))
                }
            }
            .chartXScale(domain: weeks.map { $0.weekStarting.rawValue })
            .chartXAxis { trendsDateAxis(weeks.map(\.weekStarting)) }
            .chartYAxisLabel("Per focus hour")
            .frame(height: 140)
            if metrics.blocks.topTargets.isEmpty {
                Text("No matching block events recorded.").font(Typo.meta).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Most blocked").font(Typo.heading)
                    ForEach(metrics.blocks.topTargets) { target in
                        Text("\(target.target ?? "Unavailable rule") · \(target.hitCount) hits · \(target.unblockCount) unblocks")
                            .font(Typo.meta).monospacedDigit().textSelection(.enabled)
                    }
                }
            }
        } details: {
            Text("Solid circles are linked block hits per focus hour; dashed squares are granted unblocks per focus hour. Linked events follow their focus session's start day. Unassociated events are separate and excluded from rates. Only recorded events are shown; unconfigured sites and apps, unsupported browsers and other unrecorded activity are not measured.")
            Text("\(metrics.blocks.associatedHits) linked hits · \(metrics.blocks.associatedUnblocks) linked unblocks · \(Format.duration(metrics.focusSeconds)) focus denominator")
            Text("Outside matching focus sessions · \(metrics.blocks.unassociatedHits) hits · \(metrics.blocks.unassociatedUnblocks) unblocks")
            ForEach(metrics.blocks.topTargets) { target in
                Text("\(target.target ?? "Unavailable rule") · including \(target.unassociatedHits) hits and \(target.unassociatedUnblocks) unblocks outside matching focus sessions")
            }
            ForEach(days) { day in
                Text("\(dayLabel(day)) · \(rateText(day.metrics.blocks.hitsPerFocusHour)) hits / hour · \(rateText(day.metrics.blocks.unblocksPerFocusHour)) unblocks / hour · \(day.metrics.blocks.associatedHits) linked hits · \(day.metrics.blocks.associatedUnblocks) linked unblocks · \(Format.duration(day.metrics.focusSeconds)) focus")
            }
        }
    }
}

private func trendsDateAxis(_ dates: [DayKey]) -> some AxisContent {
    let interval = dates.count > 7 ? 7 : 1
    let ticks = dates.enumerated().filter { $0.offset % interval == 0 || $0.offset == dates.count - 1 }
        .map { $0.element.rawValue }
    return AxisMarks(values: ticks) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(collisionResolution: .greedy) {
            if let date = value.as(String.self) {
                Text(String(date.suffix(5))).monospacedDigit()
            }
        }
    }
}

/// A chart with its title and one headline line. The method note and every plotted value
/// sit behind Details, so the numbers stay checkable without crowding the chart.
private struct TrendsCard<Content: View, Details: View>: View {
    let title: String
    let headline: String
    @ViewBuilder var content: Content
    @ViewBuilder var details: Details

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(Typo.focus).accessibilityAddTraits(.isHeader)
                Text(headline).font(Typo.body).foregroundStyle(.secondary).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: Space.xs) { details }
                    .font(Typo.meta).foregroundStyle(.secondary).monospacedDigit().textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.xs)
            }
            .font(Typo.meta)
            .foregroundStyle(.secondary)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
    }
}

private func ratioText(_ ratio: StatsRatio) -> String {
    ratio.percent.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "Undefined, zero denominator"
}

private func rateText(_ ratio: StatsRatio) -> String {
    ratio.value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "Undefined"
}

private func dayLabel(_ day: StatsDay) -> String { "\(day.day.rawValue)\(day.isPartial ? " · Partial today" : "")" }

private func weekLabel(_ week: StatsWeek) -> String {
    "\(week.from.rawValue) to \(week.through.rawValue)\(week.isPartial ? " · Partial week" : "")"
}

private func qualityText(_ quality: StatsQuality) -> String {
    "\(ratioText(quality.focusedShare)) · \(quality.focusedSessionCount) focused, \(quality.okaySessionCount) okay, \(quality.scatteredSessionCount) scattered · \(quality.missingRatingCount) unrated"
}

private func streakText(_ streak: StatsStreak) -> String {
    if streak.isLowerBound && streak.days == 0 { return "Streak unavailable beyond this range" }
    let count = "\(streak.isLowerBound ? "At least " : "")\(streak.days) day\(streak.days == 1 ? "" : "s") in the streak"
    return count + (streak.endingOn.map { " ending \($0.rawValue)" } ?? "")
}

/// Tile value: a whole percent, or "Unavailable" when the denominator is zero (never 0%).
private func shortPercent(_ ratio: StatsRatio) -> String {
    ratio.percent.map { "\(Int($0.rounded()))%" } ?? "Unavailable"
}

private func streakValue(_ streak: StatsStreak) -> String {
    if streak.isLowerBound && streak.days == 0 { return "Unavailable" }
    return "\(streak.isLowerBound ? "≥" : "")\(streak.days)"
}

private func trendsShortDate(_ day: DayKey) -> String {
    day.startDate.formatted(.dateTime.month(.abbreviated).day())
}
