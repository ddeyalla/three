import Foundation
import Testing
@testable import ThreeCore

struct DayKeyCivilTests {
    @Test func civilDatesValidateAndAdvanceWithoutLocalMidnight() throws {
        for (raw, next) in [("2026-04-24", "2026-04-25"), ("2011-12-30", "2011-12-31")] {
            let day = try #require(DayKey(raw))
            #expect(day.adding(days: 1).rawValue == next)
            #expect(day.adding(days: 1).adding(days: -1) == day)
            #expect(try JSONDecoder().decode(DayKey.self, from: JSONEncoder().encode(day)) == day)
            #expect(day.startDate.timeIntervalSince1970.isFinite)
        }
        #expect(DayKey("2026-02-30") == nil)
        #expect(DayKey("2026-4-24") == nil)
    }

    @Test func fullHistoryReportRoundTripsInTheProcessTimeZone() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("three-civil-codec-\(UUID().uuidString)/db.sqlite")
        let store = try Store(url: path)
        for (from, through, count) in [("2026-04-01", "2026-04-30", 30), ("2011-12-01", "2011-12-31", 31)] {
            let report = try store.historyReport(from: #require(DayKey(from)), through: #require(DayKey(through)))
            let encoded = try JSONEncoder().encode(report)
            let decoded = try JSONDecoder().decode(HistoryReport.self, from: encoded)
            #expect(decoded.days.map(\.day) == report.days.map(\.day))
            #expect(decoded.days.count == count)
        }
    }
}
