import Foundation

/// The helper owns the command. Closing this app's control pipe cancels it without signalling a recovered PID.
public final class PlanningSupervisor: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var control: FileHandle?

    public init() {}

    public func cancel() {
        lock.withLock {
            cancelled = true
            try? control?.close()
            control = nil
        }
    }

    /// Returns a result only when no helper could run. The helper persists every launched command's result.
    public func execute(run: PlanningRun, helper: URL, database: URL, directory: URL) -> PlanningCommandResult? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = helper
        process.arguments = ["planning-run", run.id]
        var environment = ProcessInfo.processInfo.environment
        environment["THREE_DB"] = database.path
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let failure: PlanningCommandResult? = lock.withLock {
            guard !cancelled else { return .init(status: .cancelled, error: "Planning was cancelled before launch.") }
            do {
                try process.run()
                control = pipe.fileHandleForWriting
                return nil
            } catch {
                return .init(status: .failed, error: "Could not start the bundled planning helper. Rebuild or replace this app bundle.")
            }
        }
        try? pipe.fileHandleForReading.close()
        guard failure == nil else {
            try? pipe.fileHandleForWriting.close()
            return failure
        }
        process.waitUntilExit()
        cancel()
        guard process.terminationStatus == 0 else {
            return .init(status: .interrupted, error: "The planning helper exited without a confirmed result. Further planning stays blocked until process ownership is resolved.", cleanupConfirmed: false)
        }
        return nil
    }
}
