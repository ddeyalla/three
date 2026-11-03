# Deliver the non-calendar Three backlog

Prepared on 2026-11-03 against `a0925d202fd8677880acd390cc1b8707953c786a` on `dv/ai-planning-v04`.
This is an execution plan for a new chat. No feature work or delegates start when this document is created.
The first unattended work window is 15:30 to 18:00 Asia/Kolkata. Treat that as a reporting checkpoint, not a promise that seven tickets fit in 150 minutes.

## Own the seven-ticket queue

Read the live issue descriptions and comments before work. The following defaults settle the choices that would otherwise interrupt the owner.

| Ticket | Deliverable | Completion boundary |
| --- | --- | --- |
| [BPRO-402](https://linear.app/brunoh-ai/issue/BPRO-402) | Month, day, and session history | Native drill-down, accurate shared reads, and CLI/MCP parity |
| [BPRO-404](https://linear.app/brunoh-ai/issue/BPRO-404) | Quiet day-close and unfinished-work offers | Idempotent close, durable summary, explicit accept/dismiss, and preserved history |
| [BPRO-406](https://linear.app/brunoh-ai/issue/BPRO-406) | Existing-task Make strict action | One-way Store operation exposed in the app and verified during focus |
| [BPRO-403](https://linear.app/brunoh-ai/issue/BPRO-403) | Five trends and a streak | Shared bounded statistics, native charts, and documented denominators |
| [BPRO-405](https://linear.app/brunoh-ai/issue/BPRO-405) | Sleep recovery, hotkey, onboarding, and login/notification reconciliation | Keep/trim accounting, native controls, visible permission failures, and tested lifecycle behavior |
| [BPRO-408](https://linear.app/brunoh-ai/issue/BPRO-408) | Optional notch focus controls | One shared timer, supported-screen behavior, and a working menu-bar fallback |
| [BPRO-407](https://linear.app/brunoh-ai/issue/BPRO-407) | Sync and companion implementation design | Schema audit, concrete conflict/deletion rules, permission requirements, and bounded follow-up work |

Keep BPRO-400 and BPRO-401 deferred. Do not add EventKit or Google Calendar integration during this run.
Leave BPRO-396 In Progress. The owner has no macOS 26 machine. Do not ask again or claim that macOS 27 proves macOS 26 acceptance.
Preserve the completed work for BPRO-397, BPRO-398, and BPRO-399.

BPRO-406 permits selecting a bounded follow-up. Record the chosen Make strict scope in the ticket and explicitly retain broader browser coverage, path rules, category allow rules, and network filtering as deferred work. Do not imply that those capabilities were built.
BPRO-407 is a discovery ticket. Do not implement CloudKit sync, iPhone/Watch apps, two-way Linear sync, or Screen Time without a separate implementation scope. Completing its concrete design is the requested outcome for this ticket.

## Establish the baseline before editing

- [ ] Read the repository instructions and inspect cwd, branch, HEAD, remote, and active diff. Record them in the run report.
- [ ] Fetch the remote and confirm that the chosen base includes `a0925d2`. Do not start from an older `origin/main` that lacks the planning and menu fixes.
- [ ] Use a new coordinator branch such as `dv/non-calendar-backlog` from that base. Preserve unrelated edits and existing worktrees.
- [ ] Read `PRODUCT.md`, `README.md`, `docs/MCP.md`, `docs/planning.md`, `docs/scheduled-planning.md`, and the relevant verification reports. Treat source and executed proof as authoritative when older prose disagrees.
- [ ] Run `make test` once at the baseline. The previous full result was 134 Core, 29 App, and 22 extension tests. That is context, not a fresh result.
- [ ] Record a disposable database fixture covering two months, empty days, a carried task, a paused session, a break, and a reflection. Include a separate upgrade fixture.
- [ ] Record the installed app's path, executable hash, database location, PID, and process start time. Preserve these through the run.
- [ ] Keep the existing Three Manual Test app and its database intact. Prepare a new QA bundle with a unique bundle ID, executable name, `THREE_DB`, and `THREE_CHROME_DATA`.

Do not use `make run`, `make install`, broad `pkill`, or another command that replaces or restarts production. Those Makefile targets operate on the installed app or every matching process.

## Freeze shared contracts, then split ownership

Use the pstack `figure-it-out` workflow for this bounded run. Its useful rules here are small verified units, a decision trail, and direct artifact checks. This run is not an autonomous merge program.
The pasted execution prompt explicitly authorizes parallel children for this run. Planning in the originating chat remains in-thread.

Limit concurrent implementation to three workers. Add one independent reviewer when a finished unit is ready. All delegates use Codex Sol 6.1 High. No Claude models, nested delegation, or unnecessary model panels.
Use the host's worktree isolation for writing delegates. Each brief names the exact base, ownership, acceptance checks, and excluded files. Tell every worker that others are editing and that it must not revert their work.

The coordinator owns shared integration files unless it grants one worker exclusive ownership for a specific unit.

| Owner | Files and responsibility |
| --- | --- |
| Coordinator | `Sources/ThreeCore/Store.swift`, `Models.swift`, shared `Operations.swift` edits, `Sources/ThreeCLI/Three.swift`, `MCP.swift`, `Package.swift`, app routing, `AppModel.swift`, `ThreeApp.swift`, and Settings composition |
| History worker | History queries and types in a focused ThreeCore extension, history views, and focused tests. Extend existing code when that is clearer than a new module. |
| Day-close worker | Close/carry behavior, summary presentation, and focused tests. Propose shared model and migration changes to the coordinator. |
| UI worker | Make strict controls first, then notch presentation. Shared task menus and app wiring are integrated by their current owner. |
| Reviewer | Read-only review of the exact candidate commit and real-artifact verification. No product edits or desktop control without the coordinator's handoff. |

Keep each implementation in its responsible module. The implementation owner can choose a simpler existing owner and record that choice.

Before fan-out, settle these contracts in a short committed note.

- Time totals use one ThreeCore calculation. They exclude pauses and breaks. A sleep adjustment must update this same calculation.
- Preserve the existing session-start-day attribution unless a separately tested migration adds enough interval evidence to split days accurately. Current sessions store total paused seconds, not every pause interval. Never invent a historical pause placement.
- Use local calendar dates and bounded reads. Keep the existing maximum 366-day history request unless an observed requirement justifies a different bound.
- Carry acceptance is a narrowly allowed transition from a closed source. Ordinary edits to closed days remain forbidden.
- Preserve source task identity, copied-task lineage, strictness, notes, steps, tags, and session history. Existing copies have no explicit lineage field in `FocusTask`. Add prospective lineage if needed and leave unknowable old lineage unknown.
- Specify what plan completion and planned minutes mean after drops, additions, and carry-over. If exact commitment-time records are required, persist them prospectively. Label legacy results derived from available records.
- Reserve migration names centrally. No two workers append competing schema versions.

## Run independent work, then the dependent work

1. Capture the baseline and freeze shared accounting/carry contracts.
2. Start BPRO-402, BPRO-404, and the bounded BPRO-406 work in parallel. The coordinator handles shared hooks and can draft BPRO-407 while workers run.
3. Verify and integrate each completed unit. Do not wait for all three to finish before reviewing a ready diff.
4. Start BPRO-408 after the UI worker finishes BPRO-406. It depends on stable shared focus commands, not history or calendar work.
5. Start BPRO-405's recovery implementation against the agreed accounting contract. Its onboarding and hotkey work can proceed independently, with exclusive ownership of shared app wiring.
6. Start BPRO-403 after BPRO-402's shared reads are verified. Integrate any BPRO-404 snapshot or BPRO-405 accounting changes before the final statistics verdict.
7. Finish BPRO-407's design, run integrated verification, and update the tickets from the coordinator.

The logical dependencies are `402 -> 403`, `closed-day carry contract -> 404`, and `shared accounting -> 402/403/405`. The dependency between 406 and 408 is an ownership choice, not a product dependency.

The fallback priority is a verified 406, usable 402, verified 404, then 405, 403, and 408. Draft 407 while waiting on builds or reviews. Do not chase a clock deadline by dropping tests or falsely closing broad tickets.

## Build history with one accounting owner

- [ ] Extend `Store.history` in `Sources/ThreeCore/AgentOperations.swift` or extract a focused history module. Return typed month/day/detail results rather than aggregating separately in SwiftUI and MCP.
- [ ] Reuse `Session.elapsed`, task/category joins, and existing tag totals. Preserve sessions when their task or category is archived or deleted.
- [ ] Show months, selected-month days with category strips, and selected-day task/session detail. Adapt to narrow windows without adding another permanent pane to the Today workspace.
- [ ] Show planned and actual duration, task state, reflections, and safe Linear links. Include useful empty and failure states.
- [ ] Keep the existing Done navigation working. Add History through existing navigation patterns without repurposing established keyboard shortcuts silently.
- [ ] Expose bounded CLI/MCP reads. Preserve current `get_history` compatibility where possible. Add explicit operations instead of silently changing an existing response shape.
- [ ] Test pauses, breaks, cross-midnight start-day attribution, DST, time-zone changes, carry copies, deleted references, and ordered range validation.
- [ ] Drive month/day/detail selection in the packaged native app. Compare the displayed totals with the real packaged CLI/MCP results and persisted fixture rows.

Done means native navigation works and the three clients agree on the same records. Compilation alone does not close BPRO-402.

## Close a day without losing unfinished work

The current `carry` operation calls `editableTask`, which rejects a closed source plan. Fix this before enabling automatic close. Do not relax `requireEditable` globally.

- [ ] Add an idempotent Store-owned close operation with a durable result. A repeated timer tick or relaunch must return the existing close rather than duplicate it.
- [ ] Default the close time to 22:00 local time. Permit configuration through the existing settings pattern.
- [ ] Close a nonempty committed plan when its work is resolved or its close time is due. Keep an uncommitted draft editable.
- [ ] If focus, an unresolved reflection, or a sleep-recovery decision still affects the day, defer close visibly. Do not stop a timer, fabricate an outcome, or choose keep/trim automatically.
- [ ] Catch up on eligible missed closes after launch or wake. Bound the work and make it restart-safe.
- [ ] Save the summary of recorded focus and outcomes. Persist actual break-skip decisions if they are currently absent. Old missing skip data is unavailable, not zero.
- [ ] Offer unfinished work without creating tomorrow's tasks automatically. Mark the source carried only when acceptance creates its copy successfully.
- [ ] Make acceptance/dismissal durable and idempotent. Enforce the destination cap, closed-day protection, and running-task rules in the same transaction.
- [ ] Preserve lineage, steps, tags, notes, strictness, and original sessions. A failure halfway through acceptance must roll back the entire operation.
- [ ] Verify close, repeated close, relaunch, accept, dismiss, full destination, concurrent accepts, and interrupted writes through the real Store and native review flow.

Done means the quiet summary and next-plan review work without losing work or silently rescheduling it.

## Expose the existing Make strict operation

- [ ] Call the existing `Store.setTaskStrict` in `Sources/ThreeCore/AgentOperations.swift`. Do not create a second policy implementation.
- [ ] Add one clear action to an existing task's controls. Explain that it prevents new unblock requests for that task. Show the strict state after success.
- [ ] Preserve the one-way operation. The app and agents gain no new loosening path.
- [ ] Respect closed/deleted-task guards and current policy for an already-granted exception. Do not silently change what strictness means.
- [ ] Verify native selection, persistence, app/CLI/MCP refresh, already-strict behavior, and the policy during an active task.
- [ ] Keep Category, Block, and Schedule controls open across timer ticks. Preserve the quiet category focus highlight and keyboard navigation.
- [ ] Correct the stale ticket/product statement that the Store mutation is missing. Record the deferred blocker ideas separately from the completed action.

Done means the selected BPRO-406 follow-up works. It does not mean Safari or other browser support exists.

## Recover sleep gaps and finish native setup

- [ ] Model a durable pending gap and its keep/trim decision. Coalesce overlapping sleep and lock observations. Do not subtract a gap twice.
- [ ] After more than ten minutes away during focus, show a quiet review. Keep retains the recorded work. Trim removes only the eligible unpaused part of the gap.
- [ ] Preserve the session identity, reflection, and one-timer invariant. If the session ended before the decision, correct its record without resurrecting it or changing a newer timer.
- [ ] Reconcile gap decisions with notifications, timer expiry, history, trends, and day-close. An unresolved decision remains recoverable after relaunch.
- [ ] Use injected clocks and explicit events for reproducible boundary tests. Handle clock rollback and nested lock/sleep without assuming wall-clock deltas are always trustworthy.
- [ ] Register a configurable global hotkey with the native platform. Default to Option-Command-Space. Report conflicts and registration failure without stealing a system shortcut.
- [ ] Open the existing menu-bar controls through the hotkey. Keep ownership and shutdown cleanup explicit.
- [ ] Add short, dismissible onboarding for the actual permissions, CLI install option, and Codex MCP configuration. Request permissions at the action that needs them.
- [ ] Inspect launch-at-login first. If missing, use `SMAppService.mainApp` with an opt-in control and OS-owned enabled, approval-needed, and error states. Do not install a second launch agent.
- [ ] Verify notification actions against actual app behavior. Add missing routing rather than another notification scheduler.
- [ ] Test keep/trim, duplicate wake, paused sleep, expiry during absence, relaunch, a newer timer, hotkey conflicts, skipped onboarding, and denied permission states.

Never put the shared Mac to sleep while workers or tool calls are running. Deterministic event tests and native review checks are useful proof, but they do not prove physical sleep/wake. Record any missing physical check explicitly.
Do not register login items or change the user's production notification/global shortcut settings merely to complete QA. Use isolated identity where possible and leave unavailable acceptance open.

## Present focus controls at the notch

- [ ] Add an optional compact presentation for the current task, category, remaining time, pause/resume, finish, and open-main-window actions.
- [ ] Reuse `AppModel` focus commands and the Store-backed running session. Create no second timer or duplicated reflection flow.
- [ ] Use public AppKit screen geometry and safe-area information. Prefer the built-in notched display. Keep controls outside the camera cutout.
- [ ] Preserve keyboard access, Escape, Reduce Motion, and readable focus states. Avoid expansion animations that interrupt work.
- [ ] On an unsupported display, use the existing menu-bar control and show a clear availability state for the notch option. Do not draw a fake hardware notch.
- [ ] Reconcile display changes, screen disconnects, Spaces, full screen, and app activation. Avoid taking keyboard focus while the user types elsewhere.
- [ ] Verify native controls against the main window and CLI. Confirm that pause/finish affect the same session exactly once.
- [ ] Test a real supported screen if one is available. Geometry fixtures prove placement logic only. Keep physical notch acceptance unverified when the hardware cannot be driven.

The default is opt-in. Preserve the main workspace and menu bar regardless of notch availability.

## Build trends from the verified record

- [ ] Extend shared Core reads with bounded statistics. Keep presentation math out of SwiftUI.
- [ ] Show daily focus for four weeks and a seven-day average, weekly completion, actual/planned accuracy, focus-quality share with category split, and distraction rates with the top three sites/apps.
- [ ] Add the committed-plan plus at-least-one-finished-task streak. A current day that is still in progress must not prematurely erase yesterday's streak.
- [ ] Define denominators in the public result and documentation. Distinguish zero activity, unavailable historical data, and an undefined ratio.
- [ ] Use actual recorded focus ratings and block events. Do not invent historical scores, commitments, break skips, or unavailable browser activity.
- [ ] Label the current period as partial. Keep date attribution consistent with history and day-close.
- [ ] Reuse the calculations for `get_stats` and the corresponding CLI output. Include per-tag trends without multiplying task focus time when a task has multiple tags in a global total.
- [ ] Prefer native Swift Charts where available. Include readable values and accessible descriptions so charts do not rely on color alone.
- [ ] Test zero denominators, partial weeks, long pauses, sleep trims, carried work, deleted records, missing ratings, and overlapping tag membership.
- [ ] Compare all five displayed charts and the streak with independently calculated fixture expectations and real MCP output.

Done means the numbers have an explicit meaning and the native chart states match that meaning.

## Finish the sync and companion design

- [ ] Audit every actual table, key, timestamp, relationship, and deletion behavior. Correct the older claim that every row is already sync-ready.
- [ ] Specify stable identities, tombstones, conflict resolution, retry/idempotency rules, schema upgrades, and how a device loses and regains access.
- [ ] Define timer ownership and reconciliation. An offline device cannot guarantee a globally exclusive timer without an explicit restriction or later conflict policy.
- [ ] Keep the app local-first. Propose a private CloudKit database and CKSyncEngine only after checking the platform and entitlement requirements.
- [ ] Separate Mac sync, a read-first iPhone/Watch companion, two-way Linear, and Screen Time into individually bounded follow-ups with acceptance checks.
- [ ] Preserve the current link-only Linear contract until a later implementation explicitly changes it.
- [ ] Give a recommended first slice, dependency order, migration/rollback strategy, and required real-device/account checks. Record alternatives and why they lost.
- [ ] Have a fresh reviewer challenge data loss, competing timers, offline edits, deletion resurrection, and account switching.
- [ ] Update BPRO-407 with the completed design and the implementation backlog. Close it only if its discovery deliverable is satisfied.

No CloudKit account, signing entitlement, Apple Developer portal access, paid call, or new device is needed to complete this design. Do not disguise a document as working sync.

## Keep moving when an operation cannot run

Make routine product and engineering choices within this plan. Log the choice, reason, and evidence. Do not ask the absent owner to choose labels, layouts, helper names, or implementation details.

| Obstacle | Next action |
| --- | --- |
| Worker/model unavailable | Report the failure and do the work in the parent when allowed. Do not silently switch providers or use Claude. |
| Worker stops making progress | Inspect its concrete output once, cancel it before replacement, and reclaim its exact state. Never leave two owners writing the same unit. |
| Shared file or migration conflict | Give it one owner, integrate the prerequisite, then rebase the dependent unit. Do not overwrite another worker's changes. |
| Missing hardware, entitlement, or OS permission | Finish the code and isolated proof, mark that acceptance check COULD NOT RUN, and select the next independent task. |
| Native control cannot be automated | Try one documented alternative, save the failure, and continue Store/protocol checks. Do not repeatedly retry coordinates or call a headless test native acceptance. |
| A legitimate user decision is outside this scope | Keep that external action disabled, document the proposed default, and continue the rest. No waiting question is needed. |
| Failing test or verified review finding | Reproduce and fix it at the owning layer. Do not weaken assertions, hide skips, or increase timeouts to make it green. |
| All remaining work depends on unavailable external state | Commit a clean checkpoint and give the exact unresolved gates. End the run honestly instead of polling indefinitely. |

This keeps the program moving. It does not turn an unavailable check into a pass.

## Verify, commit, and update from one coordinator

Use the smallest sufficient proof for each unit. A final integrated build gets the full regression set. Re-run a broader suite only when changes or an unresolved failure justify it.

```sh
make test
CONFIG=release ./scripts/bundle.sh
codesign --verify --deep --strict build/Three.app
python3 scripts/test-mcp.py --binary build/Three.app/Contents/Helpers/three
python3 scripts/test-draft-review.py --app build/Three.app
python3 scripts/test-scheduled-planning.py --app build/Three.app
python3 scripts/test-planning-supervisor.py --binary build/Three.app/Contents/Helpers/three
git diff --check
```

Inspect script options before reuse if they changed. Run every fixture with disposable data and keep scheduled planning disabled outside its test fixtures.

- [ ] Capture the baseline for changed native interactions and reproduce any regression before fixing it.
- [ ] Give one person or agent exclusive desktop ownership. Queue all native checks behind that owner.
- [ ] Verify keyboard navigation, empty/error states, persistence after QA relaunch, and cross-process refresh for each new interaction.
- [ ] Check that the category picker and nested task menus survive timer ticks and minute changes. Keep clock observation out of parent menu reconstruction.
- [ ] For history/trends, record query and native-selection latency against a fixed larger fixture. Compare equivalent baseline paths and optimize only observed regressions. Do not claim an unmeasured speedup.
- [ ] Have a fresh Sol 6.1 High reviewer inspect lifecycle, migrations, concurrency, and API compatibility. Same-model independent review is intentional under the user's model restriction. Do not wait for a forbidden cross-family review.
- [ ] Fix verified findings and re-check the changed path. Keep a failing candidate out of the integrated branch until repaired.
- [ ] Commit coherent verified units as work completes. Inspect staged paths before each commit and keep unrelated work out.
- [ ] Push the dedicated feature branch with normal Git operations when authorized by the pasted execution prompt. Never force-push, merge main, tag, publish, change VERSION, or install production as part of this plan.
- [ ] Keep `docs/verification/non-calendar/decisions.tsv` as the future run's decision trail, with evidence pointers. Keep large screenshots and raw logs under `build/verification/non-calendar/` and reference them from concise committed reports.
- [ ] Let only the coordinator update Linear status. Attach the exact commit and executed evidence. Implemented with an unverified required native check remains In Progress.

## Hand back a usable result

At the first reporting checkpoint, summarize each ticket as verified, implemented with a named acceptance gap, in progress, or design complete. Include exact commits, branch/PR links if created, commands that ran, and what the user can test.
Keep working on authorized ready tasks while the owner is away. Do not stop merely because one worker returned. If no safe ready task remains, finish with the explicit checkpoint above.

- [ ] Stop every owned QA process and delegated task that has no remaining job. Preserve the user's installed and manual-test apps.
- [ ] Confirm that production identity and data preservation checks still match, allowing documented user-driven changes rather than overwriting them.
- [ ] Confirm the working tree and remote branch state. Report any uncommitted work precisely.
- [ ] Leave calendar and BPRO-396 statuses unchanged. Make no new supported-OS or release claim.

## Read these source anchors before the relevant unit

| Area | Existing source |
| --- | --- |
| Guarded writes, snapshot, carry, timer operations | `Sources/ThreeCore/Operations.swift` |
| Bounded history and one-way strictness | `Sources/ThreeCore/AgentOperations.swift` |
| Actual schema and migrations | `Sources/ThreeCore/Store.swift` |
| Session elapsed time and persisted types | `Sources/ThreeCore/Models.swift` |
| Reflection preservation | `Sources/ThreeCore/Reflections.swift` |
| Tag aggregation and blocker events | `Sources/ThreeCore/Tags.swift`, `BlockStore.swift` |
| UI state, ticker, wake handling | `Sources/ThreeApp/AppModel.swift` |
| Menus, notification delegate, app lifecycle | `Sources/ThreeApp/ThreeApp.swift`, `MenuBarView.swift` |
| Task controls, category control, timeline | `Sources/ThreeApp/TaskViews.swift`, `CategoryPicker.swift`, `DayTimelineView.swift` |
| Existing navigation and settings | `Sources/ThreeApp/RootView.swift`, `WorkspaceView.swift`, `SettingsView.swift` |
| Packaged MCP contract | `Sources/ThreeCLI/MCP.swift`, `docs/MCP.md` |
| Isolated native QA pattern | `scripts/verification/bpro-399-qa.py` |
| Recent UI acceptance | `docs/verification/category-picker.md`, `docs/verification/task-entry-menu-polish.md` |

Read `/Users/divyanshudv/.agents/skills/emil-design-eng/SKILL.md` before UI work. Apply quiet controls, clear hierarchy, stable focus, and native keyboard interaction. Read relevant pstack and compound skills through their current installed paths.

The Sequence Work into Verifiable Units principle determines the integration order. The Never Block on the Human principle determines reversible defaults and fallback work. Neither principle weakens the Store guards or permits fabricated acceptance.
