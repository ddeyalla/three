import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// A Today card being dragged. Its own type keeps it apart from pane drags and from other apps.
struct TodayTaskDrag: Codable, Transferable {
    let taskId: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.deyalla.three.today-task", conformingTo: .data))
    }
}

/// Reordering maths over Today's task IDs, in the order `Store.moveTask` counts them.
enum TodayOrder {
    /// The gap a point falls in: the number of cards whose middle sits above it.
    static func gap(at y: CGFloat, ids: [String], frames: [String: CGRect]) -> Int {
        ids.filter { frames[$0].map { $0.midY < y } ?? false }.count
    }

    /// The index `id` ends up at when dropped into `gap`, or nil when it would stay put or is gone.
    static func destination(of id: String, gap: Int, in ids: [String]) -> Int? {
        guard let source = ids.firstIndex(of: id) else { return nil }
        let gap = min(max(gap, 0), ids.count)
        let index = gap > source ? gap - 1 : gap
        return index == source ? nil : index
    }
}

/// Where keyboard focus sits on the Today list, so Edit → Move Task never guesses its target.
enum TodayFocus: Hashable {
    case card(String)
    case entry
}

private struct TodayFocusKey: FocusedValueKey { typealias Value = TodayFocus }
private struct TodayListKey: FocusedValueKey { typealias Value = Bool }

extension FocusedValues {
    var todayFocus: TodayFocus? {
        get { self[TodayFocusKey.self] }
        set { self[TodayFocusKey.self] = newValue }
    }

    /// Set while Today is on screen in the key main window.
    var todayList: Bool? {
        get { self[TodayListKey.self] }
        set { self[TodayListKey.self] = newValue }
    }
}

/// Edit → Move Task Up and Down: the focused Today card, else the task you selected on Today.
struct TodayMoveCommands: View {
    let model: AppModel
    @FocusedValue(\.todayFocus) private var focus
    @FocusedValue(\.todayList) private var listShown

    private var target: String? {
        guard listShown == true, model.destination == .today else { return nil }
        switch focus {
        case .card(let id)?: return id
        case .entry?: return nil
        case nil: return model.selectedTaskId
        }
    }

    var body: some View {
        Button("Move Task Up") { target.map { model.moveTodayTask($0, by: -1) } }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(target.map { !model.canMoveTodayTask($0, by: -1) } ?? true)
        Button("Move Task Down") { target.map { model.moveTodayTask($0, by: 1) } }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(target.map { !model.canMoveTodayTask($0, by: 1) } ?? true)
    }
}
