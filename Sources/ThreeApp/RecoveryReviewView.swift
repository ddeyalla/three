import SwiftUI
import ThreeCore

struct RecoveryEntry: View {
    let controller: SleepRecoveryController
    let review: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let error = controller.error {
                Text(error).font(Typo.meta).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.sm) {
                Button("Review interrupted focus", action: review)
                if controller.needsRetry {
                    Button("Retry") { controller.retry() }
                }
            }
            .font(Typo.body)
            .buttonStyle(.glass)
        }
    }
}

struct RecoveryReviewView: View {
    @Bindable var controller: SleepRecoveryController
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Interrupted focus").font(Typo.focus)
                    Spacer()
                    Button("Later", action: dismiss)
                        .keyboardShortcut(.cancelAction)
                        .help("Leave the recovery decision pending.")
                }
                .font(Typo.body)
                .buttonStyle(.glass)

                if let error = controller.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(Typo.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { controller.retry() }
                        .font(Typo.body).buttonStyle(.glass)
                }
                if let review = controller.reviews.first {
                    reviewContent(review)
                } else if controller.status?.observing != nil {
                    Text("The interruption is still being observed. Review it after returning.")
                        .font(Typo.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if controller.error == nil {
                    Text("No interrupted focus waiting for a decision.")
                        .font(Typo.body).foregroundStyle(.secondary)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 320, idealWidth: 420, minHeight: 240)
        .task { controller.refresh() }
    }

    private func reviewContent(_ review: RecoveryReview) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(review.gap.clockReliable ? "\(Format.duration(review.gap.awaySeconds)) away during focus" : "Review interrupted focus time")
                    .font(Typo.body).monospacedDigit()
                Text("Keep the recorded time, or remove the unpaused absence. Nothing changes until you choose.")
                    .font(Typo.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(review.sessions) { item in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(item.taskTitle ?? "Focus block").font(Typo.heading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(item.session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(item.session.isRunning ? "Current block" : "Saved block")")
                        .font(Typo.meta).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(review.gap.clockReliable ? "\(Format.duration(item.eligibleSeconds)) eligible to trim" : "Trim unavailable")
                        .font(Typo.body).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if !review.gap.clockReliable {
                Text("The clock or observation order changed. Trim is unavailable because the absence cannot be measured reliably.")
                    .font(Typo.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.sm) { decisionButtons(review) }
                VStack(alignment: .leading, spacing: Space.sm) { decisionButtons(review) }
            }
            .font(Typo.body)
            .buttonStyle(.glass)
            if controller.reviews.count > 1 {
                Text("\(controller.reviews.count - 1) more interruptions waiting")
                    .font(Typo.meta).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func decisionButtons(_ review: RecoveryReview) -> some View {
        Button("Keep recorded time") { controller.decide(review.id, .keep) }
            .accessibilityLabel("Keep recorded focus time for this interruption")
        Button("Trim \(Format.duration(review.eligibleSeconds))") { controller.decide(review.id, .trim) }
            .disabled(!review.gap.clockReliable || controller.error != nil)
            .accessibilityLabel("Trim \(Format.duration(review.eligibleSeconds)) of unpaused absence")
    }
}
