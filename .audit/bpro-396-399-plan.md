# Three delivery plan

The user approved planning, execution, testing, commits and tracker updates for BPRO-396 through BPRO-399 on 2026-11-03. All agents use codex/gpt-6.1-sol with high reasoning effort. No Claude model runs. The initial checkout is clean main at d993f48.

## Ownership and order

1. BPRO-396 owns a frozen worktree from d993f48, native desktop QA, v0.3 metadata and release evidence. It does not contain v0.4 changes.
2. BPRO-397 owns shared planning guards, the CLI MCP adapter, SDK integration, tool tests and MCP documentation. It changes no app UI.
3. BPRO-398 starts after the shared contract lands. It owns draft review, carry-over, source display and bundled planning guidance. It proves creation through MCP followed by a user commit.
4. BPRO-399 starts only after the manual planning flow is proven. It owns durable scheduled runs, bounded local process execution and planning settings/results.
5. Native desktop QA is serialized. Other work uses independent worktrees, build directories and scratch databases. Production data, existing processes and browser profiles stay untouched.

## Shared planning contract

The existing DayPlan, NewTask, TaskRow and Source shapes remain authoritative. A draft proposal must reject replacement of committed or closed work before changing rows. Explicit replanning is a separate operation and preserves existing focus history. Starting focus is an explicit commitment, as today. Commit never reopens a closed day. Store transactions own the five-task ceiling, timer uniqueness and mutation validation. CLI and MCP use those operations rather than separate business rules.

Two structural designs were compared. A separate pending-proposal table could preserve an active plan while offering a replacement, but adds a second planning lifecycle without a ticket requirement. The selected design uses the existing draft status and rejects unsafe replacement. Users can still edit committed tasks explicitly. No new proposal store is added.

## Falsifiable completion gates

- BPRO-396 records actual native app-return, status popover, physical menu-bar and ordinary blocker-path results, plus current make test, release build and signing. Untestable runtime or accessibility checks remain explicit. Version and release metadata cannot imply unproven acceptance.
- BPRO-397 passes real stdio initialize/list/call/read, malformed-input and invariant checks. Agent blocker operations only tighten. Unsupported meeting, free-time and missing manual-block behavior stays explicit.
- BPRO-398 demonstrates MCP draft creation, visible source, review/edit/reorder/drop and human commit. Carry-over is deliberate and preserves steps and tags. Calendar integration remains outside v0.4.
- BPRO-399 demonstrates the configured command producing only a draft, one catch-up after wake, no overlap or duplicate run, timeout and process cleanup, visible errors/output, and Test in Settings.
- Each unit ends with relevant checks and a focused commit. Final integration runs make test and a release build/signature check. Tracker comments distinguish implemented, automated proof, native proof and remaining gates.

## Review limitation

The user restricted models to Sol 6.1 High. Fresh independent Sol reviewers may run. Cross-family review is not performed and cannot be claimed. The user's explicit Sol-only instruction overrides the skill's default cross-family panel. Fresh Sol review and real-artifact proof remain required.
