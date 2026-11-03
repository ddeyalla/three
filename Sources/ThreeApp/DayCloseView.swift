import SwiftUI
import ThreeCore

/// One sheet for looking back: the day-close review, the month-by-month history and the
/// four-week trends. Opened from Review in the tasks pane, the Go menu (⌘6 to ⌘8), and any
/// "Review day" button. Escape or Done closes it.
struct ReviewSheet: View {
    @Environment(AppModel.self) private var model

    private var section: ReviewSection { model.reviewSection ?? .day }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                ChoiceCapsules(selection: Binding(get: { section }, set: { model.openReview($0) }),
                               options: ReviewSection.allCases.map { .init($0, $0.title) })
                Spacer()
                Button("Done") { model.closeReview() }
                    .buttonStyle(.glass)
                    .font(Typo.body)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.md)
            Divider()
            // No transition: sections switch from the keyboard (⌘6 to ⌘8) and should feel instant.
            Group {
                switch section {
                case .day: DayReview()
                case .history: HistoryView()
                case .trends: TrendsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, idealWidth: 780, maxWidth: 1200, minHeight: 540, idealHeight: 640, maxHeight: 1000)
        .presentationSizing(.fitted)
    }
}

/// The Day section: one closed day at a time, newest first, with arrows to step through them.
/// The arrows ask the store for the neighbouring close, so they reach every closed day rather
/// than only the recent ones held in `dayCloses`.
private struct DayReview: View {
    @Environment(AppModel.self) private var model
    @State private var neighbours: (previous: DayKey?, next: DayKey?) = (nil, nil)

    /// Reloads the neighbours when the day changes or the store does (a day may have just closed).
    private struct Neighbourhood: Hashable { let day: DayKey; let takenAt: Date }

    private var latest: DayKey? { model.dayCloses.first?.day }
    private var day: DayKey { model.reviewingDay ?? latest ?? model.snapshot.day }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                Button("Previous Closed Day", systemImage: "chevron.left") { model.reviewingDay = neighbours.previous }
                    .labelStyle(.iconOnly)
                    .disabled(neighbours.previous == nil)
                Text(historyDayTitle(day, full: true))
                    .font(Typo.focus)
                    .monospacedDigit()
                Button("Next Closed Day", systemImage: "chevron.right") { model.reviewingDay = neighbours.next }
                    .labelStyle(.iconOnly)
                    .disabled(neighbours.next == nil)
                Spacer()
                if let latest, latest != day {
                    Button("Latest") { model.reviewingDay = latest }
                        .font(Typo.body)
                }
            }
            .buttonStyle(.glass)
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            DayCloseView(day: day)
                .id(day)
        }
        .task(id: Neighbourhood(day: day, takenAt: model.snapshot.takenAt)) {
            neighbours = (try? model.store.closedDays(around: day)) ?? (nil, nil)
        }
    }
}

struct DayCloseView: View {
    @Environment(AppModel.self) private var model
    let day: DayKey
    var pendingRecovery: DayCloseRecoveryCheck = { _, _ in false }
    @State private var review: DayCloseReview?
    @State private var status: DayCloseResult?
    @State private var loadError: String?
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if let error = actionError ?? loadError {
                    HStack(spacing: Space.md) {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(Typo.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Refresh") { actionError = nil; reload() }
                            .buttonStyle(.glass).font(Typo.body)
                    }
                }
                if let review {
                    summary(review.summary)
                    if review.offers.isEmpty {
                        Label("No unfinished work waiting for a decision.", systemImage: "checkmark.circle")
                            .font(Typo.body).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Unfinished work").font(Typo.heading)
                            Text(day < .today
                                 ? "Choose what belongs today. Nothing is added automatically."
                                 : "Review this work on a later day to accept it. You can dismiss it now.")
                                .font(Typo.meta).foregroundStyle(.secondary)
                            ForEach(review.offers) { row in offer(row) }
                        }
                    }
                    if !review.decisions.isEmpty {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("Reviewed").font(Typo.heading)
                            ForEach(review.decisions, id: \.sourceTaskId) { decision in
                                let title = review.summary.tasks.first { $0.id == decision.sourceTaskId }?.title ?? "Task"
                                Label(decision.decision == .accepted
                                      ? "\(title) · Accepted for \(decision.destinationDay?.rawValue ?? "a later day")"
                                      : "\(title) · Dismissed",
                                      systemImage: decision.decision == .accepted ? "arrow.turn.down.right" : "xmark")
                                    .font(Typo.body).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if status == nil, loadError == nil {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if loadError == nil {
                    VStack(spacing: Space.sm) {
                        Image(systemName: "moon.zzz").font(Typo.title).foregroundStyle(.tertiary)
                        Text(statusText).font(Typo.body).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.dayCloses.isEmpty {
                            Text("Each committed day is summarised here once it closes.")
                                .font(Typo.meta).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.xl)
        }
        .task { reload() }
        .onChange(of: day) { reload() }
        .onChange(of: model.snapshot.takenAt) { reload() }
    }

    private func summary(_ summary: DayCloseSummary) -> some View {
        let unfinished = summary.tasks.filter { $0.status.isOpen }.count
        return VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xxl) {
                stat(Format.duration(summary.focusedSeconds), "focused")
                stat("\(summary.doneCount)", "done")
                stat("\(unfinished)", "unfinished")
                stat("\(summary.plannedMinutes)m", "planned")
                stat(summary.skippedBreakCount.map { "\($0)" } ?? "—",
                     summary.skippedBreakCount == nil ? "skipped breaks unavailable" : "skipped breaks")
            }
            Text("Planned time \(summary.commitment == nil ? "derived from recorded tasks" : "as committed"). Saved when the day closed; later carry decisions keep this summary.")
                .font(Typo.meta).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(value).font(Typo.title).monospacedDigit()
            Text(label).font(Typo.meta).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func offer(_ row: TaskRow) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(row.task.title).font(Typo.body).fixedSize(horizontal: false, vertical: true)
                Text("\(row.category.name) · \(row.task.blockMinutes)m\(row.task.strict ? " · Strict" : "")")
                    .font(Typo.meta).foregroundStyle(.secondary)
                if !row.task.notes.isEmpty {
                    Text(row.task.notes).font(Typo.meta).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: Space.md)
            HStack(spacing: Space.sm) {
                Button("Dismiss") { decide { _ = try model.store.dismissCarry(row.id) } }
                    .help("Leave this work on its original day without adding it to another plan.")
                    .accessibilityLabel("Dismiss unfinished work \(row.task.title)")
                Button("Accept today") {
                    decide { _ = try model.store.carryTask(row.id, to: .today) }
                }
                .disabled(day >= .today)
                .help(day >= .today ? "You can accept this work on a later day." : "Copy this work into today's plan.")
                .accessibilityLabel("Accept \(row.task.title) for today")
            }
            .font(Typo.body)
            .buttonStyle(.glass)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
    }

    private var statusText: String {
        switch status {
        case .deferred(.focus): "This day will close after its focus block ends."
        case .deferred(.reflection): "Review or dismiss this day's saved reflection before it closes."
        case .deferred(.recovery): "Choose whether to keep or trim the interrupted session before this day closes."
        case .notEligible(.legacyClosed): "This older day closed before summaries were recorded."
        case .notEligible(.noCommittedPlan): "A committed plan is needed before this day can close."
        case .notEligible(.emptyPlan): "There is no planned work to review."
        case .notEligible(.futureDay): "This day has not arrived yet."
        case .notEligible(.notDue): "This day's summary will be saved when its work is resolved or its close time arrives."
        case .ready: "This day is ready to close at the next check."
        case .closed, nil: "No saved day summary."
        }
    }

    private func decide(_ action: () throws -> Void) {
        actionError = model.perform(action) ? nil : model.error
        reload()
    }

    private func reload() {
        do {
            review = try model.store.dayCloseReview(for: day)
            status = try model.store.dayCloseStatus(for: day, pendingRecovery: pendingRecovery)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
