import Foundation
import Observation
import ThreeCore
import UserNotifications

@MainActor
@Observable
final class PlanningController {
    let store: Store
    private(set) var settings: PlanningSettings
    private(set) var lastRun: PlanningRun?
    private(set) var checking = false
    var error: String?
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    @ObservationIgnored private let deliverNotice: @MainActor (PlanningNotice) -> Void
    @ObservationIgnored private var command: PlanningSupervisor?
    @ObservationIgnored private let helper: URL
    @ObservationIgnored private var lastCheck: Date?
    @ObservationIgnored private var shuttingDown = false
    @ObservationIgnored private var cancellationRequested = false
    @ObservationIgnored private var testRequested = false

    init(store: Store, helper: URL? = nil, deliverNotice: @escaping @MainActor (PlanningNotice) -> Void = PlanningController.notify) throws {
        self.store = store
        self.helper = helper ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/three")
        self.deliverNotice = deliverNotice
        settings = try store.planningSettings()
        lastRun = try store.latestPlanningRun()
    }

    func refresh() {
        do {
            settings = try store.planningSettings()
            lastRun = try store.latestPlanningRun()
        } catch { self.error = error.localizedDescription }
    }

    func save(_ settings: PlanningSettings) {
        do {
            try store.setPlanningSettings(settings)
            error = nil
            refresh()
        } catch { self.error = error.localizedDescription }
    }

    func check(now: Date, test: Bool = false) {
        guard !shuttingDown else { return }
        guard task == nil else {
            if test {
                if checking { error = "A planning command is already running." }
                else { testRequested = true; checking = true }
            }
            return
        }
        if !test, let lastCheck, now >= lastCheck, now.timeIntervalSince(lastCheck) < 1 { return }
        lastCheck = now
        checking = test
        cancellationRequested = false
        let store = store
        task = Task {
            defer {
                checking = false
                task = nil
                command = nil
                if testRequested {
                    testRequested = false
                    check(now: Date(), test: true)
                }
            }
            do {
                let run = try await Task.detached {
                    try store.recoverPlanningRun()
                    return try store.claimPlanningRun(trigger: test ? .test : .scheduled, now: now)
                }.value
                refresh()
                if let run, run.status == .running {
                    checking = true
                    error = nil
                    let command = PlanningSupervisor()
                    self.command = command
                    if shuttingDown || cancellationRequested { command.cancel() }
                    let directory = FileManager.default.homeDirectoryForCurrentUser
                    let helper = self.helper
                    let result = await Task.detached {
                        command.execute(run: run, helper: helper,
                                        database: URL(fileURLWithPath: store.db.path), directory: directory)
                    }.value
                    if let result {
                        try await Task.detached { try store.finishPlanningRun(run.id, result: result) }.value
                    }
                    refresh()
                }
                if let notice = try store.takePlanningNotice(day: .today) { deliverNotice(notice) }
            } catch {
                self.error = error.localizedDescription
                refresh()
            }
        }
    }

    func cancel() {
        cancellationRequested = true
        testRequested = false
        command?.cancel()
    }

    func shutdown() async {
        shuttingDown = true
        command?.cancel()
        await task?.value
    }

    private static func notify(_ notice: PlanningNotice) {
        let content = UNMutableNotificationContent()
        content.title = notice.draftReady ? "Today's plan is ready" : "Your day still needs a plan"
        content.body = notice.draftReady ? "Review the draft in Three, then Commit when ready." : "Open Planning in Settings for the command result, or plan today yourself."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "planning.\(notice.day)", content: content, trigger: nil)) { _ in }
    }
}
