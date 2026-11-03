import Darwin
import Foundation
import Testing
import ThreeCore
@testable import ThreeApp

private final class PlanningTestBundle: NSObject {}

@MainActor
struct ScheduledPlanningAppTests {
    private func store() throws -> Store {
        try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-planning-app-\(UUID().uuidString)/db.sqlite"))
    }

    private func helper() throws -> URL {
        let url = Bundle(for: PlanningTestBundle.self).bundleURL.deletingLastPathComponent().appendingPathComponent("three")
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
        return url
    }

    @Test func testShowsOutputAndFailureAndDoesNotRepeatNudgeOnReload() async throws {
        let store = try store()
        var settings = PlanningSettings()
        settings.command = "printf 'fixture stdout'; printf 'fixture stderr' >&2; exit 6"
        try store.setPlanningSettings(settings)
        var notices: [PlanningNotice] = []
        let planning = try PlanningController(store: store, helper: try helper()) { notices.append($0) }
        planning.check(now: Date(), test: true)
        #expect(planning.checking)
        await planning.task?.value
        #expect(!planning.checking)
        #expect(planning.lastRun?.status == .failed)
        #expect(planning.lastRun?.stdout == "fixture stdout")
        #expect(planning.lastRun?.stderr == "fixture stderr")
        #expect(planning.lastRun?.exitCode == 6)
        #expect(notices.count == 1 && !notices[0].draftReady)
        let restarted = try PlanningController(store: store, helper: try helper()) { notices.append($0) }
        restarted.check(now: Date())
        await restarted.task?.value
        #expect(notices.count == 1)
        #expect(restarted.lastRun?.id == planning.lastRun?.id)
    }

    @Test func startupCancelPreventsCommandAndShutdownWaitsForOwnedCleanup() async throws {
        let store = try store()
        var settings = PlanningSettings()
        settings.command = "printf should-not-run"
        try store.setPlanningSettings(settings)
        let planning = try PlanningController(store: store, helper: try helper(), deliverNotice: { _ in })
        planning.check(now: Date(), test: true)
        planning.cancel()
        await planning.task?.value
        #expect(planning.lastRun?.status == .cancelled)
        #expect(planning.lastRun?.stdout == "")
        #expect(planning.lastRun?.processGroup == nil)
        await planning.shutdown()
        planning.check(now: Date(), test: true)
        #expect(planning.task == nil)
    }

    @Test func settingsUseSharedPreferenceStoreAndPreserveTimerPreferences() throws {
        let store = try store()
        var timer = try store.preferences()
        timer.sessionMinutes = 25
        try store.setPreferences(timer)
        let planning = try PlanningController(store: store, helper: try helper(), deliverNotice: { _ in })
        var settings = planning.settings
        settings.localTime = "14:45"
        settings.command = "echo local-only"
        planning.save(settings)
        #expect(planning.error == nil)
        let reopened = try Store(url: URL(fileURLWithPath: store.db.path))
        #expect(try reopened.planningSettings() == settings)
        #expect(try reopened.preferences().sessionMinutes == 25)
        settings.localTime = "25:00"
        planning.save(settings)
        #expect(planning.error != nil)
        #expect(try reopened.planningSettings().localTime == "14:45")
    }

    @Test func shutdownCancelsAnAlreadyRunningOwnedProcessGroup() async throws {
        let store = try store()
        let fifo = URL(fileURLWithPath: store.db.path).deletingLastPathComponent().appendingPathComponent("ready.fifo")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let descriptor = open(fifo.path, O_RDONLY | O_NONBLOCK)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        var settings = PlanningSettings()
        settings.command = "printf ready > '\(fifo.path)'; /bin/sleep 60"
        try store.setPlanningSettings(settings)
        let planning = try PlanningController(store: store, helper: try helper(), deliverNotice: { _ in })
        planning.check(now: Date(), test: true)
        let ready = await Task.detached {
            var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&event, 1, 3000) > 0 else { return false }
            var bytes = [UInt8](repeating: 0, count: 5)
            return read(descriptor, &bytes, 5) == 5 && String(decoding: bytes, as: UTF8.self) == "ready"
        }.value
        // Always clean up, including when readiness fails.
        await planning.shutdown()
        #expect(ready)
        #expect(planning.lastRun?.status == .cancelled)
        let group = try #require(planning.lastRun?.processGroup)
        #expect(kill(-group, 0) == -1 && errno == ESRCH)
        #expect(try store.activePlanningRun() == nil)
    }
}
