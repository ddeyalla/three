import Foundation
import Testing
import ThreeCore
@testable import ThreeApp

@MainActor
struct ReviewNavigationTests {
    private func model() throws -> AppModel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("three-review-nav-\(UUID().uuidString)/db.sqlite")
        return AppModel(store: try Store(url: url), notifications: TimerNotificationDelivery(
            removePending: { _ in }, removeDelivered: { _ in }, add: { _, _ in }
        ), runsSystemEffects: false)
    }

    @Test func listsAreOrderedTodayUpcomingInboxThenDoneAndTags() {
        #expect(Destination.ordered == [.today, .upcoming, .inbox, .done, .tags])
        #expect(Set(Destination.ordered) == Set(Destination.allCases))
        #expect(Destination(rawValue: "history") == nil)
        #expect(Destination(rawValue: "trends") == nil)
        #expect(ReviewSection.allCases == [.day, .history, .trends])
    }

    @Test func choosingADayOpensTheReviewSheetOnDay() throws {
        let model = try model()
        #expect(model.reviewSection == nil)
        model.openReview(.trends)
        #expect(model.reviewSection == .trends)
        model.reviewingDay = DayKey("2026-11-01")
        #expect(model.reviewSection == .day)
        model.closeReview()
        #expect(model.reviewSection == nil)
        #expect(model.reviewingDay == nil)
    }

    @Test func recoveryReviewClosesTheReviewSheet() throws {
        let model = try model()
        model.reviewingDay = DayKey("2026-11-01")
        model.reviewRecovery()
        #expect(model.reviewingRecovery)
        #expect(model.reviewSection == nil)
        #expect(model.reviewingDay == nil)
    }
}
