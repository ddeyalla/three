import Foundation
import Testing
import ThreeCore
@testable import ThreeApp

@MainActor struct HistoryMonthTests {
    @Test func gregorianMonthIdentityMatchesPickerAndArrowBounds() throws {
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        let parse = ISO8601DateFormatter()
        let first = try #require(HistoryMonth(containing: parse.date(from: "2026-11-01T12:00:00Z")!, timeZone: zone))
        let last = try #require(HistoryMonth(containing: parse.date(from: "2026-11-30T12:00:00Z")!, timeZone: zone))
        #expect(first.calendar.identifier == .gregorian)
        #expect(first.key == last.key)
        #expect(first.from == last.from && first.through == last.through)
        #expect(first.from == DayKey("2026-11-01"))
        #expect(first.through == DayKey("2026-11-30"))
        let september = try #require(HistoryMonth(containing: parse.date(from: "2026-09-06T12:00:00Z")!, timeZone: zone))
        let nextDate = try #require(september.shifted(by: 1))
        let next = try #require(HistoryMonth(containing: nextDate, timeZone: zone))
        #expect(next.key == "2026-10")
        #expect(next.key != september.key)
        #expect(next.from == DayKey("2026-10-01"))
        #expect(next.through == DayKey("2026-10-31"))
    }
}
