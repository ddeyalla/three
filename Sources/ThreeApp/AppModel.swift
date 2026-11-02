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
    private(set) var inbox: [TaskRow] = []
    private(set) var upcoming: [DaySnapshot] = []
    private(set) var logbook: [LoggedDay] = []
    private(set) var tagSummaries: [TagSummary] = []
    private(set) var deferredReflections: [DeferredReflection] = []
    private(set) var reflectionPresentation: ReflectionPresentation?
    var destination: Destination = .today
    /// The card opened in place in Inbox, Upcoming or Done, or the tag opened in Tags.
    var expandedTaskId: String?
    /// Bumped by ⌘N. The next quick-add field on screen claims it and takes focus.
    var quickAddRequest = 0
    var quickAddPending = false

    @ObservationIgnored private var signalToken: Int32 = 0
    @ObservationIgnored private var ticker: Timer?
    /// The block (session + planned length) whose end already opened the panel.
    /// Extending changes the length, which re-arms it, whoever extended.
    @ObservationIgnored private var reflectedBlock: String?
    @ObservationIgnored private var scheduledNotification: (id: String, end: Date)?
    @ObservationIgnored private var reflectionNote = ""
    @ObservationIgnored lazy var reflection = ReflectionPanelController(model: self)

    init() {
        do {
            store = try Store()
            snapshot = try store.snapshot()
            inbox = try store.inbox()
            upcoming = try store.upcoming()
            logbook = try store.logbook()
            tagSummaries = try store.tagSummaries()
            deferredReflections = try store.deferredReflections()
        } catch {
            fatalError("Three can't open its database: \(error)")
        }
        // THREE_OPEN=inbox|upcoming|done|tags opens on that view, for screenshots and scripts.
        if let open = ProcessInfo.processInfo.environment["THREE_OPEN"], let d = Destination(rawValue: open) { destination = d }
        signalToken = ChangeSignal.observe { [weak self] in self?.reload() }
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common keeps the clock running while a menu is open.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // A notification left from before a relaunch may be stale; reconcile schedules a fresh one if needed.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        reconcile()
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
        guard let row = selectedTask else { return snapshot.preferences.sessionMinutes }
        let left = Int((row.blockSeconds - row.focusedSeconds) / 60)
        return left >= 5 ? min(left, snapshot.preferences.sessionMinutes) : snapshot.preferences.sessionMinutes
    }

    // MARK: Loop

    private func tick() {
        now = Date()
        if snapshot.day != DayKey(now) { reload() }
        try? store.finishBreakIfDue(now: now)
        reconcileReflection()
        if case .live(let prompt, _) = reflectionPresentation, now >= prompt.deadline {
            do {
                try store.deferReflection(prompt, note: reflectionNote, now: now)
                hideReflection()
                reload()
            } catch {
                self.error = error.localizedDescription
            }
        }
        if let running, running.kind == .focus, !running.isPaused,
           running.remaining(at: now) <= 0, reflectedBlock != blockKey(running), reflectionPresentation == nil {
            reflectedBlock = blockKey(running)
            if UserDefaults.standard.object(forKey: "chime") as? Bool ?? true { NSSound(named: "Glass")?.play() }
            showReflection(.live(ReflectionPrompt(session: running, openedAt: now), task: runningTask))
        }
    }

    func reload() {
        let selectedBefore = selectedTask?.id
        defer { if selectedTask?.id != selectedBefore { dialOverride = nil } }
        do {
            snapshot = try store.snapshot(for: DayKey(Date()))
            inbox = try store.inbox()
            upcoming = try store.upcoming()
            logbook = try store.logbook()
            tagSummaries = try store.tagSummaries()
            deferredReflections = try store.deferredReflections()
            if let id = selectedTaskId, !snapshot.tasks.contains(where: { $0.id == id && $0.task.status.isOpen }) {
                selectedTaskId = nil
            }
            reconcile()
            reconcileReflection()
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

    @discardableResult
    func perform(_ action: () throws -> Void) -> Bool {
        let succeeded: Bool
        do {
            try action()
            error = nil
            succeeded = true
        } catch {
            self.error = error.localizedDescription
            succeeded = false
        }
        reload()
        return succeeded
    }

    func start(_ task: TaskRow? = nil) {
        let target = task ?? selectedTask
        // The dial shows the selected task's length; any other task works out its own.
        let minutes = target?.id == selectedTask?.id ? dialMinutes : nil
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
        showReflection(.live(ReflectionPrompt(session: running, openedAt: Date()), task: runningTask))
    }

    private func blockKey(_ s: Session) -> String { "\(s.id)/\(s.plannedSeconds)/\(s.plannedEnd.timeIntervalSince1970)" }

    func reviewReflection(_ saved: DeferredReflection) {
        guard reflectionPresentation == nil else { return }
        showReflection(.saved(saved))
    }

    func reflectionActivity(note: String) {
        guard case .live(let prompt, let task) = reflectionPresentation else { return }
        reflectionNote = note
        reflectionPresentation = .live(ReflectionPrompt(session: prompt.session, openedAt: Date()), task: task)
    }

    func dismissReflection(_ saved: DeferredReflection) {
        if perform({ try store.dismissDeferredReflection(saved.id) }), reflectionPresentation?.session.id == saved.id {
            hideReflection()
        }
    }

    func closeReflection() {
        if case .saved(let saved) = reflectionPresentation {
            dismissReflection(saved)
        } else {
            hideReflection()
        }
    }

    func hideReflection() {
        reflectionPresentation = nil
        reflection.hide()
    }

    private func showReflection(_ presentation: ReflectionPresentation) {
        reflectionPresentation = presentation
        reflectionNote = presentation.session.note ?? ""
        reflection.show(presentation)
    }

    private func reconcileReflection() {
        switch reflectionPresentation {
        case .live(let prompt, _) where !prompt.matches(running):
            hideReflection()
            if running?.isPaused == true { reflectedBlock = nil }
        case .saved(let saved) where !deferredReflections.contains(where: { $0.id == saved.id }):
            hideReflection()
        default:
            break
        }
    }

    func select(_ row: TaskRow) {
        selectedTaskId = row.id
        dialOverride = nil
    }

    func toggleExpanded(_ row: TaskRow) {
        expandedTaskId = expandedTaskId == row.id ? nil : row.id
    }

    /// Every task the app knows about: today, the inbox and the week ahead.
    var allTasks: [TaskRow] { snapshot.tasks + inbox + upcoming.flatMap(\.tasks) }

    func task(_ id: String?) -> TaskRow? {
        guard let id else { return nil }
        return allTasks.first { $0.id == id } ?? (snapshot.runningTask?.id == id ? snapshot.runningTask : nil)
    }

    /// The day a task is planned for, or nil for the inbox.
    func day(of id: String) -> DayKey? {
        if snapshot.tasks.contains(where: { $0.id == id }) { return snapshot.day }
        return upcoming.first { $0.tasks.contains { $0.id == id } }?.day
    }

    func schedule(_ row: TaskRow, on day: DayKey?) {
        perform { try store.schedule(row.id, on: day) }
    }

    var liveCategories: [ThreeCore.Category] { snapshot.categories.filter { !$0.archived } }

    var liveTags: [Tag] { tagSummaries.map(\.tag).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

    /// Quick add: `#category`, a duration and a day word override the defaults. Returns whether a task was added.
    @discardableResult
    func capture(_ text: String, defaultDay: DayKey?) -> Bool {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let quick = QuickAdd.parse(text, categories: liveCategories.map(\.name), today: snapshot.day)
        guard !quick.title.isEmpty else {
            error = "Give the task a title, then add #category, a length or a day after it."
            return false
        }
        guard let fallback = liveCategories.first else { return false }
        let new = NewTask(title: quick.title, category: quick.category ?? fallback.name,
                          blockMinutes: quick.minutes ?? snapshot.preferences.defaultBlockMinutes, tags: quick.tags)
        let day: DayKey? = switch quick.when {
        case .day(let d)?: d
        case .inbox?: nil
        case nil: defaultDay
        }
        perform {
            if let day { try store.addTask(new, day: day, source: .app) } else { try store.addToInbox(new, source: .app) }
        }
        return error == nil
    }
}

enum ReflectionPresentation {
    case live(ReflectionPrompt, task: TaskRow?)
    case saved(DeferredReflection)

    var session: Session {
        switch self {
        case .live(let prompt, _): prompt.session
        case .saved(let saved): saved.session
        }
    }

    var task: TaskRow? {
        switch self {
        case .live(_, let task): task
        case .saved(let saved): saved.task
        }
    }

    var isSaved: Bool {
        if case .saved = self { return true }
        return false
    }
}

/// What the tasks pane shows.
enum Destination: String, Hashable, CaseIterable {
    case today, inbox, upcoming, done, tags

    var title: String { rawValue.capitalized }
}
