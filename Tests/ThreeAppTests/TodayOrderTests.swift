import Foundation
import Testing
import ThreeCore
@testable import ThreeApp

struct TodayOrderTests {
    /// A day of `open` live tasks named A, B, C… with a dropped task sitting between the first two,
    /// so the drop maths has to count the same rows as `Store.moveTask`.
    private func day(open: Int) throws -> (Store, [String: String]) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("three-order-\(UUID().uuidString).sqlite")
        let store = try Store(url: url)
        let titles = ["A", "Dropped"] + ["B", "C", "D"].prefix(open - 1)
        for title in titles { try store.addTask(NewTask(title: title, category: "Coding", blockMinutes: 30), source: .app) }
        let rows = try store.snapshot().tasks
        try store.setTaskStatus(rows.first { $0.task.title == "Dropped" }!.id, .dropped)
        return (store, Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.task.title) }))
    }

    private func liveTitles(_ store: Store, _ titles: [String: String]) throws -> [String] {
        try store.snapshot().tasks.filter { $0.task.status != .dropped }.map { titles[$0.id]! }
    }

    @Test(arguments: [3, 4])
    func droppingIntoEveryGapPlacesTheCardThereAndKeepsTheRest(open: Int) throws {
        for source in 0..<open {
            for gap in 0...open {
                let (store, titles) = try day(open: open)
                let before = try liveTitles(store, titles)
                let ids = try store.snapshot().tasks.filter { $0.task.status != .dropped }.map(\.id)
                let moving = before[source]

                let stays = gap == source || gap == source + 1
                let index = TodayOrder.destination(of: ids[source], gap: gap, in: ids)
                #expect((index == nil) == stays, "\(moving) into gap \(gap): only the card's own edges are no-ops")
                guard let index, !stays else { continue }
                try store.moveTask(ids[source], to: index)

                var expected = before.filter { $0 != moving }
                let above = gap == 0 ? nil : before[gap - 1]
                expected.insert(moving, at: above.map { expected.firstIndex(of: $0)! + 1 } ?? 0)
                #expect(try liveTitles(store, titles) == expected, "\(moving) dropped into gap \(gap) of \(before)")
                #expect(try store.snapshot().tasks.contains { titles[$0.id] == "Dropped" && $0.task.status == .dropped })
            }
        }
    }

    @Test func aTaskThatLeftTheListDuringTheDragIsNotMoved() {
        #expect(TodayOrder.destination(of: "gone", gap: 0, in: ["a", "b"]) == nil)
        #expect(TodayOrder.destination(of: "a", gap: 99, in: ["a", "b"]) == 1)
        #expect(TodayOrder.destination(of: "b", gap: -3, in: ["a", "b"]) == 0)
    }

    @Test func theGapFollowsCardMiddlesByIdentity() {
        let frames: [String: CGRect] = [
            "a": CGRect(x: 0, y: 0, width: 300, height: 40),
            "b": CGRect(x: 0, y: 48, width: 300, height: 40),
            "c": CGRect(x: 0, y: 96, width: 300, height: 120),
            "stale": CGRect(x: 0, y: -100, width: 300, height: 40),
        ]
        let ids = ["a", "b", "c"]
        #expect(TodayOrder.gap(at: -20, ids: ids, frames: frames) == 0)
        #expect(TodayOrder.gap(at: 19, ids: ids, frames: frames) == 0)
        #expect(TodayOrder.gap(at: 21, ids: ids, frames: frames) == 1)
        #expect(TodayOrder.gap(at: 92, ids: ids, frames: frames) == 2)
        #expect(TodayOrder.gap(at: 140, ids: ids, frames: frames) == 2)
        #expect(TodayOrder.gap(at: 160, ids: ids, frames: frames) == 3)
        #expect(TodayOrder.gap(at: 900, ids: ids, frames: frames) == 3)
        #expect(TodayOrder.gap(at: 30, ids: ["b", "a", "c"], frames: frames) == 1, "a reload reorders IDs, frames stay keyed")
    }

    @MainActor @Test func theDialFitsThePaneWithinItsReadableRange() {
        #expect(DialView.diameter(fitting: CGSize(width: 360, height: 300)) == 240)
        #expect(DialView.diameter(fitting: CGSize(width: 2000, height: 2000)) == 400)
        let compact = DialView.diameter(fitting: CGSize(width: 360, height: 568))
        #expect(compact <= 360 - 48)
        #expect(compact > 240)
        #expect(DialView.diameter(fitting: CGSize(width: 500, height: 728)) > compact)
    }
}
