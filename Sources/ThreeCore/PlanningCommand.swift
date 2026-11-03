import Darwin
import Foundation

public struct PlanningCommandResult: Sendable {
    public var status: PlanningRunStatus
    public var stdout: String
    public var stderr: String
    public var outputTruncated: Bool
    public var exitCode: Int32?
    public var error: String?
    public var cleanupConfirmed: Bool

    public init(status: PlanningRunStatus, stdout: String = "", stderr: String = "", outputTruncated: Bool = false,
                exitCode: Int32? = nil, error: String? = nil, cleanupConfirmed: Bool = true) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.outputTruncated = outputTruncated
        self.exitCode = exitCode
        self.error = error
        self.cleanupConfirmed = cleanupConfirmed
    }
}

/// One owned child group. A zombie leader anchors its PID until descendants have been terminated.
public final class PlanningCommand: @unchecked Sendable {
    public static let outputLimit = 65_536
    private let lock = NSLock()
    private var cancelled = false

    public init() {}
    public func cancel() { lock.withLock { cancelled = true } }
    private var isCancelled: Bool { lock.withLock { cancelled } }

    public static func environment(run: PlanningRun, helper: URL, database: URL, directory: URL,
                                   base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        env["THREE_DB"] = database.path
        env["THREE_PLANNING_RUN"] = run.id
        env["THREE_PLANNING_DATE"] = run.day.rawValue
        env["THREE_HELPER"] = helper.path
        env["THREE_PLANNING_DIRECTORY"] = directory.path
        // JSON basic strings are valid TOML strings when slashes remain unescaped.
        func quote(_ text: String) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            return String(decoding: try! encoder.encode(text), as: UTF8.self)
        }
        let fields = ["THREE_DB", "THREE_PLANNING_RUN", "THREE_PLANNING_DATE"].map { "\($0)=\(quote(env[$0]!))" }.joined(separator: ",")
        env["THREE_CODEX_MCP_CONFIG"] = "mcp_servers.three={command=\(quote(helper.path)),args=[\"mcp\"],env={\(fields)}}"
        env["THREE_PLANNING_PROMPT"] = "Plan \(run.day.rawValue) with Three. Read three://plan-day-guide, get_day, get_carryover and list_categories. This is unattended scheduled planning. Create one draft with plan_day and commit=false for exactly \(run.day.rawValue). Never commit, start focus, move or remove work. Preserve prior work. Do not invent availability, meetings or priorities. If the saved context is insufficient, explain what is missing and leave the day unchanged for human planning."
        return env
    }

    /// Call off the main actor. The loop drains both pipes even after their retained prefixes fill.
    public func execute(run: PlanningRun, shell: String? = nil, directory: URL,
                        environment: [String: String], timeout: TimeInterval = 600,
                        clock: @Sendable () -> Date = { Date() },
                        didSpawn: (Int32) throws -> Void) -> PlanningCommandResult {
        guard !isCancelled else { return .init(status: .cancelled, error: "Planning was cancelled before launch.") }
        let shell = shell ?? getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) } ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else {
            return .init(status: .failed, error: "Login shell is missing or not executable: \(shell)")
        }
        var out: [Int32] = [0, 0], err: [Int32] = [0, 0]
        guard pipe(&out) == 0 else { return .init(status: .failed, error: "Could not open command output pipe.") }
        guard pipe(&err) == 0 else {
            close(out[0]); close(out[1])
            return .init(status: .failed, error: "Could not open command error pipe.")
        }
        defer { for fd in out + err { close(fd) } }
        for fd in out + err { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, err[1], STDERR_FILENO)
        posix_spawnattr_setpgroup(&attributes, 0)
        // Suspend until the durable claim knows the group. No configured command runs in this gap.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_START_SUSPENDED | POSIX_SPAWN_CLOEXEC_DEFAULT))
        let command = #"cd -- "$THREE_PLANNING_DIRECTORY" || exit 126; "# + run.command
        let arguments = [shell, "-l", "-c", command].map { strdup($0) } + [nil]
        var environment = environment
        environment["THREE_PLANNING_DIRECTORY"] = directory.path
        let variables = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in arguments + variables { free(pointer) } }
        var pid: pid_t = 0
        let spawnError = arguments.withUnsafeBufferPointer { argv in
            variables.withUnsafeBufferPointer { envp in
                posix_spawn(&pid, shell, &actions, &attributes, argv.baseAddress!, envp.baseAddress!)
            }
        }
        guard spawnError == 0 else {
            return .init(status: .failed, error: "Could not launch login shell: \(String(cString: strerror(spawnError)))")
        }
        var forced: PlanningCommandResult?
        do { try didSpawn(pid) } catch {
            forced = .init(status: .failed, error: "Could not record command ownership. The owned process was terminated.")
        }
        if forced == nil { kill(pid, SIGCONT) }
        close(out[1]); out[1] = -1
        close(err[1]); err[1] = -1
        _ = fcntl(out[0], F_SETFL, O_NONBLOCK)
        _ = fcntl(err[0], F_SETFL, O_NONBLOCK)
        let start = ContinuousClock.now
        var stdout = Data(), stderr = Data(), truncated = false
        var buffer = [UInt8](repeating: 0, count: 8192)
        func drain(_ fd: Int32, into data: inout Data) {
            // Bound each pass so a writer flooding stdout cannot starve stderr or the deadline.
            for _ in 0..<32 {
                let count = read(fd, &buffer, buffer.count)
                guard count > 0 else { return }
                let retained = min(count, Self.outputLimit - data.count)
                data.append(contentsOf: buffer.prefix(retained))
                if retained < count { truncated = true }
            }
        }
        var info = siginfo_t()
        var ownershipLost = false
        while forced == nil {
            drain(out[0], into: &stdout)
            drain(err[0], into: &stderr)
            let now = clock()
            if isCancelled { forced = .init(status: .cancelled, error: "Planning was cancelled.") }
            else if DayKey(now) != run.day || now.timeIntervalSince1970 < run.startedAt.timeIntervalSince1970 {
                forced = .init(status: .cancelled, error: "Local date or clock changed during planning. No automatic retry.")
            } else if start.duration(to: .now) >= .seconds(timeout) || now.timeIntervalSince1970 >= run.deadline.timeIntervalSince1970 {
                forced = .init(status: .timedOut, error: "Planning exceeded its wall-time limit.")
            }
            // WNOWAIT leaves the leader unreaped, so this group ID cannot be reused before cleanup.
            let waited = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
            if waited == -1 && errno != EINTR { ownershipLost = true; break }
            if waited == 0, info.si_pid == pid { break }
            if forced == nil {
                var fds = [pollfd(fd: out[0], events: Int16(POLLIN), revents: 0), pollfd(fd: err[0], events: Int16(POLLIN), revents: 0)]
                _ = poll(&fds, 2, 20)
            }
        }
        if waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == -1, errno == ECHILD { ownershipLost = true }
        if ownershipLost {
            return .init(status: .interrupted, stdout: String(decoding: stdout, as: UTF8.self), stderr: String(decoding: stderr, as: UTF8.self),
                         outputTruncated: truncated, error: "Command process ownership is unknown. No PID was signalled and further planning is blocked.", cleanupConfirmed: false)
        }
        // Include descendants that outlive a successful shell. Never do this for a recovered group.
        kill(-pid, SIGKILL)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        // A surviving group keeps the durable claim active. Recovery releases it only after ESRCH.
        let cleanupConfirmed = kill(-pid, 0) == -1 && errno == ESRCH
        drain(out[0], into: &stdout)
        drain(err[0], into: &stderr)
        let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        var result = forced ?? .init(status: code == 0 ? .succeeded : .failed,
                                     exitCode: code, error: code == 0 ? nil : "Command exited with status \(code). See stdout and stderr.")
        result.stdout = String(decoding: stdout, as: UTF8.self)
        result.stderr = String(decoding: stderr, as: UTF8.self)
        result.outputTruncated = truncated
        result.exitCode = code
        result.cleanupConfirmed = cleanupConfirmed
        return result
    }
}
