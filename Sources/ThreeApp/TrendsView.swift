import Charts
import SwiftUI
import ThreeCore

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
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                Button("Today", systemImage: "chevron.left") { model.destination = .today }
                    .buttonStyle(.glass)
                Text("Trends").font(Typo.title)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { refresh += 1 }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .help("Refresh recorded trends and active-session totals")
            }
            switch state {
            case .loading:
                ProgressView("Reading trends…")
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
        .padding(Space.xl)
        .background(.thinMaterial, in: .rect(cornerRadius: Radius.panel))
        .padding(Space.sm)
        .task(id: ReadKey(revision: model.snapshot.takenAt, refresh: refresh)) { await load() }
    }

    private func content(_ report: StatsReport) -> some View {
        let selected = report.tags.first { $0.id == tagId }
        let metrics = selected?.metrics ?? report.metrics
        let days = selected?.days ?? report.days
        let weeks = selected?.weeks ?? report.weeks
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("\(report.from.rawValue) to \(report.through.rawValue) · Four weeks")
                        .font(Typo.heading)
                    Text("Today and this week are partial. Active-session totals are frozen at the last refresh.")
                        .font(Typo.meta).foregroundStyle(.secondary)
                    Picker("Tag", selection: $tagId) {
                        Text("All tags").tag("")
                        ForEach(report.tags) { tag in Text("@\(tag.tag.name)").tag(tag.id) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    Text("\(Format.duration(metrics.focusSeconds)) recorded focus · \(Format.duration(TimeInterval(metrics.derivedPlannedSeconds))) derived planned")
                        .monospacedDigit()
                    Text("\(metrics.commitmentSnapshotPlanCount) plans with commitment records · \(metrics.legacyCommittedPlanCount) older plans excluded from completion and accuracy")
                        .font(Typo.meta).foregroundStyle(.secondary)
                    Text("Recorded break choices · \(metrics.breaks.takenCount) taken · \(metrics.breaks.skippedCount) skipped · \(metrics.breaks.missingDecisionCount) unknown after ended focus · \(metrics.breaks.pendingFocusSessionCount) pending focus")
                        .font(Typo.meta).foregroundStyle(.secondary).monospacedDigit()
                    Text(streakText(report.streak)).font(Typo.body)
                    Text("Streak uses all tags. A committed plan needs a task finished on that plan's day. An incomplete today retains yesterday's streak.")
                        .font(Typo.meta).foregroundStyle(.secondary)
                    if metrics.quality.focusSessionCount == 0 && metrics.derivedPlannedSeconds == 0 {
                        Text("No focus sessions or eligible planned tasks recorded in this range. Plan a task and record focus to populate these trends.")
                            .foregroundStyle(.secondary)
                    }
                }
                TrendsFocusChart(days: days, accent: model.accent)
                TrendsCompletionChart(weeks: weeks, metrics: metrics, accent: model.accent)
                TrendsAccuracyChart(days: days, metrics: metrics, accent: model.accent)
                TrendsQualityChart(weeks: weeks, metrics: metrics, accent: model.accent)
                TrendsBlocksChart(days: days, weeks: weeks, metrics: metrics, accent: model.accent)
                DisclosureGroup("What these numbers include") {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(report.provenance.actualTime)
                        Text(report.provenance.plannedTime)
                        Text(report.provenance.completion)
                        Text(report.provenance.accuracy)
                        Text(report.provenance.breaks)
                        Text(report.provenance.tags)
                        Text(report.provenance.coverage)
                        Text("Older plans without commitment records and unrecorded break choices remain unavailable. Complete activity coverage is unknown. Zero means no matching recorded rows, not proof of no activity.")
                        Text("Missing task references: \(report.missingData.missingTaskReferenceCount). Missing category references: \(report.missingData.missingCategoryReferenceCount).")
                    }
                    .font(Typo.meta).foregroundStyle(.secondary).textSelection(.enabled)
                    .padding(.top, Space.sm)
                }
                Text("As of \(report.takenAt.formatted(date: .abbreviated, time: .shortened)) · \(report.timeZoneIdentifier)")
                    .font(Typo.meta).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, Space.sm)
        }
    }

    private func load() async {
        guard !Task.isCancelled else { return }
        let store = model.store
        let calendar = Calendar.current
        state = .loading
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

private struct TrendsFocusChart: View {
    let days: [StatsDay]
    let accent: Color

    var body: some View {
        TrendsCard(title: "Daily focus", note: "Bars show recorded focus minutes. The line shows the trailing seven-day average, including recorded zero days. The first six averages are unavailable.") {
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
            .frame(height: 190)
            DisclosureGroup("Daily focus values") {
                ForEach(days) { day in
                    Text("\(dayLabel(day)) · \(Format.duration(day.metrics.focusSeconds)) · Average \(day.sevenDayAverageMinutes.map { "\($0.formatted(.number.precision(.fractionLength(1)))) min" } ?? "unavailable, fewer than seven included dates")")
                        .font(Typo.meta).monospacedDigit()
                }
            }
        }
    }
}

private struct TrendsCompletionChart: View {
    let weeks: [StatsWeek]
    let metrics: StatsMetrics
    let accent: Color

    var body: some View {
        TrendsCard(title: "Weekly plan completion", note: "Done original commitment tasks divided by all original commitment tasks, including later drops and carries. Closed days use frozen outcomes. Drafts and legacy plans without snapshots are excluded.") {
            Text("\(ratioText(metrics.completion)) · \(metrics.completedTaskCount) of \(metrics.committedPlannedTaskCount) committed planned tasks done")
                .monospacedDigit()
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
            .frame(height: 170)
            ForEach(weeks) { week in
                Text("\(weekLabel(week)) · \(ratioText(week.metrics.completion)) · \(week.metrics.completedTaskCount) of \(week.metrics.committedPlannedTaskCount) tasks")
                    .font(Typo.meta).monospacedDigit()
            }
            if metrics.completion.value == nil {
                Text("Completion is unavailable until a committed plan has a recorded commitment snapshot with tasks.").foregroundStyle(.secondary)
            }
        }
    }
}

private struct TrendsAccuracyChart: View {
    let days: [StatsDay]
    let metrics: StatsMetrics
    let accent: Color

    var body: some View {
        TrendsCard(title: "Actual / planned time", note: "Recorded focus on dates with commitment snapshots divided by original committed planned time. 100% means equal time. Unplanned focus on those dates counts in actual time; the ratio can exceed 100%. Legacy dates and drafts are excluded.") {
            Text("\(ratioText(metrics.actualToPlanned)) · \(Format.duration(metrics.accuracyFocusSeconds)) actual / \(Format.duration(TimeInterval(metrics.committedPlannedSeconds))) committed planned")
                .monospacedDigit()
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
            .frame(height: 170)
            if metrics.actualToPlanned.value == nil {
                Text("Accuracy is unavailable because no committed planned time with a snapshot is recorded.").foregroundStyle(.secondary)
            }
            DisclosureGroup("Daily time values") {
                ForEach(days) { day in
                    Text("\(dayLabel(day)) · \(ratioText(day.metrics.actualToPlanned)) · \(Format.duration(day.metrics.accuracyFocusSeconds)) actual / \(Format.duration(TimeInterval(day.metrics.committedPlannedSeconds))) committed planned")
                        .font(Typo.meta).monospacedDigit()
                }
            }
        }
    }
}

private struct TrendsQualityChart: View {
    let weeks: [StatsWeek]
    let metrics: StatsMetrics
    let accent: Color

    var body: some View {
        TrendsCard(title: "Focused-rated session share", note: "Weekly focused ratings divided by recorded focus-session ratings. Sessions without ratings remain unavailable and do not count as scattered. The category breakdown reflects current task records.") {
            Text("\(ratioText(metrics.quality.focusedShare)) · \(metrics.quality.focusedSessionCount) focused of \(metrics.quality.ratedSessionCount) rated · \(metrics.quality.missingRatingCount) unrated")
                .monospacedDigit()
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
            .chartYAxisLabel("Percent focused among recorded ratings")
            .frame(height: 190)
            DisclosureGroup("Weekly quality values") {
                ForEach(weeks) { week in
                    Text("\(weekLabel(week)) · \(qualityText(week.metrics.quality))")
                        .font(Typo.meta).monospacedDigit()
                }
            }
            ForEach(metrics.categoryQuality) { category in
                Text("\(category.category?.name ?? "Unknown category") · \(qualityText(category.quality))")
                    .font(Typo.meta).monospacedDigit()
            }
            if metrics.quality.ratedSessionCount == 0 {
                Text("No focus ratings recorded. Rate a focus session to see quality trends.").foregroundStyle(.secondary)
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
        TrendsCard(title: "Recorded distractions per focus hour", note: "Weekly solid circles show linked block hits per focus hour. Dashed squares show granted unblocks per focus hour. Linked events follow their focus session's start day. Unassociated events are separate and excluded from rates.") {
            Text("\(rateText(metrics.blocks.hitsPerFocusHour)) hits / focus hour · \(rateText(metrics.blocks.unblocksPerFocusHour)) unblocks / focus hour")
                .monospacedDigit()
            Text("\(metrics.blocks.associatedHits) linked hits · \(metrics.blocks.associatedUnblocks) linked unblocks · \(Format.duration(metrics.focusSeconds)) focus denominator")
                .font(Typo.meta).monospacedDigit()
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
            .chartYAxisLabel("Events per focus hour")
            .frame(height: 190)
            if metrics.blocks.hitsPerFocusHour.value == nil {
                Text("Rates are unavailable because no focus time is recorded.").foregroundStyle(.secondary)
            }
            Text("Outside matching focus sessions · \(metrics.blocks.unassociatedHits) hits · \(metrics.blocks.unassociatedUnblocks) unblocks")
                .font(Typo.meta).monospacedDigit()
            Text("Top recorded sites and apps").font(Typo.heading)
            ForEach(metrics.blocks.topTargets) { target in
                Text("\(target.target ?? "Unavailable rule") · \(target.hitCount) hits · \(target.unblockCount) unblocks, including \(target.unassociatedHits) hits and \(target.unassociatedUnblocks) unblocks outside matching focus sessions")
                    .font(Typo.meta).monospacedDigit().textSelection(.enabled)
            }
            if metrics.blocks.topTargets.isEmpty {
                Text("No matching block events recorded.").foregroundStyle(.secondary)
            }
            Text("Only recorded events are shown. Unconfigured sites and apps, unsupported browsers, and other unrecorded activity are not measured.")
                .font(Typo.meta).foregroundStyle(.secondary)
            DisclosureGroup("Daily distraction values") {
                ForEach(days) { day in
                    Text("\(dayLabel(day)) · \(rateText(day.metrics.blocks.hitsPerFocusHour)) hits / hour · \(rateText(day.metrics.blocks.unblocksPerFocusHour)) unblocks / hour · \(day.metrics.blocks.associatedHits) linked hits · \(day.metrics.blocks.associatedUnblocks) linked unblocks · \(Format.duration(day.metrics.focusSeconds)) focus")
                        .font(Typo.meta).monospacedDigit()
                }
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
        AxisValueLabel {
            if let date = value.as(String.self) {
                Text(String(date.suffix(5))).monospacedDigit()
            }
        }
    }
}

private struct TrendsCard<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(title).font(Typo.focus).accessibilityAddTraits(.isHeader)
            Text(note).font(Typo.meta).foregroundStyle(.secondary)
            content
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
