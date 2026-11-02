import Foundation
import Observation
import CoreTransferable
import UniformTypeIdentifiers

enum WorkspacePane: String, CaseIterable, Codable, Identifiable, Transferable {
    case tasks, now, timeline

    var id: Self { self }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .now: "Now"
        case .timeline: "Timeline"
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.deyalla.three.workspace-pane", conformingTo: .data))
    }
}

@MainActor @Observable
final class WorkspaceLayout {
    private(set) var panes: [WorkspacePane]
    private let defaults: UserDefaults
    static let preferenceKey = "workspacePaneOrder"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.preferenceKey) ?? []
        let decoded = stored.compactMap(WorkspacePane.init(rawValue:))
        panes = stored.count == WorkspacePane.allCases.count
            && Set(decoded) == Set(WorkspacePane.allCases) ? decoded : WorkspacePane.allCases
    }

    func move(_ pane: WorkspacePane, to destination: WorkspacePane) {
        guard let source = panes.firstIndex(of: pane),
              let target = panes.firstIndex(of: destination), source != target else { return }
        var updated = panes
        updated.remove(at: source)
        updated.insert(pane, at: target)
        panes = updated
        defaults.set(panes.map(\.rawValue), forKey: Self.preferenceKey)
    }

    func canMove(_ pane: WorkspacePane, by offset: Int) -> Bool {
        guard let index = panes.firstIndex(of: pane), (-1...1).contains(offset), offset != 0 else { return false }
        return panes.indices.contains(index + offset)
    }

    func move(_ pane: WorkspacePane, by offset: Int) {
        guard canMove(pane, by: offset), let index = panes.firstIndex(of: pane) else { return }
        move(pane, to: panes[index + offset])
    }

    func reset() {
        panes = WorkspacePane.allCases
        defaults.removeObject(forKey: Self.preferenceKey)
    }
}
