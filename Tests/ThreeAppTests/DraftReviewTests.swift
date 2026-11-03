import Foundation
import Testing
import ThreeCore
@testable import ThreeApp

struct DraftReviewTests {
    private func store() throws -> Store {
        try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("three-review-\(UUID().uuidString)/db.sqlite"))
    }

    @Test func sharedDraftCanBeEditedThenCommitted() throws {
        let store: Store
        if let path = ProcessInfo.processInfo.environment["THREE_REVIEW_DB"] {
            store = try Store(url: URL(fileURLWithPath: path))
        } else {
            store = try self.store()
            try store.setPlan((1...3).map {
                NewTask(title: "Proposed \($0)", category: "Coding", blockMinutes: 30, strict: true,
                        linearRef: "https://linear.app/brunoh-ai/issue/BPRO-398", notes: "Issue context", tags: ["review"])
            }, day: .today, source: .mcp, commit: false)
            try store.addStep(to: #require(try store.snapshot().tasks.first).id, title: "Review the diff")
        }
        let draft = try store.snapshot()
        #expect(draft.draftSummary == "Draft from MCP · 3 tasks · 1h 30m")
        #expect(draft.running == nil)
        #expect(draft.tasks.count == 3)
        let first = draft.tasks[0], second = draft.tasks[1], third = draft.tasks[2]
        try store.updateTask(first.id, title: "Reviewed task", blockMinutes: 45)
        try store.moveTask(second.id, to: 0)
        try store.setTaskStatus(third.id, .dropped)
        let reviewed = try store.snapshot()
        #expect(reviewed.plan?.status == .draft)
        #expect(reviewed.tasks.filter { $0.task.status != .dropped }.map(\.id) == [second.id, first.id])
        #expect(reviewed.draftSummary == "Draft from MCP · 2 tasks · 1h 15m")
        let edited = try #require(reviewed.tasks.first { $0.id == first.id })
        #expect(edited.task.title == "Reviewed task")
        #expect(edited.task.blockMinutes == 45)
        #expect(edited.task.strict)
        #expect(edited.task.linearRef == first.task.linearRef)
        #expect(edited.task.notes == first.task.notes)
        #expect(edited.steps == first.steps)
        #expect(!edited.steps.isEmpty)
        #expect(edited.tags == first.tags)
        #expect(reviewed.running == nil)
        try store.commit(day: .today)
        let committed = try store.snapshot()
        #expect(committed.plan?.status == .committed)
        #expect(committed.plan?.source == .mcp)
        #expect(committed.plan?.committedAt != nil)
        #expect(committed.draftSummary == nil)
        #expect(committed.sessions.isEmpty)
        #expect(committed.tasks == reviewed.tasks)
        #expect(throws: ThreeError.self) { try store.setPlan([], day: .today, source: .mcp, commit: false) }
        #expect(try store.snapshot().tasks == committed.tasks)
    }

    @Test func draftSummaryUsesSavedSourceAndCountsOnlyPlannedWork() throws {
        let store = try self.store()
        #expect(try store.snapshot().draftSummary == nil)
        for (source, title) in [(Source.app, "Three"), (.cli, "CLI"), (.mcp, "MCP"), (.routine, "Routine")] {
            try store.setPlan([NewTask(title: "Plan", category: "Coding", blockMinutes: 45)], day: .today, source: source, commit: false)
            #expect(try store.snapshot().draftSummary == "Draft from \(title) · 1 task · 45m")
        }
        try store.setTaskStatus(#require(try store.snapshot().tasks.first).id, .dropped)
        #expect(try store.snapshot().draftSummary == "Draft from Routine · 0 tasks · 0m")
    }

    @Test func linearLinksOpenOnlyHTTPSIssueURLs() {
        for reference in ["https://linear.app/brunoh-ai/issue/BPRO-398/title", "BPRO-398 https://linear.app/brunoh-ai/issue/BPRO-398"] {
            #expect(LinearIssueLink(reference)?.title == "BPRO-398")
            #expect(LinearIssueLink(reference)?.url.host == "linear.app")
        }
        for reference in ["BPRO-398", "javascript:alert(1)", "file:///tmp/BPRO-398", "http://linear.app/team/issue/BPRO-398",
                          "https://linear.app.evil.example/team/issue/BPRO-398", "https://evil.example/team/issue/BPRO-398",
                          "https://linear.app/settings", "https://linear.app/team/issue/not-an-issue",
                          "https://user:pass@linear.app/team/issue/BPRO-398", "https://linear.app:8443/team/issue/BPRO-398"] {
            #expect(LinearIssueLink(reference) == nil, "Do not open \(reference)")
        }
    }
}
