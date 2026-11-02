import Foundation
import Testing
@testable import ThreeApp

@MainActor
struct WorkspaceLayoutTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "ThreeWorkspaceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func everyOrderSurvivesRelaunchAndMovesKeepAllPanes() {
        withDefaults { defaults in
            for first in WorkspacePane.allCases {
                for second in WorkspacePane.allCases where second != first {
                    let last = WorkspacePane.allCases.first { $0 != first && $0 != second }!
                    let order = [first, second, last]
                    defaults.set(order.map(\.rawValue), forKey: WorkspaceLayout.preferenceKey)
                    #expect(WorkspaceLayout(defaults: defaults).panes == order)
                    for source in order {
                        for target in order {
                            defaults.set(order.map(\.rawValue), forKey: WorkspaceLayout.preferenceKey)
                            let layout = WorkspaceLayout(defaults: defaults)
                            let targetIndex = order.firstIndex(of: target)!
                            layout.move(source, to: target)
                            #expect(layout.panes[targetIndex] == source)
                            #expect(layout.panes.filter { $0 != source } == order.filter { $0 != source })
                            #expect(Set(layout.panes) == Set(WorkspacePane.allCases))
                            #expect(layout.panes.count == 3)
                            #expect(WorkspaceLayout(defaults: defaults).panes == layout.panes)
                        }
                    }
                }
            }
        }
    }

    @Test func invalidPreferencesRestoreACompleteWorkspace() {
        withDefaults { defaults in
            let invalid: [Any] = [[], ["tasks"], ["tasks", "now", "now"],
                                  ["tasks", "now", "unknown"], ["tasks", "now", "timeline", "tasks"],
                                  "tasks,now,timeline", 42]
            for value in invalid {
                defaults.set(value, forKey: WorkspaceLayout.preferenceKey)
                #expect(WorkspaceLayout(defaults: defaults).panes == WorkspacePane.allCases)
            }
        }
    }

    @Test func menuMovesRespectEdgesAndResetPersists() {
        withDefaults { defaults in
            let layout = WorkspaceLayout(defaults: defaults)
            #expect(!layout.canMove(.tasks, by: -1))
            #expect(!layout.canMove(.timeline, by: 1))
            layout.move(.tasks, by: -1)
            layout.move(.timeline, by: 1)
            layout.move(.now, by: .max)
            #expect(layout.panes == WorkspacePane.allCases)
            layout.move(.tasks, by: 1)
            #expect(layout.panes == [.now, .tasks, .timeline])
            layout.move(.timeline, by: -1)
            #expect(layout.panes == [.now, .timeline, .tasks])
            layout.reset()
            #expect(WorkspaceLayout(defaults: defaults).panes == WorkspacePane.allCases)
        }
    }
}
