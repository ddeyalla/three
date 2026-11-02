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
    /// Bumped by `requestQuickAdd` when the list on screen stays; its field claims the pending request.
    /// A list that appears instead claims `quickAddPending` on appear.
    var quickAddRequest = 0
    var quickAddPending = false
    /// The blocker as this Mac enforces it, re-read on every change, at the policy's next change and every few seconds.
    private(set) var blocking: BlockingState
    /// The Settings tab to show, so Blocking Settings… can open it there.
    var settingsTab: SettingsTab = .timer
    /// Set by the menu bar's Set Up Chrome…; the Blocking tab claims it and opens the setup sheet.
    var chromeSetupRequested = false

    @ObservationIgnored private var signalToken: Int32 = 0
    @ObservationIgnored private var ticker: Timer?
    /// The block (session + planned length) whose end already opened the panel.
    /// Extending changes the length, which re-arms it, whoever extended.
    @ObservationIgnored private var reflectedBlock: String?
    @ObservationIgnored private var scheduledNotification: (id: String, end: Date)?
    @ObservationIgnored private var reflectionNote = ""
    @ObservationIgnored lazy var reflection = ReflectionPanelController(model: self)
    @ObservationIgnored lazy var appBlocker = AppBlocker(model: self)
    @ObservationIgnored lazy var blockOverlay = BlockOverlayController(model: self)
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []

    init() {
        do {
            store = try Store()
            snapshot = try store.snapshot()
            inbox = try store.inbox()
            upcoming = try store.upcoming()
            logbook = try store.logbook()
            tagSummaries = try store.tagSummaries()
            deferredReflections = try store.deferredReflections()
            blocking = BlockingState(status: try store.blockStatus(), now: Date())
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
        // A new time zone, a changed clock or a wake can move every focus-hours boundary at once.
        let local = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        systemObservers = [
            local.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            },
            local.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            },
        ]
        appBlocker.start()
        refreshBlocking()
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

    /// Today's list in the order `Store.moveTask` counts: every task except dropped ones.
    var todayRows: [TaskRow] { snapshot.tasks.filter { $0.task.status != .dropped } }

    /// "2 of 3 done", "1h 28m focused": the day so far, for Today's summary and Now's all-done state.
    var dayProgress: [String] {
        var parts: [String] = []
        if snapshot.activeTaskCount > 0 { parts.append("\(snapshot.doneCount) of \(snapshot.activeTaskCount) done") }
        let focus = snapshot.focusSeconds(at: now)
        if focus >= 60 { parts.append("\(Format.duration(focus)) focused") }
        return parts
    }

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
        // A clock set back by more than a tick leaves the last policy in the future, so read it again.
        if now >= blockingRefreshDue || now < blocking.now.addingTimeInterval(-1) { refreshBlocking() }
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
        refreshBlocking()
    }

    /// Browser heartbeats are written silently, so connections are re-read this often even when nothing else changes.
    private static let blockingRecheck: TimeInterval = 15

    private var blockingRefreshDue: Date {
        min(blocking.policy.nextChange ?? .distantFuture, blocking.now.addingTimeInterval(Self.blockingRecheck))
    }

    /// Re-reads the blocker and applies it: hides apps now in force and closes an overlay whose rule no longer is.
    func refreshBlocking() {
        NSTimeZone.resetSystemTimeZone()
        let at = Date()
        do {
            blocking = BlockingState(status: try store.blockStatus(now: at, calendar: .current), now: at,
                                     failedAppRuleIDs: appBlocker.failedRuleIDs)
        } catch {
            self.error = error.localizedDescription
            return
        }
        appBlocker.enforce(blocking)
        blockOverlay.reconcile(with: blocking)
    }

    func updateAppBlockingFailures(_ ids: Set<String>) {
        blocking.failedAppRuleIDs = ids
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
        if reflectionPresentation != nil {
            reflection.activate()
            return
        }
        guard let running, running.kind == .focus else { return }
        reflectedBlock = blockKey(running)
        showReflection(.live(ReflectionPrompt(session: running, openedAt: Date()), task: runningTask), takeFocus: true)
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

    private func showReflection(_ presentation: ReflectionPresentation, takeFocus: Bool = false) {
        reflectionPresentation = presentation
        reflectionNote = presentation.session.note ?? ""
        reflection.show(presentation, takeFocus: takeFocus || presentation.isSaved)
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

    /// Opens the panel where a person asks for one rule for five minutes. Only ever from Three's own UI.
    func requestUnblock(_ rule: BlockRule) {
        blockOverlay.present(.init(rule: rule, appName: rule.bundleID == nil ? nil : rule.name), mode: .unblock)
    }

    func select(_ row: TaskRow) {
        selectedTaskId = row.id
        dialOverride = nil
    }

    /// Puts the cursor in quick add on `preferred`, or in the Inbox when that list can't take another task.
    /// Switching lists leaves the claim to the field that appears, so the outgoing list's field can't take it.
    func requestQuickAdd(on preferred: Destination? = nil) {
        let shown = destination
        if let preferred { destination = preferred }
        if ![.today, .inbox, .upcoming].contains(destination)
            || (destination == .today && snapshot.activeTaskCount >= Rules.maxTasks) {
            destination = .inbox
        }
        quickAddPending = true
        if destination == shown { quickAddRequest += 1 }
    }

    func canMoveTodayTask(_ id: String, by offset: Int) -> Bool {
        guard let index = todayRows.firstIndex(where: { $0.id == id }) else { return false }
        return todayRows.indices.contains(index + offset)
    }

    func moveTodayTask(_ id: String, by offset: Int) {
        guard canMoveTodayTask(id, by: offset), let index = todayRows.firstIndex(where: { $0.id == id }) else { return }
        perform { try store.moveTask(id, to: index + offset) }
    }

    /// A dropped card: reads the order fresh, so a reload during the drag can't shift where it lands.
    func moveTodayTask(_ id: String, toGap gap: Int) {
        guard let index = TodayOrder.destination(of: id, gap: gap, in: todayRows.map(\.id)) else { return }
        perform { try store.moveTask(id, to: index) }
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
