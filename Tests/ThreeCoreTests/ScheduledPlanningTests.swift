import Darwin
import Foundation
import GRDB
import Testing
@testable import ThreeCore

struct ScheduledPlanningTests {
    private func store() throws -> Store {
        try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-scheduled-\(UUID().uuidString)/db.sqlite"))
    }

    private func enabled(_ store: Store, command: String = "true") throws {
        var settings = PlanningSettings()
        settings.enabled = true
        settings.localTime = "00:00"
        settings.command = command
        try store.setPlanningSettings(settings)
    }

    private func context(_ run: PlanningRun) throws -> ScheduledPlanningContext {
        try #require(try ScheduledPlanningContext(environment: ["THREE_DB": "/scratch/db", "THREE_PLANNING_RUN": run.id, "THREE_PLANNING_DATE": run.day.rawValue]))
    }

    private func task(_ name: String = "Review") -> NewTask { NewTask(title: name, category: "Coding", blockMinutes: 30) }

    @Test func defaultOffAndStrictSettingsRoundTrip() throws {
        let store = try store()
        #expect(try store.claimPlanningRun(trigger: .scheduled) == nil)
        #expect(try store.planningSettings() == PlanningSettings())
        var settings = PlanningSettings()
        for invalid in ["9:30", "24:00", "09:60", "-1:30", "09:3", " 9:30"] {
            settings.localTime = invalid
            #expect(throws: ThreeError.self) { try store.setPlanningSettings(settings) }
        }
        try enabled(store)
        #expect(try Store(url: URL(fileURLWithPath: store.db.path)).planningSettings().enabled)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let early = ISO8601DateFormatter().date(from: "2026-11-03T09:29:59Z")!
        #expect(!PlanningSettings().isDue(at: early, calendar: calendar))
        #expect(PlanningSettings().isDue(at: early.addingTimeInterval(1), calendar: calendar))
        calendar.timeZone = TimeZone(secondsFromGMT: 19_800)!
        #expect(PlanningSettings().isDue(at: early, calendar: calendar))
    }

    @Test func catchupIsTodayOnlyAndRestartNeverRetriesAutomatically() throws {
        let store = try store()
        try enabled(store)
        let now = Date()
        let run = try #require(try store.claimPlanningRun(trigger: .scheduled, now: now))
        #expect(run.day == DayKey(now))
        try store.finishPlanningRun(run.id, result: .init(status: .failed, error: "fixture"), now: now)
        let reopened = try Store(url: URL(fileURLWithPath: store.db.path))
        #expect(try reopened.claimPlanningRun(trigger: .scheduled, now: now.addingTimeInterval(30)) == nil)
        #expect(try reopened.claimPlanningRun(trigger: .test, now: now)?.id != run.id)
        #expect(try store.db.read { try PlanningRun.fetchAll($0).count } == 2)
    }

    @Test func lastRunUsesAttemptOrderAfterClockRollback() throws {
        let store = try store()
        try enabled(store)
        let firstTime = DayKey.today.startDate.addingTimeInterval(12 * 3600)
        let first = try #require(try store.claimPlanningRun(trigger: .test, now: firstTime))
        try store.finishPlanningRun(first.id, result: .init(status: .failed, stdout: "Old result", exitCode: 7), now: firstTime)
        let secondTime = firstTime.addingTimeInterval(-60)
        let second = try #require(try store.claimPlanningRun(trigger: .test, now: secondTime))
        try store.finishPlanningRun(second.id, result: .init(status: .failed, stdout: "New result", exitCode: 9), now: secondTime)
        let latest = try #require(try store.latestPlanningRun())
        #expect(latest.id == second.id)
        #expect(latest.stdout == "New result" && latest.exitCode == 9)
    }

    @Test func migrationPreservesExistingWorkAndWakeDoesNotReplayMissedDates() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("three-schedule-migration-\(UUID().uuidString)/db.sqlite")
        let old = try Store(url: url, upTo: "v8-canonical-plan-dates")
        let task = try old.addTask(task("Keep legacy work"), source: .app)
        var timer = try old.preferences()
        timer.sessionMinutes = 25
        try old.setPreferences(timer)
        let upgraded = try Store(url: url)
        #expect(try upgraded.snapshot().tasks.map(\.id) == [task.id])
        #expect(try upgraded.preferences().sessionMinutes == 25)
        #expect(try upgraded.planningSettings().enabled == false)
        try enabled(upgraded)
        let future = Date().addingTimeInterval(5 * 86_400)
        let caughtUp = try #require(try upgraded.claimPlanningRun(trigger: .scheduled, now: future))
        #expect(caughtUp.day == DayKey(future))
        #expect(try upgraded.db.read { try PlanningRun.fetchAll($0).count } == 1)
        try upgraded.finishPlanningRun(caughtUp.id, result: .init(status: .failed), now: future)
        #expect(try upgraded.claimPlanningRun(trigger: .scheduled, now: future) == nil)
        #expect(try upgraded.claimPlanningRun(trigger: .scheduled, now: future.addingTimeInterval(86_400))?.day == DayKey(future.addingTimeInterval(86_400)))
    }

    @Test func supervisorMigrationPreservesEarlierRunResults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("three-supervisor-migration-\(UUID().uuidString)/db.sqlite")
        let id = UUID().uuidString
        let now = Date()
        do {
            let old = try Store(url: url, upTo: "v9-scheduled-planning")
            try old.db.write { db in
                try db.execute(sql: """
                    INSERT INTO planningRun(id, day, trigger, status, startedAt, deadline, command, stdout, exitCode)
                    VALUES(?, ?, 'test', 'failed', ?, ?, 'old command', 'old output', 7)
                    """, arguments: [id, DayKey(now), now.timeIntervalSince1970, now.addingTimeInterval(600).timeIntervalSince1970])
            }
        }
        let upgraded = try Store(url: url)
        let run = try #require(try upgraded.latestPlanningRun())
        #expect(run.id == id && run.stdout == "old output" && run.exitCode == 7)
        #expect(run.supervisorPID == nil && run.status == .failed)
    }

    @Test func recoveryReleasesOnlyProvenGoneGroupsAndKeepsCapturedOutput() throws {
        let store = try store()
        try enabled(store, command: "printf recovered-output")
        let run = try #require(try store.claimPlanningRun(trigger: .test))
        let directory = URL(fileURLWithPath: store.db.path).deletingLastPathComponent()
        let result = PlanningCommand().execute(run: run, shell: "/bin/zsh", directory: directory,
                                               environment: ["THREE_PLANNING_DIRECTORY": directory.path]) {
            try store.recordPlanningProcess(run.id, group: $0)
        }
        #expect(result.cleanupConfirmed)
        try store.finishPlanningRun(run.id, result: .init(status: .succeeded, stdout: result.stdout, cleanupConfirmed: false))
        #expect(try store.activePlanningRun()?.id == run.id)
        try store.recoverPlanningRun()
        #expect(try store.planningRun(run.id)?.status == .interrupted)
        #expect(try store.planningRun(run.id)?.stdout == "recovered-output")
        #expect(try store.claimPlanningRun(trigger: .scheduled) == nil)
        #expect(try store.claimPlanningRun(trigger: .test) != nil)
    }

    @Test func recoveryDoesNotStealALiveSupervisorsFinalResult() throws {
        let store = try store()
        try enabled(store, command: "printf completed")
        let run = try #require(try store.claimPlanningRun(trigger: .test))
        try store.recordPlanningSupervisor(run.id, pid: getpid())
        let directory = URL(fileURLWithPath: store.db.path).deletingLastPathComponent()
        let result = PlanningCommand().execute(run: run, directory: directory, environment: [:]) {
            try store.recordPlanningProcess(run.id, group: $0)
        }
        #expect(result.cleanupConfirmed)
        let observer = try Store(url: URL(fileURLWithPath: store.db.path))
        try observer.recoverPlanningRun()
        #expect(try store.planningRun(run.id)?.status == .running)
        try store.finishPlanningRun(run.id, result: result)
        #expect(try store.planningRun(run.id)?.stdout == "completed")
        #expect(try store.planningRun(run.id)?.error?.contains("did not leave") == true)
    }

    @Test func atomicClaimsAcrossInstancesAndManualRaces() async throws {
        let first = try store()
        try enabled(first)
        let second = try Store(url: URL(fileURLWithPath: first.db.path))
        let ids = await withTaskGroup(of: String?.self) { group in
            for index in 0..<12 {
                group.addTask {
                    try? (index.isMultiple(of: 2) ? first : second).claimPlanningRun(trigger: index.isMultiple(of: 3) ? .test : .scheduled)?.id
                }
            }
            var ids: [String] = []
            for await id in group { if let id { ids.append(id) } }
            return ids
        }
        #expect(ids.count == 1)
        #expect(throws: ThreeError.self) { try second.claimPlanningRun(trigger: .test) }
        _ = try #require(try first.activePlanningRun())
    }

    @Test func existingDraftCommittedClosedAndFullWorkArePreserved() throws {
        for status in [PlanStatus.draft, .committed, .closed] {
            let store = try store()
            try enabled(store)
            for index in 0..<5 { _ = try store.addTask(task("Keep \(index)"), source: .app) }
            try store.db.write { try $0.execute(sql: "UPDATE dayPlan SET status=?", arguments: [status]) }
            let before = try store.snapshot()
            let run = try #require(try store.claimPlanningRun(trigger: .scheduled))
            #expect(run.status == .skipped)
            #expect(throws: ThreeError.self) { try store.claimPlanningRun(trigger: .test) }
            #expect(try store.snapshot().plan == before.plan)
            #expect(try store.snapshot().tasks == before.tasks)
            #expect(try store.takePlanningNotice(day: .today) == nil)
        }
    }

    @Test func scheduledDraftIsAtomicOnceAndRoutineWithBoundaryGuards() throws {
        let store = try store()
        let now = Date()
        let run = try #require(try store.claimPlanningRun(trigger: .test, now: now))
        let context = try context(run)
        #expect(throws: ThreeError.self) { try store.createScheduledDraft([], context: context, now: now) }
        #expect(throws: ThreeError.self) { try store.createScheduledDraft((0..<6).map { task("Task \($0)") }, context: context, now: now) }
        #expect(try store.snapshot().plan == nil)
        #expect(throws: ThreeError.self) { try store.createScheduledDraft([task()], context: context, now: run.deadline) }
        #expect(throws: ThreeError.self) { try store.createScheduledDraft([task()], context: context, now: now.addingTimeInterval(-1)) }
        try store.createScheduledDraft([task()], context: context, now: now)
        let before = try store.snapshot()
        #expect(before.plan?.status == .draft)
        #expect(before.plan?.source == .routine)
        #expect(before.tasks.first?.task.createdBy == .routine)
        #expect(before.running == nil)
        #expect(throws: ThreeError.self) { try store.createScheduledDraft([task("Replace")], context: context, now: now) }
        #expect(try store.snapshot().tasks == before.tasks)
        try store.finishPlanningRun(run.id, result: .init(status: .succeeded))
        #expect(try store.planningRun(run.id)?.status == .succeeded)
        #expect(throws: ThreeError.self) { try store.validateScheduledContext(context) }
        #expect(try store.takePlanningNotice(day: .today)?.draftReady == true)
        #expect(try store.takePlanningNotice(day: .today) == nil)
    }

    @Test func timerAndHumanPlanRacesDoNotMutateWork() throws {
        let store = try store()
        try enabled(store)
        let timer = try store.startBreak(minutes: 5)
        #expect(try store.claimPlanningRun(trigger: .scheduled) == nil)
        #expect(throws: ThreeError.self) { try store.claimPlanningRun(trigger: .test) }
        try store.stop()
        let run = try #require(try store.claimPlanningRun(trigger: .scheduled))
        _ = try store.startBreak(minutes: 5)
        #expect(throws: ThreeError.self) { try store.createScheduledDraft([task()], context: context(run)) }
        #expect(try store.snapshot().plan == nil)
        try store.stop()
        let human = try store.addTask(task("Human edit"), source: .app)
        #expect(throws: ThreeError.self) { try store.createScheduledDraft([task()], context: context(run)) }
        #expect(try store.snapshot().tasks.map(\.id) == [human.id])
        #expect(try store.history(from: .today, through: .today).contains { $0.id == timer.id })
    }

    @Test func successWithoutDraftFailsAndNoticeSurvivesPermissionDenialAndRetry() throws {
        let store = try store()
        let run = try #require(try store.claimPlanningRun(trigger: .test))
        try store.finishPlanningRun(run.id, result: .init(status: .succeeded, stdout: "no draft", exitCode: 0))
        #expect(try store.planningRun(run.id)?.status == .failed)
        #expect(try store.takePlanningNotice(day: .today)?.draftReady == false)
        let retry = try #require(try store.claimPlanningRun(trigger: .test))
        try store.createScheduledDraft([task()], context: context(retry))
        try store.finishPlanningRun(retry.id, result: .init(status: .succeeded))
        #expect(try store.takePlanningNotice(day: .today) == nil)
    }

    @Test func unknownCrashStateBlocksAcrossDatesWithoutSignallingPIDs() throws {
        let store = try store()
        try enabled(store)
        let run = try #require(try store.claimPlanningRun(trigger: .test))
        try store.recoverPlanningRun()
        #expect(try store.activePlanningRun()?.id == run.id)
        #expect(try store.claimPlanningRun(trigger: .scheduled, now: Date().addingTimeInterval(172_800)) == nil)
        #expect(throws: ThreeError.self) { try store.claimPlanningRun(trigger: .test) }
        // This process group exists and belongs to the test host, so recovery must leave it alone.
        try store.recordPlanningProcess(run.id, group: getpgrp())
        try store.recoverPlanningRun()
        #expect(try store.activePlanningRun()?.id == run.id)
        #expect(kill(getpid(), 0) == 0)
    }

    @Test func invalidScheduledEnvironmentFailsClosed() throws {
        #expect(try ScheduledPlanningContext(environment: [:]) == nil)
        for environment in [["THREE_PLANNING_DATE": "today"], ["THREE_PLANNING_RUN": UUID().uuidString],
                            ["THREE_PLANNING_DATE": "2026-11-03", "THREE_PLANNING_RUN": UUID().uuidString, "THREE_DB": "relative"]] {
            #expect(throws: ThreeError.self) { try ScheduledPlanningContext(environment: environment) }
        }
    }

    private func execute(_ command: String, timeout: TimeInterval = 3,
                         clock: @escaping @Sendable () -> Date = { Date() }, cancel: Bool = false) throws -> (PlanningCommandResult, PlanningRun, Store) {
        let store = try store()
        try enabled(store, command: command)
        let run = try #require(try store.claimPlanningRun(trigger: .test, timeout: timeout))
        let directory = URL(fileURLWithPath: store.db.path).deletingLastPathComponent()
        let runner = PlanningCommand()
        if cancel { runner.cancel() }
        let env = PlanningCommand.environment(run: run, helper: directory.appendingPathComponent("three"), database: URL(fileURLWithPath: store.db.path), directory: directory,
                                              base: ["PATH": "/usr/bin:/bin", "HOME": directory.path, "ZDOTDIR": directory.path])
        let result = runner.execute(run: run, shell: "/bin/zsh", directory: directory, environment: env, timeout: timeout, clock: clock) {
            try store.recordPlanningProcess(run.id, group: $0)
        }
        try store.finishPlanningRun(run.id, result: result)
        return (result, try #require(try store.planningRun(run.id)), store)
    }

    @Test func commandFailuresOutputCapAndNoDraftAreVisible() throws {
        let (failed, run, _) = try execute("printf 'out'; printf 'err' >&2; exit 7")
        #expect(failed.exitCode == 7)
        #expect(run.status == .failed)
        #expect(run.stdout == "out" && run.stderr == "err")
        let (_, missing, _) = try execute("three_fixture_command_that_does_not_exist")
        #expect(missing.exitCode == 127 && !missing.stderr.isEmpty)
        let (_, denied, _) = try execute("/usr/bin/touch permission-fixture; /bin/chmod 600 permission-fixture; ./permission-fixture")
        #expect(denied.status == .failed && denied.exitCode == 126 && denied.stderr.contains("permission denied"))
        let (output, noDraft, _) = try execute("/usr/bin/yes x | /usr/bin/head -c 200000; /usr/bin/yes y | /usr/bin/head -c 200000 >&2")
        #expect(output.stdout.utf8.count == PlanningCommand.outputLimit)
        #expect(output.stderr.utf8.count == PlanningCommand.outputLimit)
        #expect(output.outputTruncated)
        #expect(noDraft.status == .failed && noDraft.error?.contains("did not leave") == true)
    }

    @Test func loginPathAndWorkingDirectoryAreReal() throws {
        let store = try store()
        let directory = URL(fileURLWithPath: store.db.path).deletingLastPathComponent()
        try "export PATH='\(directory.path):/usr/bin:/bin'\n".write(to: directory.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
        let executable = directory.appendingPathComponent("fixture-path-command")
        try "#!/bin/sh\nprintf 'login-path-ok\\n'; pwd\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try enabled(store, command: "fixture-path-command")
        let run = try #require(try store.claimPlanningRun(trigger: .test))
        let env = PlanningCommand.environment(run: run, helper: executable, database: URL(fileURLWithPath: store.db.path), directory: directory,
                                              base: ["PATH": "/usr/bin:/bin", "HOME": directory.path, "ZDOTDIR": directory.path])
        let result = PlanningCommand().execute(run: run, shell: "/bin/zsh", directory: directory, environment: env) { try store.recordPlanningProcess(run.id, group: $0) }
        #expect(result.status == .succeeded)
        #expect(result.stdout == "login-path-ok\n\(directory.path)\n")
    }

    @Test func timeoutCancellationClockChangeAndDescendantsAreBounded() throws {
        let (timeout, run, _) = try execute("/bin/sleep 60 & echo $!; wait", timeout: 0.2)
        #expect(timeout.status == .timedOut)
        let group = try #require(run.processGroup)
        #expect(kill(-group, 0) == -1 && errno == ESRCH)
        let (cancel, cancelled, _) = try execute("echo should-not-run", cancel: true)
        #expect(cancel.status == .cancelled && cancel.stdout.isEmpty && cancelled.processGroup == nil)
        let old = Date().addingTimeInterval(-172_800)
        let (clock, _, _) = try execute("/bin/sleep 60", clock: { old })
        #expect(clock.status == .cancelled)
        let (background, backgroundRun, _) = try execute("/bin/sleep 60 & echo done")
        #expect(background.status == .succeeded)
        #expect(kill(-backgroundRun.processGroup!, 0) == -1 && errno == ESRCH)
    }

    @Test func scheduledFixtureCommand() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["THREE_SCHEDULED_FIXTURE_DB"], let command = env["THREE_SCHEDULED_FIXTURE_COMMAND"],
              let helper = env["THREE_SCHEDULED_FIXTURE_HELPER"] else { return }
        let store = try Store(url: URL(fileURLWithPath: path))
        try enabled(store, command: command)
        let run = try #require(try store.claimPlanningRun(trigger: .test))
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        let failure = PlanningSupervisor().execute(run: run, helper: URL(fileURLWithPath: helper),
                                                  database: URL(fileURLWithPath: path), directory: directory)
        if let failure { try store.finishPlanningRun(run.id, result: failure) }
        #expect(failure == nil)
        #expect(try store.planningRun(run.id)?.status == .succeeded)
        #expect(try store.snapshot().plan?.source == .routine)
        #expect(try store.snapshot().plan?.status == .draft)
        #expect(try store.snapshot().running == nil)
    }
}
