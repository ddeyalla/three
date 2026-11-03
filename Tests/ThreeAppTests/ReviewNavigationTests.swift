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

    @Test func dayStepsMoveBetweenClosedDays() throws {
        let closed = try ["2026-11-02", "2026-10-30", "2026-10-28"].map { try #require(DayKey($0)) }
        let day = try #require(DayKey("2026-10-30"))
        #expect(ReviewDays.previous(before: day, closed: closed) == DayKey("2026-10-28"))
        #expect(ReviewDays.next(after: day, closed: closed) == DayKey("2026-11-02"))
        #expect(ReviewDays.previous(before: closed[2], closed: closed) == nil)
        #expect(ReviewDays.next(after: closed[0], closed: closed) == nil)
        // A day that never closed (today) steps back to the latest closed day.
        #expect(ReviewDays.previous(before: try #require(DayKey("2026-11-03")), closed: closed) == closed[0])
    }
}
