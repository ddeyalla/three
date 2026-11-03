import Foundation
import Testing
import notify
import os
@testable import ThreeCore

@Test func changeSignalsFollowTheirDatabaseIncludingSymlinkedPeers() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("three-signals-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try Store(url: root.appendingPathComponent("first/db.sqlite"))
    let second = try Store(url: root.appendingPathComponent("second/db.sqlite"))
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"),
                                               withDestinationURL: root.appendingPathComponent("first"))
    let peer = try Store(url: root.appendingPathComponent("alias/db.sqlite"))
    #expect(ChangeSignal.name(for: first.db.path) == ChangeSignal.name(for: peer.db.path))
    #expect(ChangeSignal.name(for: first.db.path) != ChangeSignal.name(for: second.db.path))
    var firstToken: Int32 = 0, secondToken: Int32 = 0
    let queue = DispatchQueue(label: "three-signal-test")
    let firstDelivered = DispatchSemaphore(value: 0), secondDelivered = DispatchSemaphore(value: 0)
    let counts = OSAllocatedUnfairLock(initialState: [0, 0])
    #expect(notify_register_dispatch(ChangeSignal.name(for: first.db.path), &firstToken, queue) { _ in
        counts.withLock { $0[0] += 1 }
        firstDelivered.signal()
    } == NOTIFY_STATUS_OK)
    #expect(notify_register_dispatch(ChangeSignal.name(for: second.db.path), &secondToken, queue) { _ in
        counts.withLock { $0[1] += 1 }
        secondDelivered.signal()
    } == NOTIFY_STATUS_OK)
    defer { notify_cancel(firstToken); notify_cancel(secondToken) }
    try second.addToInbox(NewTask(title: "Other database", category: "Coding", blockMinutes: 30), source: .cli)
    #expect(secondDelivered.wait(timeout: .now() + 2) == .success)
    queue.sync {}
    #expect(counts.withLock { $0 } == [0, 1])
    try peer.addToInbox(NewTask(title: "Same database", category: "Coding", blockMinutes: 30), source: .cli)
    #expect(firstDelivered.wait(timeout: .now() + 2) == .success)
    queue.sync {}
    #expect(counts.withLock { $0 } == [1, 1])
    #expect(try first.inbox().map(\.task.title) == ["Same database"])
}

@Test func standardDatabaseKeepsItsInstalledNotificationName() {
    #expect(ChangeSignal.name(for: Store.standardURL.path) == "com.deyalla.three.changed")
}
