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
                      Resume.self, Extend.self, Stop.self, Done.self, Drop.self, Tomorrow.self, Capture.self, Inbox.self,
                      Schedule.self, Upcoming.self, Logbook.self, Steps.self, Tags.self, Categories.self, Settings.self,
                      Block.self, NativeHost.self]
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

/// " @onboarding @launch", or nothing.
func tagSuffix(_ r: TaskRow) -> String { r.tags.map { " @\($0.name)" }.joined() }

/// Blocks like "90", "90m", "1h", "1h30m".
func parseMinutes(_ s: String) throws -> Int {
    guard let m = QuickAdd.parseMinutes(s), m > 0 else { throw ValidationError("Can't read \"\(s)\" as minutes.") }
    return m
}

/// A task by its 1-based position in today's list, "i2" for the inbox, or an id prefix.
func resolveTask(_ ref: String, in snap: DaySnapshot, inbox: [TaskRow] = []) throws -> TaskRow {
    let visible = snap.tasks.filter { $0.task.status != .dropped }
    if let n = Int(ref), (1...max(1, visible.count)).contains(n), n <= visible.count { return visible[n - 1] }
    if ref.lowercased().hasPrefix("i"), let n = Int(ref.dropFirst()), (1...max(1, inbox.count)).contains(n), n <= inbox.count {
        return inbox[n - 1]
    }
    let matches = (snap.tasks + inbox).filter { $0.id.lowercased().hasPrefix(ref.lowercased()) }
    guard matches.count == 1 else { throw ThreeError.noSuchTask(ref) }
    return matches[0]
}

func parseDay(_ s: String) throws -> DayKey? {
    switch s.lowercased() {
    case "inbox", "someday", "none": return nil
    case "yesterday": return DayKey.today.adding(days: -1)
    default:
        if let d = DayKey(s) { return d }
        guard case .day(let d)? = QuickAdd.parse(s, categories: []).when else {
            throw ValidationError("Use today, tomorrow, a weekday, yyyy-MM-dd or inbox.")
        }
        return d
    }
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
    let focusedMinutes: Int, status: String, strict: Bool, linear: String?, tags: [String]
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
                 linear: r.task.linearRef, tags: r.tags.map(\.name))
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
        print("  \(mark) \(i + 1). \(r.task.title)  [\(r.category.name) · \(Int(r.focusedSeconds / 60))/\(r.task.blockMinutes)m]\(tagSuffix(r))")
        for step in r.steps { print("       \(step.done ? "☑" : "☐") \(step.title)") }
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
    @Option(name: .customLong("tag"), help: "A tag, such as a product or feature. Repeat for more.") var tags: [String] = []
    @OptionGroup var day: DayOption

    func run() throws {
        let s = try store()
        try s.addTask(NewTask(title: title, category: category, blockMinutes: parseMinutes(block),
                              strict: strict, linearRef: linear, tags: tags), day: day.day(), source: .cli)
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

struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Quick add, Todoist style. Goes to the inbox unless you name a day.",
        discussion: "three capture \"Write the PRD #writing @launch 45m tomorrow\"  ·  #category, @tags, a duration, and today/tomorrow/a weekday/inbox."
    )
    @Argument(parsing: .remaining) var words: [String]

    func run() throws {
        let s = try store()
        let quick = QuickAdd.parse(words.joined(separator: " "), categories: try s.categories().filter { !$0.archived }.map(\.name))
        let prefs = try s.preferences()
        let fallback = try s.categories().first { !$0.archived }?.name ?? ""
        let new = NewTask(title: quick.title, category: quick.category ?? fallback,
                          blockMinutes: quick.minutes ?? prefs.defaultBlockMinutes, tags: quick.tags)
        switch quick.when {
        case .day(let day)?:
            try s.addTask(new, day: day, source: .cli)
            printDay(try s.snapshot(for: day))
        case .inbox?, nil:
            try s.addToInbox(new, source: .cli)
            printInbox(try s.inbox())
        }
    }
}

func printInbox(_ rows: [TaskRow]) {
    if rows.isEmpty { return print("Inbox is empty.") }
    for (i, r) in rows.enumerated() {
        print("  i\(i + 1). \(r.task.title)  [\(r.category.name) · \(r.task.blockMinutes)m]\(tagSuffix(r))")
    }
}

struct Inbox: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List unplanned tasks. Refer to them as i1, i2, …")
    @OptionGroup var common: Common
    func run() throws {
        let rows = try store().inbox()
        if common.json {
            try emit(rows.enumerated().map { i, r in
                TaskJSON(number: i + 1, id: r.id, title: r.task.title, category: r.category.name, blockMinutes: r.task.blockMinutes,
                         focusedMinutes: 0, status: r.task.status.rawValue, strict: r.task.strict, linear: r.task.linearRef,
                         tags: r.tags.map(\.name))
            })
        } else {
            printInbox(rows)
        }
    }
}

struct Schedule: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Move a task to a day, or back to the inbox.")
    @Argument(help: "Task number, i-number for the inbox, or id.") var task: String
    @Argument(help: "today, tomorrow, a weekday, yyyy-MM-dd, or inbox.") var when: String

    func run() throws {
        let s = try store()
        let row = try resolveTask(task, in: s.snapshot(), inbox: s.inbox())
        let day = try parseDay(when)
        try s.schedule(row.id, on: day)
        if let day { printDay(try s.snapshot(for: day)) } else { printInbox(try s.inbox()) }
    }
}

struct Upcoming: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "The next seven days.")
    @OptionGroup var common: Common
    func run() throws {
        let days = try store().upcoming()
        if common.json { return try emit(days.map(dayJSON)) }
        for snap in days where !snap.tasks.isEmpty {
            print(snap.day.startDate.formatted(.dateTime.weekday(.wide).month().day()))
            for r in snap.tasks where r.task.status != .dropped { print("  · \(r.task.title)  [\(r.category.name) · \(r.task.blockMinutes)m]") }
        }
    }
}

struct Steps: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "step",
        abstract: "Break a task into small steps.",
        subcommands: [AddStep.self, CheckStep.self, RemoveStep.self]
    )

    struct Ref: ParsableArguments {
        @Argument(help: "Task number, i-number, or id.") var task: String
        func row(_ s: Store) throws -> TaskRow { try resolveTask(task, in: s.snapshot(), inbox: s.inbox()) }
    }

    struct AddStep: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add")
        @OptionGroup var ref: Ref
        @Argument var title: String
        func run() throws {
            let s = try store()
            try s.addStep(to: ref.row(s).id, title: title)
            printDay(try s.snapshot())
        }
    }

    struct CheckStep: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "done", abstract: "Toggle a step by its number.")
        @OptionGroup var ref: Ref
        @Argument var number: Int
        func run() throws {
            let s = try store()
            let steps = try ref.row(s).steps
            guard (1...max(1, steps.count)).contains(number), number <= steps.count else { throw ValidationError("No step \(number).") }
            try s.setStep(steps[number - 1].id, done: !steps[number - 1].done)
            printDay(try s.snapshot())
        }
    }

    struct RemoveStep: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove")
        @OptionGroup var ref: Ref
        @Argument var number: Int
        func run() throws {
            let s = try store()
            let steps = try ref.row(s).steps
            guard (1...max(1, steps.count)).contains(number), number <= steps.count else { throw ValidationError("No step \(number).") }
            try s.removeStep(steps[number - 1].id)
            printDay(try s.snapshot())
        }
    }
}

struct Categories: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List and edit categories.",
        subcommands: [List.self, AddCategory.self, Rename.self, Color.self, Archive.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        @OptionGroup var common: Common
        func run() throws { try printCategories(json: common.json) }
    }

    static func printCategories(json: Bool) throws {
            let cats = try store().categories()
            if json {
                struct C: Encodable { let name: String, color: String, archived: Bool }
                try emit(cats.map { C(name: $0.name, color: $0.colorHex, archived: $0.archived) })
            } else {
                for c in cats { print("\(c.colorHex)  \(c.name)\(c.archived ? "  (archived)" : "")") }
            }
    }

    struct AddCategory: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add")
        @Argument var name: String
        @Option(help: "Hex colour, e.g. #6E9BF2.") var color = "#8E8E93"
        func run() throws { try store().addCategory(name: name, colorHex: color); try Categories.printCategories(json: false) }
    }

    struct Rename: ParsableCommand {
        @Argument var name: String
        @Argument var newName: String
        func run() throws { let s = try store(); try s.updateCategory(id(name, s), name: newName); try Categories.printCategories(json: false) }
    }

    struct Color: ParsableCommand {
        @Argument var name: String
        @Argument(help: "Hex colour, e.g. #6E9BF2.") var hex: String
        func run() throws { let s = try store(); try s.updateCategory(id(name, s), colorHex: hex); try Categories.printCategories(json: false) }
    }

    struct Archive: ParsableCommand {
        @Argument var name: String
        @Flag(help: "Bring it back.") var undo = false
        func run() throws { let s = try store(); try s.updateCategory(id(name, s), archived: !undo); try Categories.printCategories(json: false) }
    }

    static func id(_ name: String, _ s: Store) throws -> String {
        guard let c = try s.categories().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ThreeError.noSuchCategory(name)
        }
        return c.id
    }
}

struct Logbook: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Tasks you finished, by the day you finished them.")
    @Option(help: "How many days back.") var days = 30
    @OptionGroup var common: Common

    func run() throws {
        let log = try store().logbook(days: days)
        if common.json {
            struct D: Encodable { let date: String, tasks: [TaskJSON] }
            return try emit(log.map { d in
                D(date: d.day.rawValue, tasks: d.tasks.enumerated().map { i, r in
                    TaskJSON(number: i + 1, id: r.id, title: r.task.title, category: r.category.name, blockMinutes: r.task.blockMinutes,
                             focusedMinutes: Int(r.focusedSeconds / 60), status: r.task.status.rawValue, strict: r.task.strict,
                             linear: r.task.linearRef, tags: r.tags.map(\.name))
                })
            })
        }
        if log.isEmpty { return print("Nothing finished in the last \(days) days.") }
        for d in log {
            print(d.day.rawValue)
            for r in d.tasks { print("  ✓ \(r.task.title)  [\(r.category.name) · \(clockMinutes(r.focusedSeconds))]\(tagSuffix(r))") }
        }
    }
}

struct Tags: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Tags group work across days, such as a product or a feature, and total its focus time.",
        discussion: "Tag in quick add with @name: three capture \"Fix login bug @onboarding 30m\"",
        subcommands: [List.self, Add.self, Remove.self, Rename.self, Archive.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Every tag with its focus time.")
        @Flag(help: "Include archived tags.") var all = false
        @OptionGroup var common: Common

        func run() throws {
            let summaries = try store().tagSummaries(includeArchived: all)
            if common.json {
                struct W: Encodable { let title: String, focusedMinutes: Int, done: Bool, lastWorked: Date? }
                struct T: Encodable {
                    let name: String, archived: Bool, focusedMinutes: Int, lastSevenDaysMinutes: Int, daysWorked: Int
                    let lastWorked: Date?, tasks: [W]
                }
                return try emit(summaries.map {
                    T(name: $0.tag.name, archived: $0.tag.archived, focusedMinutes: Int($0.seconds / 60),
                      lastSevenDaysMinutes: Int($0.recentSeconds / 60), daysWorked: $0.daysWorked, lastWorked: $0.lastWorked,
                      tasks: $0.work.map { W(title: $0.title, focusedMinutes: Int($0.seconds / 60), done: $0.done, lastWorked: $0.lastWorked) })
                })
            }
            if summaries.isEmpty { return print("No tags yet. Add one in quick add: three capture \"Fix login @onboarding\"") }
            for t in summaries {
                let days = t.daysWorked == 1 ? "1 day" : "\(t.daysWorked) days"
                print("@\(t.tag.name)  \(clockMinutes(t.seconds)) over \(days) · \(clockMinutes(t.recentSeconds)) past week\(t.tag.archived ? "  (archived)" : "")")
                for w in t.work { print("    \(w.done ? "✓" : " ") \(w.title)  \(clockMinutes(w.seconds))") }
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Tag a task: three tags add 2 onboarding launch")
        @Argument(help: "Task number, i1 for the inbox, or an id prefix.") var task: String
        @Argument var names: [String]
        func run() throws {
            let s = try store()
            let row = try resolveTask(task, in: s.snapshot(), inbox: s.inbox())
            for name in names { try s.addTag(name, to: row.id) }
            printDay(try s.snapshot())
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Untag a task: three tags remove 2 launch")
        @Argument var task: String
        @Argument var name: String
        func run() throws {
            let s = try store()
            let row = try resolveTask(task, in: s.snapshot(), inbox: s.inbox())
            try s.removeTag(id(name, s), from: row.id)
            printDay(try s.snapshot())
        }
    }

    struct Rename: ParsableCommand {
        @Argument var name: String
        @Argument var newName: String
        func run() throws { let s = try store(); try s.updateTag(id(name, s), name: newName) }
    }

    struct Archive: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Hide a finished tag from the list. Its time is kept.")
        @Argument var name: String
        @Flag(help: "Bring it back.") var undo = false
        func run() throws { let s = try store(); try s.updateTag(id(name, s), archived: !undo) }
    }

    static func id(_ name: String, _ s: Store) throws -> String {
        let clean = name.hasPrefix("@") ? String(name.dropFirst()) : name
        guard let t = try s.tags(includeArchived: true).first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else {
            throw ValidationError("No tag named \"\(clean)\".")
        }
        return t.id
    }
}

/// "2h 05m", "45m".
func clockMinutes(_ seconds: TimeInterval) -> String {
    let m = Int(seconds / 60)
    return m >= 60 ? String(format: "%dh %02dm", m / 60, m % 60) : "\(m)m"
}

struct Settings: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show or change timer defaults (shared with the app).")
    @Option(help: "Default focus session.") var session: String?
    @Option(help: "Short break.") var shortBreak: String?
    @Option(help: "Long break.") var longBreak: String?
    @Option(help: "Focus before a long break.") var longBreakAfter: String?
    @Option(help: "Default block for new tasks.") var block: String?
    @OptionGroup var common: Common

    func run() throws {
        let s = try store()
        var p = try s.preferences()
        if let session { p.sessionMinutes = try parseMinutes(session) }
        if let shortBreak { p.shortBreakMinutes = try parseMinutes(shortBreak) }
        if let longBreak { p.longBreakMinutes = try parseMinutes(longBreak) }
        if let longBreakAfter { p.longBreakAfterMinutes = try parseMinutes(longBreakAfter) }
        if let block { p.defaultBlockMinutes = try parseMinutes(block) }
        if p != (try s.preferences()) { try s.setPreferences(p) }
        if common.json { return try emit(p) }
        print("""
        session          \(p.sessionMinutes)m
        short break      \(p.shortBreakMinutes)m
        long break       \(p.longBreakMinutes)m after \(p.longBreakAfterMinutes)m of focus
        new task block   \(p.defaultBlockMinutes)m
        """)
    }
}
