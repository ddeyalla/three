import Foundation
import Testing
@testable import ThreeCore

struct TimerIdentityTests {
    @Test(arguments: [false, true], [SessionKind.focus, .break])
    func stalePauseOrResumeLeavesReplacementUntouched(resuming: Bool, kind: SessionKind) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("three-timer-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(url: directory.appendingPathComponent("db.sqlite"))
        let peer = try Store(url: directory.appendingPathComponent("db.sqlite"))
        let task = try store.addTask(NewTask(title: "Session identity", category: "Coding", blockMinutes: 60), source: .app)
        let old = try store.startFocus(taskId: task.id)
        try store.pause(expectedSessionID: old.id)
        #expect(try store.snapshot().running?.isPaused == true)
        try store.resume(expectedSessionID: old.id)
        #expect(try store.snapshot().running?.isPaused == false)
        try peer.stop()
        if kind == .focus { _ = try peer.startFocus(taskId: task.id) }
        else { _ = try peer.startBreak() }
        if resuming { try peer.pause() }
        let replacement = try #require(peer.snapshot().running)
        #expect(throws: ThreeError.self) {
            if resuming { try store.resume(expectedSessionID: old.id) }
            else { try store.pause(expectedSessionID: old.id) }
        }
        #expect(try store.snapshot().running == replacement)
    }
}
