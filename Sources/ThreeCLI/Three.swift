import AppKit
import ArgumentParser
import Foundation
import ThreeCore

@main
struct Three: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "three",
        abstract: "Plan three focused tasks a day and run them on a timer.",
        subcommands: [Today.self, Status.self, Add.self, Plan.self, Commit.self, Start.self, Pause.self,
                      Resume.self, Extend.self, Stop.self, Done.self, Drop.self, Tomorrow.self, Categories.self]
    )
}

// MARK: Shared

struct Common: ParsableArguments {
    @Flag(help: "Print JSON instead of text.") var json = false
}

struct DayOption: ParsableArguments {
    @Option(help: "today, tomorrow, yesterday, or yyyy-MM-dd.") var date = "today"

    func day() throws -> DayKey {
        switch date {
        case "today": return .today
        case "tomorrow": return DayKey.today.adding(days: 1)
        case "yesterday": return DayKey.today.adding(days: -1)
        default:
            guard let d = DayKey(date) else { throw ValidationError("Use today, tomorrow, yesterday or yyyy-MM-dd.") }
            return d
        }
    }
}

/// Blocks like "90", "90m", "1h", "1h30m".
func parseMinutes(_ s: String) throws -> Int {
    let lower = s.lowercased()
    if let m = Int(lower) { return m }
    var total = 0, digits = ""
    for ch in lower {
        if ch.isNumber { digits.append(ch); continue }
        guard let n = Int(digits) else { throw ValidationError("Can't read \"\(s)\" as minutes.") }
        switch ch {
        case "h": total += n * 60
        case "m": total += n
        default: throw ValidationError("Can't read \"\(s)\" as minutes.")
        }
        digits = ""
    }
    guard digits.isEmpty, total > 0 else { throw ValidationError("Can't read \"\(s)\" as minutes.") }
    return total
}

/// A task by its 1-based position in the day's list, or by id prefix.
func resolveTask(_ ref: String, in snap: DaySnapshot) throws -> TaskRow {
    let visible = snap.tasks.filter { $0.task.status != .dropped }
    if let n = Int(ref), (1...visible.count).contains(n) { return visible[n - 1] }
    let matches = snap.tasks.filter { $0.id.lowercased().hasPrefix(ref.lowercased()) }
    guard matches.count == 1 else { throw ThreeError.noSuchTask(ref) }
    return matches[0]
}

func store() throws -> Store { try Store() }

/// Timer commands need the app to chime and reflect at block end; launch it in the background if it's closed.
/// Skipped when THREE_DB points elsewhere, since the launched app would use the default database.
func ensureAppRunning() {
    guard ProcessInfo.processInfo.environment["THREE_DB"] == nil,
          NSRunningApplication.runningApplications(withBundleIdentifier: ThreeVersion.bundleID).isEmpty else { return }
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-g", "-b", ThreeVersion.bundleID]
    try? open.run()
    open.waitUntilExit()
}

func emit<T: Encodable>(_ value: T) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    print(String(decoding: try enc.encode(value), as: UTF8.self))
}

struct TaskJSON: Encodable {
    let number: Int, id: String, title: String, category: String, blockMinutes: Int
    let focusedMinutes: Int, status: String, strict: Bool, linear: String?
}

struct SessionJSON: Encodable {
    let id: String, kind: String, taskId: String?, startedAt: Date, plannedEnd: Date
    let paused: Bool, remainingSeconds: Int
}

struct DayJSON: Encodable {
    let date: String, status: String?, plannedMinutes: Int, focusedMinutes: Int
    let tasks: [TaskJSON], running: SessionJSON?
}

func dayJSON(_ snap: DaySnapshot) -> DayJSON {
    let now = Date()
    let tasks = snap.tasks.filter { $0.task.status != .dropped }.enumerated().map { i, r in
        TaskJSON(number: i + 1, id: r.id, title: r.task.title, category: r.category.name, blockMinutes: r.task.blockMinutes,
                 focusedMinutes: Int(r.focusedSeconds / 60), status: r.task.status.rawValue, strict: r.task.strict,
                 linear: r.task.linearRef)
    }
    let running = snap.running.map {
        SessionJSON(id: $0.id, kind: $0.kind.rawValue, taskId: $0.taskId, startedAt: $0.startedAt, plannedEnd: $0.plannedEnd,
                    paused: $0.isPaused, remainingSeconds: Int($0.remaining(at: now)))
    }
    return DayJSON(date: snap.day.rawValue, status: snap.plan?.status.rawValue, plannedMinutes: snap.plannedMinutes,
                   focusedMinutes: Int(snap.focusSeconds(at: now) / 60), tasks: tasks, running: running)
}

func clock(_ seconds: TimeInterval) -> String {
    let s = Int(abs(seconds))
    return (seconds < 0 ? "+" : "") + String(format: "%02d:%02d", s / 60, s % 60)
}

func printStatus(_ snap: DaySnapshot) {
    guard let r = snap.running else { return print("Nothing running.") }
    let what = r.kind == .break ? "Break" : (snap.runningTask?.task.title ?? "Focus")
    print("\(what) · \(r.isPaused ? "paused, " : "")\(clock(r.remaining(at: Date()))) left")
}

func printDay(_ snap: DaySnapshot) {
    let status = snap.plan.map { " (\($0.status.rawValue))" } ?? ""
    print("\(snap.day)\(status) · \(snap.doneCount)/\(snap.activeTaskCount) done · \(Int(snap.focusSeconds(at: Date()) / 60))m focus · \(snap.plannedMinutes)m planned")
    let visible = snap.tasks.filter { $0.task.status != .dropped }
    if visible.isEmpty { print("  No tasks. Add one: three add \"Ship onboarding\" --cat Coding --block 90m") }
    for (i, r) in visible.enumerated() {
        let mark = switch r.task.status {
        case .done: "✓"
        case .active: "▶"
        case .carried: "→"
        default: " "
        }
        print("  \(mark) \(i + 1). \(r.task.title)  [\(r.category.name) · \(Int(r.focusedSeconds / 60))/\(r.task.blockMinutes)m]")
    }
    if snap.running != nil { print(""); printStatus(snap) }
}

// MARK: Commands

struct Today: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show a day's plan and what's running.")
    @OptionGroup var day: DayOption
    @OptionGroup var common: Common

    func run() throws {
        let snap = try store().snapshot(for: day.day())
        common.json ? try emit(dayJSON(snap)) : printDay(snap)
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "What's running right now.")
    @OptionGroup var common: Common

    func run() throws {
        let snap = try store().snapshot()
        common.json ? try emit(dayJSON(snap).running) : printStatus(snap)
    }
}

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add a task to a day.")
    @Argument var title: String
    @Option(name: [.customLong("cat"), .long], help: "Category name.") var category = "Coding"
    @Option(help: "Time block, e.g. 45, 90m, 1h30m.") var block = "60"
    @Option(help: "Linear issue, e.g. ENG-123.") var linear: String?
    @Flag(help: "No unblocking during this task's sessions.") var strict = false
    @OptionGroup var day: DayOption

    func run() throws {
        let s = try store()
        try s.addTask(NewTask(title: title, category: category, blockMinutes: parseMinutes(block),
                              strict: strict, linearRef: linear), day: day.day(), source: .cli)
        printDay(try s.snapshot(for: day.day()))
    }
}

struct Plan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Replace a day's untouched tasks.",
        discussion: "Each task is \"Title:Category:Minutes\", e.g. three plan \"Ship onboarding:Coding:90\" \"Write PRD:Writing:60\""
    )
    @Argument var tasks: [String]
    @Flag(help: "Commit the plan right away instead of leaving a draft.") var commit = false
    @OptionGroup var day: DayOption

    func run() throws {
        let parsed = try tasks.map { spec -> NewTask in
            let parts = spec.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { throw ValidationError("Use \"Title:Category:Minutes\", got \"\(spec)\".") }
            return NewTask(title: parts[0], category: parts[1], blockMinutes: try parseMinutes(parts[2]))
        }
        guard parsed.count <= Rules.maxTasks else { throw ThreeError.tooManyTasks }
        let s = try store()
        try s.setPlan(parsed, day: day.day(), source: .cli, commit: commit)
        printDay(try s.snapshot(for: day.day()))
    }
}

struct Commit: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Commit a draft plan.")
    @OptionGroup var day: DayOption

    func run() throws {
        let s = try store()
        try s.commit(day: day.day())
        printDay(try s.snapshot(for: day.day()))
    }
}

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start focusing on a task (default: the next open one).")
    @Argument(help: "Task number or id.") var task: String?
    @Option(help: "Session length, e.g. 25 or 45m.") var min: String?

    func run() throws {
        let s = try store()
        let id = try task.map { try resolveTask($0, in: s.snapshot()).id }
        try s.startFocus(taskId: id, minutes: min.map(parseMinutes))
        ensureAppRunning()
        printStatus(try s.snapshot())
    }
}

struct Pause: ParsableCommand {
    func run() throws { let s = try store(); try s.pause(); printStatus(try s.snapshot()) }
}

struct Resume: ParsableCommand {
    func run() throws { let s = try store(); try s.resume(); ensureAppRunning(); printStatus(try s.snapshot()) }
}

struct Extend: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add minutes to the running block.")
    @Argument var minutes = "5"
    func run() throws {
        let s = try store()
        try s.extend(minutes: parseMinutes(minutes))
        ensureAppRunning()
        printStatus(try s.snapshot())
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "End the running session or break.")
    func run() throws { let s = try store(); try s.stop(); printStatus(try s.snapshot()) }
}

struct Done: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Mark a task done (ends its running session).")
    @Argument(help: "Task number or id.") var task: String
    @Option(help: "One-line note for the session.") var note: String?

    func run() throws {
        let s = try store()
        let row = try resolveTask(task, in: s.snapshot())
        if try s.snapshot().running?.taskId == row.id {
            try s.finishFocus(outcome: .done, rating: .okay, note: note, markTaskDone: true)
        } else {
            try s.setTaskStatus(row.id, .done)
        }
        printDay(try s.snapshot())
    }
}

struct Drop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Drop a task from the day.")
    @Argument(help: "Task number or id.") var task: String
    func run() throws {
        let s = try store()
        try s.removeTask(resolveTask(task, in: s.snapshot()).id)
        printDay(try s.snapshot())
    }
}

struct Tomorrow: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Push a task to tomorrow.")
    @Argument(help: "Task number or id.") var task: String
    func run() throws {
        let s = try store()
        try s.pushToTomorrow(resolveTask(task, in: s.snapshot()).id)
        printDay(try s.snapshot())
    }
}

struct Categories: ParsableCommand {
    @OptionGroup var common: Common
    func run() throws {
        let cats = try store().categories()
        if common.json {
            struct C: Encodable { let name: String, color: String }
            try emit(cats.map { C(name: $0.name, color: $0.colorHex) })
        } else {
            for c in cats { print("\(c.colorHex)  \(c.name)") }
        }
    }
}
