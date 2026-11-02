import AppKit
import Observation
import SwiftUI
import ThreeCore
import UserNotifications

/// The app's single source of UI state: the latest snapshot plus a 1 Hz clock.
/// It also owns the side effects other processes can't: notifications, sounds, the reflection panel.
@MainActor
@Observable
final class AppModel {
    let store: Store
    private(set) var snapshot: DaySnapshot
    private(set) var now = Date()
    var error: String?
    /// Minutes dragged on the dial while idle; nil follows the selected task.
    var dialOverride: Int?
    var selectedTaskId: String?

    @ObservationIgnored private var signalToken: Int32 = 0
    @ObservationIgnored private var ticker: Timer?
    /// The block (session + planned length) whose end already opened the panel.
    /// Extending changes the length, which re-arms it, whoever extended.
    @ObservationIgnored private var reflectedBlock: String?
    @ObservationIgnored private var scheduledNotification: (id: String, end: Date)?
    @ObservationIgnored lazy var reflection = ReflectionPanelController(model: self)

    init() {
        do {
            store = try Store()
            snapshot = try store.snapshot()
        } catch {
            fatalError("Three can't open its database: \(error)")
        }
        signalToken = ChangeSignal.observe { [weak self] in self?.reload() }
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common keeps the clock running while a menu is open.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        reconcile()
        Snapshotter.scheduleIfRequested(model: self)
    }

    // MARK: Derived

    var running: Session? { snapshot.running }
    var runningTask: TaskRow? { snapshot.runningTask }

    var selectedTask: TaskRow? {
        snapshot.tasks.first { $0.id == selectedTaskId && $0.task.status.isOpen } ?? snapshot.nextTask
    }

    /// The colour of whatever the timer is about.
    var accent: Color {
        if let running, running.kind == .break { return Theme.idle }
        return (runningTask ?? selectedTask)?.category.color ?? Theme.idle
    }

    var remaining: TimeInterval? { running.map { $0.remaining(at: now) } }

    /// What Start would run for: the dragged value, else the task's block left, capped at a session.
    var dialMinutes: Int {
        if let dialOverride { return dialOverride }
        guard let row = selectedTask else { return Rules.defaultSessionMinutes }
        let left = Int((row.blockSeconds - row.focusedSeconds) / 60)
        return left >= 5 ? min(left, Rules.defaultSessionMinutes) : Rules.defaultSessionMinutes
    }

    // MARK: Loop

    private func tick() {
        now = Date()
        if snapshot.day != DayKey(now) { reload() }
        try? store.finishBreakIfDue(now: now)
        if reflection.isVisible, running?.kind != .focus { reflection.hide() }
        if let running, running.kind == .focus, !running.isPaused,
           running.remaining(at: now) <= 0, reflectedBlock != blockKey(running) {
            reflectedBlock = blockKey(running)
            NSSound(named: "Glass")?.play()
            reflection.show()
        }
    }

    func reload() {
        do {
            snapshot = try store.snapshot(for: DayKey(Date()))
            if let id = selectedTaskId, !snapshot.tasks.contains(where: { $0.id == id && $0.task.status.isOpen }) {
                selectedTaskId = nil
            }
            reconcile()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Keeps the one pending notification in step with the running session, whoever changed it.
    private func reconcile() {
        let center = UNUserNotificationCenter.current()
        guard let running, !running.isPaused, running.remaining(at: Date()) > 0 else {
            if scheduledNotification != nil {
                center.removeAllPendingNotificationRequests()
                scheduledNotification = nil
            }
            return
        }
        if let s = scheduledNotification, s.id == running.id, s.end == running.plannedEnd { return }
        let content = UNMutableNotificationContent()
        if running.kind == .focus {
            content.title = "Time's up: \(runningTask?.task.title ?? "focus block")"
            content.body = "How did it go?"
        } else {
            content.title = "Break's over"
            content.body = snapshot.nextTask.map { "Next: \($0.task.title) (\($0.task.blockMinutes)m)" } ?? "Nice work today."
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, running.plannedEnd.timeIntervalSinceNow), repeats: false)
        center.removeAllPendingNotificationRequests()
        center.add(UNNotificationRequest(identifier: running.id, content: content, trigger: trigger))
        scheduledNotification = (running.id, running.plannedEnd)
    }

    // MARK: Actions

    func perform(_ action: () throws -> Void) {
        do {
            try action()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        reload()
    }

    func start(_ task: TaskRow? = nil) {
        let target = task ?? selectedTask
        let minutes = dialMinutes
        perform { try store.startFocus(taskId: target?.id, minutes: minutes) }
        selectedTaskId = nil
        dialOverride = nil
    }

    func togglePause() {
        guard let running else { return start() }
        perform { running.isPaused ? try store.resume() : try store.pause() }
    }

    func extend(_ minutes: Int) { perform { try store.extend(minutes: minutes) } }

    func stop() { perform { try store.stop() } }

    func finishEarly() {
        guard let running, running.kind == .focus else { return }
        reflectedBlock = blockKey(running)
        reflection.show()
    }

    private func blockKey(_ s: Session) -> String { "\(s.id)/\(s.plannedSeconds)" }

    func select(_ row: TaskRow) {
        selectedTaskId = row.id
        dialOverride = nil
    }
}
