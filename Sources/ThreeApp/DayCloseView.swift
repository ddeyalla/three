import SwiftUI
import ThreeCore

struct DayReviewSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                DatePicker("Review date", selection: Binding(
                    get: { (model.reviewingDay ?? model.snapshot.day).startDate },
                    set: { model.reviewingDay = DayKey($0) }), displayedComponents: .date)
                Spacer()
                Button("Done") { model.reviewingDay = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Space.lg)
            DayCloseView(day: model.reviewingDay ?? model.snapshot.day)
                .id(model.reviewingDay)
        }
        .frame(width: 560, height: 600)
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
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Day review").font(Typo.title)
                    Text(day.rawValue).font(Typo.body).foregroundStyle(.secondary)
                }
                if let error = actionError ?? loadError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(Typo.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Refresh") { actionError = nil; reload() }
                        .buttonStyle(.glass).font(Typo.body)
                }
                if let review {
                    summary(review.summary)
                    if review.offers.isEmpty {
                        Text("No unfinished work waiting for a decision.")
                            .font(Typo.body).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Unfinished work").font(Typo.heading)
                            Text(day < .today
                                 ? "Choose what belongs today. Nothing is added automatically."
                                 : "Review this work on a later day to accept it. You can dismiss it now.")
                                .font(Typo.body).foregroundStyle(.secondary)
                            ForEach(review.offers) { row in offer(row) }
                        }
                    }
                    if !review.decisions.isEmpty {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Reviewed").font(Typo.heading)
                            ForEach(review.decisions, id: \.sourceTaskId) { decision in
                                let title = review.summary.tasks.first { $0.id == decision.sourceTaskId }?.title ?? "Task"
                                Text(decision.decision == .accepted
                                     ? "\(title) · Accepted for \(decision.destinationDay?.rawValue ?? "a later day")"
                                     : "\(title) · Dismissed")
                                    .font(Typo.body).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if status == nil, loadError == nil {
                    ProgressView("Loading day review").font(Typo.body)
                } else if loadError == nil {
                    Text(statusText).font(Typo.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("\(Format.duration(summary.focusedSeconds)) focused").font(Typo.focus).monospacedDigit()
            Text("\(summary.doneCount) done · \(summary.tasks.filter { $0.status.isOpen }.count) unfinished")
                .font(Typo.body).monospacedDigit()
            Text("\(summary.plannedMinutes)m planned · \(summary.commitment == nil ? "Derived from recorded tasks" : "At commitment")")
                .font(Typo.body).foregroundStyle(.secondary).monospacedDigit()
            Text(summary.skippedBreakCount.map { "\($0) skipped breaks" } ?? "Skipped breaks unavailable")
                .font(Typo.body).foregroundStyle(.secondary).monospacedDigit()
            Text("Saved when the day closed. Later carry decisions keep this summary.")
                .font(Typo.meta).foregroundStyle(.secondary)
        }
    }

    private func offer(_ row: TaskRow) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(row.task.title).font(Typo.body).fixedSize(horizontal: false, vertical: true)
            Text("\(row.category.name) · \(row.task.blockMinutes)m\(row.task.strict ? " · Strict" : "")")
                .font(Typo.meta).foregroundStyle(.secondary)
            if !row.task.notes.isEmpty {
                Text(row.task.notes).font(Typo.body).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack(spacing: Space.sm) {
                Button("Accept today") {
                    decide { _ = try model.store.carryTask(row.id, to: .today) }
                }
                .disabled(day >= .today)
                .help(day >= .today ? "You can accept this work on a later day." : "Copy this work into today's plan.")
                .accessibilityLabel("Accept \(row.task.title) for today")
                Button("Dismiss") { decide { _ = try model.store.dismissCarry(row.id) } }
                    .help("Leave this work on its original day without adding it to another plan.")
                    .accessibilityLabel("Dismiss unfinished work \(row.task.title)")
            }
            .font(Typo.body)
            .buttonStyle(.glass)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: Radius.card))
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
