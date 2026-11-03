import ArgumentParser
import Foundation
import MCP
import ThreeCore

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "mcp", abstract: "Serve Three tools and resources over stdio.")

    func run() async throws {
        do {
            let context = try ScheduledPlanningContext(environment: ProcessInfo.processInfo.environment)
            let adapter = ThreeMCP(store: try store(), scheduled: context)
            if let context { try adapter.store.validateScheduledContext(context) }
            let server = Server(name: "three", version: "1.0.0",
                                instructions: "Read three://plan-day-guide. Propose drafts with commit=false for human review. Calendar, free time and manual blocking are unsupported.",
                                capabilities: .init(resources: .init(), tools: .init()))
            await server.withMethodHandler(ListTools.self) { _ in .init(tools: adapter.definitions) }
            await server.withMethodHandler(ValidatedMethod<CallTool>.self) { parameters in
                let params = try parameters.requireValue()
                return adapter.call(name: params.name, arguments: params.arguments ?? [:])
            }
            await server.withMethodHandler(ListResources.self) { _ in
                .init(resources: [
                    Resource(name: "Today", uri: "three://today", mimeType: "application/json"),
                    Resource(name: "Plan the day", uri: "three://plan-day-guide", mimeType: "text/markdown"),
                ])
            }
            await server.withMethodHandler(ValidatedMethod<ReadResource>.self) { parameters in
                let params = try parameters.requireValue()
                switch params.uri {
                case "three://today":
                    do {
                        return .init(contents: [.text(try mcpJSON(MCPDay(try adapter.store.snapshot())), uri: params.uri, mimeType: "application/json")])
                    } catch { throw MCPError.internalError("Could not read today.") }
                case "three://plan-day-guide":
                    guard let url = planDayGuideURL(),
                          let text = try? String(contentsOf: url, encoding: .utf8) else {
                        throw MCPError.internalError("Planning guide is unavailable.")
                    }
                    let scheduledGuide = context.map { "\n\nScheduled mode targets \($0.day.rawValue). Only reads and one plan_day with commit=false are permitted. Do not carry, edit, drop, commit, or start focus. If context is insufficient, explain what is missing and leave the day unchanged.\n" } ?? ""
                    return .init(contents: [.text(text + scheduledGuide, uri: params.uri, mimeType: "text/markdown")])
                default: throw MCPError.invalidParams("Unknown resource URI.")
                }
            }
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
            await server.stop()
        } catch {
            throw ValidationError("MCP server could not start. Check the database path and permissions.")
        }
    }
}

private func planDayGuideURL() -> URL? {
    let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    let directories = [Bundle.main.resourceURL, Bundle.main.bundleURL, executableDirectory,
                       executableDirectory.deletingLastPathComponent().appendingPathComponent("Resources")].compactMap { $0 }
    for directory in directories {
        if let bundle = Bundle(url: directory.appendingPathComponent("Three_ThreeCLI.bundle")),
           let url = bundle.url(forResource: "PlanDay", withExtension: "md") { return url }
    }
    return nil
}

private enum ValidatedMethod<Base: MCP.Method>: MCP.Method {
    static var name: String { Base.name }
    typealias Result = Base.Result
    struct Parameters: Codable, Hashable, Sendable {
        let value: Base.Parameters?
        init(from decoder: Decoder) throws { value = try? Base.Parameters(from: decoder) }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
        func requireValue() throws -> Base.Parameters {
            guard let value else { throw MCPError.invalidParams("Invalid parameters for \(Base.name).") }
            return value
        }
    }
}

private enum MCPTool: String, CaseIterable {
    case getToday = "get_today", getDay = "get_day", planDay = "plan_day", commitDay = "commit_day"
    case addTask = "add_task", updateTask = "update_task", removeTask = "remove_task", moveTask = "move_task"
    case setTaskStatus = "set_task_status", carryTask = "carry_task", scheduleTask = "schedule_task"
    case listCategories = "list_categories", upsertCategory = "upsert_category"
    case startFocus = "start_focus", pause, resume, stop, extend, startBreak = "start_break", finishFocus = "finish_focus"
    case getStatus = "get_status", getCarryover = "get_carryover", getHistory = "get_history"
    case getHistoryReport = "get_history_report"
    case getDayClose = "get_day_close", closeDay = "close_day", dismissCarry = "dismiss_carry"
    case getBlockStatus = "get_block_status", addBlockRule = "add_block_rule", setTaskStrict = "set_task_strict"

    var definition: Tool {
        let text: String
        let fields: [String: Value]
        let required: [String]
        let readOnly: Bool
        switch self {
        case .getToday:
            (text, fields, required, readOnly) = ("Read today's plan, task details, sources and sessions. Calendar and free time are unsupported.", [:], [], true)
        case .getDay:
            (text, fields, required, readOnly) = ("Read a local day's plan and sessions.", ["date": dateField], ["date"], true)
        case .planDay:
            (text, fields, required, readOnly) = ("Replace untouched tasks in a draft. Defaults to commit=false for human review. Committed days require explicit commit=true replanning. Closed days are immutable. Worked tasks remain and count toward five. Warns above three.", ["date": dateField, "tasks": .object(["type": "array", "items": taskSchema, "maxItems": 5]), "commit": .object(["type": "boolean", "default": false])], ["date", "tasks"], false)
        case .commitDay:
            (text, fields, required, readOnly) = ("Commit a draft only on the person's request. No calendar events are written before v0.5.", ["date": dateField], ["date"], false)
        case .addTask:
            (text, fields, required, readOnly) = ("Add a task to a day. Uses source=mcp and enforces five tasks.", taskFields.merging(["date": dateField]) { $1 }, ["date", "title", "category", "block_minutes"], false)
        case .updateTask:
            (text, fields, required, readOnly) = ("Edit supported fields on a live task. Use separate tools for status, ordering, scheduling and strictness.", ["id": idField, "title": stringField, "category": stringField, "block_minutes": blockField, "notes": stringField], ["id"], false)
        case .removeTask:
            (text, fields, required, readOnly) = ("Remove an untouched task or drop a worked task, preserving focus history. Ends its running session.", ["id": idField], ["id"], false)
        case .moveTask:
            (text, fields, required, readOnly) = ("Move a task within its plan using a zero-based index. Indices beyond the list append.", ["id": idField, "index": .object(["type": "integer", "minimum": 0])], ["id", "index"], false)
        case .setTaskStatus:
            (text, fields, required, readOnly) = ("Set todo, done, partial, dropped or carried, with optional task notes. Active requires start_focus. Carried is terminal; carry_task also copies to tomorrow. Closed days and deleted tasks cannot reopen.", ["id": idField, "status": .object(["type": "string", "enum": ["todo", "done", "partial", "dropped", "carried"]]), "note": stringField], ["id", "status"], false)
        case .carryTask:
            (text, fields, required, readOnly) = ("Accept open work onto a later date, defaulting to its plan's next day. Copies metadata, steps and tags with lineage and preserves source sessions. Closed sources are allowed. Repeats return the same copy. Refuses pending reflections, running tasks and full or closed destinations.", ["id": idField, "date": dateField], ["id"], false)
        case .dismissCarry:
            (text, fields, required, readOnly) = ("Dismiss unfinished planned work, including a closed source, without creating another task. Durable and safe to repeat. Conflicts with prior acceptance.", ["id": idField], ["id"], false)
        case .getDayClose:
            (text, fields, required, readOnly) = ("Read the frozen day-close summary, or null when none was saved. Includes original outcomes, commitment evidence, focus and known break decisions. Does not close a day.", ["date": dateField], ["date"], true)
        case .closeDay:
            (text, fields, required, readOnly) = ("Check and close an eligible committed day. Defers active focus, reflection and recovery. Repeats return the saved summary. Never creates tomorrow's tasks or changes a timer.", ["date": dateField], ["date"], false)
        case .scheduleTask:
            (text, fields, required, readOnly) = ("Move a task to a day, or to the inbox with date=inbox. Refuses running, deleted and carried tasks and closed days.", ["id": idField, "date": .object(["type": "string", "description": "today, tomorrow, yesterday, yyyy-MM-dd, or inbox"])], ["id", "date"], false)
        case .listCategories:
            (text, fields, required, readOnly) = ("Read categories, including archived ones.", [:], [], true)
        case .upsertCategory:
            (text, fields, required, readOnly) = ("Create with name and color_hex. Update an existing category by exact id, including archive state. Omitting id always creates.", ["id": idField, "name": stringField, "color_hex": .object(["type": "string", "pattern": "^#[0-9A-Fa-f]{6}$"]), "archived": boolField], [], false)
        case .startFocus:
            (text, fields, required, readOnly) = ("Start focus on an exact task id, or the next open task today. Commits a draft and ends a running break. Refuses a second focus timer. Launches Three outside scratch databases.", ["task_id": idField, "minutes": integerField(1, 480)], [], false)
        case .pause, .resume, .stop:
            (text, fields, required, readOnly) = ("\(rawValue.capitalized) the running timer. Stop leaves a focused task partial. Fails when nothing runs.", [:], [], false)
        case .extend:
            (text, fields, required, readOnly) = ("Add minutes to the running timer. Overruns extend from now.", ["minutes": integerField(1, 480)], ["minutes"], false)
        case .startBreak:
            (text, fields, required, readOnly) = ("Start a break using Store defaults or explicit minutes. Refuses a running focus session.", ["minutes": integerField(1, 120)], [], false)
        case .finishFocus:
            (text, fields, required, readOnly) = ("Finish the current focus session with reflection. Does not start another session.", ["outcome": .object(["type": "string", "enum": ["done", "progress", "stuck"]]), "rating": integerField(1, 3), "note": stringField, "mark_task_done": boolField], ["outcome", "rating", "mark_task_done"], false)
        case .getStatus:
            (text, fields, required, readOnly) = ("Read the running timer and remaining seconds, or null.", [:], [], true)
        case .getCarryover:
            (text, fields, required, readOnly) = ("Read unfinished planned tasks before date. Excludes undated inbox tasks. Does not move anything.", ["date": dateField], ["date"], true)
        case .getHistory:
            (text, fields, required, readOnly) = ("Read sessions and reflections by inclusive local start date. At most 366 days. No calendar or trend model is implied.", ["from": dateField, "to": dateField], ["from", "to"], true)
        case .getHistoryReport:
            (text, fields, required, readOnly) = ("Read shared month/day/task/session history with focus and derived planned totals. Includes empty dates and deleted references. Inclusive local start dates, at most 366 days. Does not modify records.", ["from": dateField, "to": dateField], ["from", "to"], true)
        case .getBlockStatus:
            (text, fields, required, readOnly) = ("Read current blocker policy, rules, focus hours, today's hits and browser coverage.", [:], [], true)
        case .addBlockRule:
            (text, fields, required, readOnly) = ("Tighten blocking by adding or re-enabling a domain or app rule. Repeats return the covering rule. Never removes, disables or grants exceptions.", ["kind": .object(["type": "string", "enum": ["domain", "app"]]), "value": stringField], ["kind", "value"], false)
        case .setTaskStrict:
            (text, fields, required, readOnly) = ("Mark a live task strict. One-way and safe to repeat. No false or disable parameter exists.", ["id": idField], ["id"], false)
        }
        return Tool(name: rawValue, description: text, inputSchema: objectSchema(fields, required: required),
                    annotations: .init(readOnlyHint: readOnly, openWorldHint: false))
    }
}

private let stringField: Value = ["type": "string"]
private let boolField: Value = ["type": "boolean"]
private let idField: Value = ["type": "string", "minLength": 1, "description": "Exact Store UUID, never a list position or prefix."]
private let dateField: Value = ["type": "string", "description": "today, tomorrow, yesterday, or a real yyyy-MM-dd local date."]
private let blockField = integerField(5, 480)
private let timestampPattern = #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]+)?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$"#
private let taskFields: [String: Value] = [
    "title": ["type": "string", "minLength": 1], "category": stringField, "block_minutes": blockField,
    "scheduled_start": ["type": "string", "format": "date-time", "pattern": .string(timestampPattern)], "strict": boolField,
    "linear": stringField, "notes": stringField, "tags": ["type": "array", "items": stringField],
]
private let taskSchema = objectSchema(taskFields, required: ["title", "category", "block_minutes"])

private func integerField(_ low: Int, _ high: Int) -> Value { ["type": "integer", "minimum": .int(low), "maximum": .int(high)] }
private func objectSchema(_ fields: [String: Value], required: [String]) -> Value {
    ["type": "object", "properties": .object(fields), "required": .array(required.map(Value.string)), "additionalProperties": false]
}

private struct ThreeMCP: Sendable {
    let store: Store
    let scheduled: ScheduledPlanningContext?

    var tools: [MCPTool] {
        scheduled == nil ? MCPTool.allCases : [.getToday, .getDay, .planDay, .listCategories, .getStatus, .getCarryover, .getHistory, .getBlockStatus]
    }

    var definitions: [Tool] {
        tools.map { tool in
            guard tool == .planDay, let scheduled else { return tool.definition }
            return Tool(name: tool.rawValue, description: "Create one draft for \(scheduled.day). Preserves all existing plans. Never commits or starts a timer.",
                        inputSchema: objectSchema(["date": ["type": "string", "enum": [.string(scheduled.day.rawValue)]],
                                                   "tasks": ["type": "array", "items": taskSchema, "minItems": 1, "maxItems": 5],
                                                   "commit": ["type": "boolean", "enum": [false]]], required: ["date", "tasks"]),
                        annotations: .init(readOnlyHint: false, openWorldHint: false))
        }
    }

    func call(name: String, arguments: [String: Value]) -> CallTool.Result {
        guard let tool = MCPTool(rawValue: name) else { return failure("unknown_tool", "Unknown or unsupported tool.") }
        do {
            guard tools.contains(tool) else { return failure("scheduled_only", "Scheduled mode permits reads and draft creation only.") }
            if let scheduled { try store.validateScheduledContext(scheduled) }
            try validate(.object(arguments), schema: tool.definition.inputSchema)
            return try perform(tool, MCPArguments(values: arguments))
        } catch let error as ThreeError {
            let code: String = switch error {
            case .tooManyTasks: "too_many_tasks"
            case .noSuchTask: "no_such_task"
            case .noSuchCategory: "no_such_category"
            case .noRunningSession: "no_running_session"
            case .alreadyRunning: "already_running"
            case .nothingToStart: "nothing_to_start"
            case .invalid: "invalid_input"
            }
            return failure(code, String(error.localizedDescription.prefix(512)))
        } catch let error as BlockError {
            return failure("block_rule_error", String(error.localizedDescription.prefix(512)))
        } catch {
            FileHandle.standardError.write(Data("three mcp: operation failed.\n".utf8))
            return failure("internal_error", "Operation failed. Check the database and try again.")
        }
    }

    private func perform(_ tool: MCPTool, _ a: MCPArguments) throws -> CallTool.Result {
        switch tool {
        case .getToday: return try result(MCPDay(store.snapshot()))
        case .getDay: return try result(MCPDay(store.snapshot(for: a.day("date"))))
        case .planDay:
            let day = try a.day("date")
            let tasks = try a.array("tasks").map { value in try MCPArguments(values: value.objectValue!).newTask() }
            if let scheduled {
                guard try a.requiredString("date") == scheduled.day.rawValue, day == scheduled.day, a.bool("commit") != true else {
                    return failure("scheduled_only", "Scheduled mode only creates an uncommitted draft for its target date.")
                }
                try store.createScheduledDraft(tasks, context: scheduled)
            } else {
                try store.setPlan(tasks, day: day, source: .mcp, commit: a.bool("commit") ?? false)
            }
            let snapshot = try store.snapshot(for: day)
            return try result(MCPPlanResult(day: MCPDay(snapshot), warnings: snapshot.activeTaskCount > Rules.idealTasks ? ["More than three tasks are planned. Leave room for buffer."] : []))
        case .commitDay: try store.commit(day: a.day("date"))
        case .addTask: return try result(store.addTask(a.newTask(), day: a.day("date"), source: .mcp))
        case .updateTask:
            try store.updateTask(a.requiredString("id"), title: a.string("title"), category: a.string("category"), blockMinutes: a.int("block_minutes"), notes: a.string("notes"))
        case .removeTask: try store.removeTask(a.requiredString("id"))
        case .moveTask: try store.moveTask(a.requiredString("id"), to: a.requiredInt("index"))
        case .setTaskStatus:
            let status = TaskStatus(rawValue: try a.requiredString("status"))!
            try store.updateTask(a.requiredString("id"), status: status, notes: a.string("note"))
        case .carryTask:
            if a.string("date") != nil { return try result(store.carryTask(a.requiredString("id"), to: a.day("date"))) }
            return try result(store.pushToTomorrow(a.requiredString("id")))
        case .dismissCarry: return try result(store.dismissCarry(a.requiredString("id")))
        case .getDayClose: return try result(store.dayCloseSummary(for: a.day("date")))
        case .closeDay: return try result(store.closeDay(a.day("date")))
        case .scheduleTask:
            let date = try a.requiredString("date")
            try store.schedule(a.requiredString("id"), on: date == "inbox" ? nil : a.day("date"))
        case .listCategories: return try result(store.categories())
        case .upsertCategory:
            if let id = a.string("id") {
                try store.updateCategory(id, name: a.string("name"), colorHex: a.string("color_hex"), archived: a.bool("archived"))
            } else {
                guard a.bool("archived") != true else { throw ThreeError.invalid("Create an active category before archiving it.") }
                return try result(store.addCategory(name: a.requiredString("name"), colorHex: a.requiredString("color_hex")))
            }
        case .startFocus:
            let session = try store.startFocus(taskId: a.string("task_id"), minutes: a.int("minutes"))
            ensureAppRunning()
            return try result(session)
        case .pause: try store.pause()
        case .resume: try store.resume()
        case .stop: try store.stop()
        case .extend: try store.extend(minutes: a.requiredInt("minutes"))
        case .startBreak:
            let session = try store.startBreak(minutes: a.int("minutes"))
            ensureAppRunning()
            return try result(session)
        case .finishFocus:
            try store.finishFocus(outcome: Outcome(rawValue: a.requiredString("outcome"))!, rating: FocusRating(rawValue: a.requiredInt("rating"))!, note: a.string("note"), markTaskDone: a.bool("mark_task_done")!)
        case .getStatus: return try result(dayJSON(store.snapshot()).running)
        case .getCarryover: return try result(store.carryover(before: a.day("date")).map(MCPTask.init))
        case .getHistory: return try result(store.history(from: a.day("from"), through: a.day("to")))
        case .getHistoryReport: return try result(store.historyReport(from: a.day("from"), through: a.day("to")))
        case .getBlockStatus: return try result(BlockStatusJSON(store.blockStatus(), now: Date()))
        case .addBlockRule:
            let kind = try a.requiredString("kind"), value = try a.requiredString("value")
            let target: BlockTarget = kind == "domain" ? .domain(try BlockDomain(parsing: value)) : .app(try AppBundleID(parsing: value))
            _ = try store.addBlockRule(target)
            return try result(BlockStatusJSON(store.blockStatus(), now: Date()))
        case .setTaskStrict: try store.setTaskStrict(a.requiredString("id"))
        }
        return try result(["ok": true])
    }
}

private struct MCPArguments {
    let values: [String: Value]
    func string(_ name: String) -> String? { values[name]?.stringValue }
    func int(_ name: String) -> Int? { values[name]?.intValue }
    func bool(_ name: String) -> Bool? { values[name]?.boolValue }
    func requiredString(_ name: String) throws -> String {
        guard let value = string(name) else { throw ThreeError.invalid("Missing string field \(name).") }
        return value
    }
    func requiredInt(_ name: String) throws -> Int {
        guard let value = int(name) else { throw ThreeError.invalid("Missing integer field \(name).") }
        return value
    }
    func array(_ name: String) throws -> [Value] {
        guard let value = values[name]?.arrayValue else { throw ThreeError.invalid("Missing array field \(name).") }
        return value
    }
    func day(_ name: String) throws -> DayKey {
        try parsePlanDay(requiredString(name))
    }

    func newTask() throws -> NewTask {
        var start: Date?
        if let raw = string("scheduled_start") {
            guard DayKey(String(raw.prefix(10))) != nil else {
                throw ThreeError.invalid("scheduled_start needs a valid calendar date.")
            }
            start = ISO8601DateFormatter().date(from: raw)
            if start == nil {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions.insert(.withFractionalSeconds)
                start = formatter.date(from: raw)
            }
            guard start != nil else { throw ThreeError.invalid("scheduled_start needs an ISO 8601 timestamp with timezone.") }
        }
        return try NewTask(title: requiredString("title"), category: requiredString("category"), blockMinutes: requiredInt("block_minutes"), scheduledStart: start, strict: bool("strict") ?? false, linearRef: string("linear"), notes: string("notes") ?? "", tags: values["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    }
}

private func validate(_ value: Value, schema: Value, field: String = "arguments") throws {
    let rules = schema.objectValue!
    func reject() throws -> Never { throw ThreeError.invalid("Invalid field \(field). See tools/list for supported fields and types.") }
    if let allowed = rules["enum"]?.arrayValue, !allowed.contains(value) { try reject() }
    switch rules["type"]?.stringValue {
    case "object":
        guard let object = value.objectValue else { try reject() }
        let properties = rules["properties"]!.objectValue!
        guard Set(object.keys).isSubset(of: Set(properties.keys)),
              (rules["required"]?.arrayValue ?? []).allSatisfy({ object[$0.stringValue!] != nil }) else { try reject() }
        for (key, item) in object { try validate(item, schema: properties[key]!, field: key) }
    case "string":
        guard let string = value.stringValue else { try reject() }
        if let minimum = rules["minLength"]?.intValue, string.count < minimum { try reject() }
        if let pattern = rules["pattern"]?.stringValue,
           string.range(of: pattern, options: .regularExpression) != string.startIndex..<string.endIndex { try reject() }
    case "integer":
        guard let integer = value.intValue else { try reject() }
        if let minimum = rules["minimum"]?.intValue, integer < minimum { try reject() }
        if let maximum = rules["maximum"]?.intValue, integer > maximum { try reject() }
    case "boolean": guard value.boolValue != nil else { try reject() }
    case "array":
        guard let array = value.arrayValue else { try reject() }
        if let maximum = rules["maxItems"]?.intValue, array.count > maximum { try reject() }
        for item in array { try validate(item, schema: rules["items"]!, field: field) }
    default: preconditionFailure("Unsupported tool schema")
    }
}

private struct MCPTask: Encodable {
    let task: FocusTask
    let category: ThreeCore.Category
    let focusedSeconds: TimeInterval
    let steps: [Step]
    let tags: [Tag]
    init(_ row: TaskRow) { task = row.task; category = row.category; focusedSeconds = row.focusedSeconds; steps = row.steps; tags = row.tags }
}

private struct MCPDay: Encodable {
    let date: DayKey
    let plan: DayPlan?
    let tasks: [MCPTask]
    let sessions: [Session]
    let running: Session?
    let runningTask: MCPTask?
    let takenAt: Date
    let plannedMinutes: Int
    init(_ snapshot: DaySnapshot) {
        date = snapshot.day; plan = snapshot.plan; tasks = snapshot.tasks.map(MCPTask.init)
        sessions = snapshot.sessions; running = snapshot.running; runningTask = snapshot.runningTask.map(MCPTask.init)
        takenAt = snapshot.takenAt; plannedMinutes = snapshot.plannedMinutes
    }
}
private struct MCPPlanResult: Encodable { let day: MCPDay; let warnings: [String] }
private func mcpJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
private func result<T: Encodable>(_ value: T) throws -> CallTool.Result { .init(content: [.text(text: try mcpJSON(value), annotations: nil, _meta: nil)], isError: false) }
private func failure(_ code: String, _ message: String) -> CallTool.Result {
    struct Failure: Encodable { let code: String; let message: String }
    let text = try! mcpJSON(Failure(code: code, message: message))
    return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
}
