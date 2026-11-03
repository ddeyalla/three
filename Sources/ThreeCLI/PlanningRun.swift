import ArgumentParser
import Darwin
import Foundation
import ThreeCore

struct PlanningRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "planning-run", abstract: "Supervise an already claimed local planning command.", shouldDisplay: false)
    @Argument var runID: String

    func run() async throws {
        guard UUID(uuidString: runID)?.uuidString == runID,
              let database = ProcessInfo.processInfo.environment["THREE_DB"], database.hasPrefix("/") else {
            throw ValidationError("Planning supervision needs a run UUID and absolute THREE_DB.")
        }
        var input = stat()
        guard fstat(STDIN_FILENO, &input) == 0, input.st_mode & S_IFMT == S_IFIFO else {
            throw ValidationError("Planning supervision needs the app's control pipe.")
        }
        let store = try store()
        guard let run = try store.planningRun(runID), run.status == .running, run.processGroup == nil,
              DayKey.today == run.day, Date() >= run.startedAt, Date() < run.deadline else {
            throw ValidationError("Planning claim is inactive or already supervised.")
        }
        try store.recordPlanningSupervisor(runID, pid: getpid())
        let command = PlanningCommand()
        let channel = FileHandle.standardInput
        channel.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                command.cancel()
                handle.readabilityHandler = nil
            }
        }
        defer { channel.readabilityHandler = nil }
        let helper = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let environment = PlanningCommand.environment(run: run, helper: helper,
                                                      database: URL(fileURLWithPath: database), directory: directory)
        let result = await Task.detached {
            command.execute(run: run, directory: directory, environment: environment) {
                try store.recordPlanningProcess(run.id, group: $0)
            }
        }.value
        try store.finishPlanningRun(run.id, result: result)
    }
}
