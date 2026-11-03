# Non-calendar execution contracts

The run starts from `81e5a96a4dd65c9ecf4dcc77ae50978a7df72d9c` on `dv/ai-planning-v04`. The clean coordinator branch is `dv/non-calendar-backlog`. The remote is `https://github.com/ddeyalla/three`. Fetch succeeded and the base contains `a0925d2`.

## Accounting and data

`Session.elapsed(at:)` owns elapsed work. Every history, trend, task total, and day-close calculation uses it. Aggregate focus excludes break sessions. Existing sessions are attributed to their start date in the current local calendar. Historical pause placement is unknown. No client invents intervals or splits paused time across dates.

Reads take ordered, inclusive local dates with at most 366 days. Existing `get_history` keeps its session-array response. New detailed reads use explicit Codable result types and new operation names. History preserves sessions and their deleted or archived references.

Planned totals from mutable legacy rows are labelled derived. They exclude dropped and carried tasks. Exact commitment denominators require a prospective snapshot, never an inferred backfill. A close summary freezes the recorded outcomes before later carry acceptance. Missing historical break decisions and ratings remain unavailable.

Recovery will use durable gap records and an additive session trim field, default zero for old sessions. Trim changes `Session.elapsed`, not start/end identity or another timer. The eligible trim cannot include pauses or already adjusted intervals. Duplicate observations and decisions converge on one result.

## Lifecycle and ownership

Carry from a closed source is an explicit, narrow Store transaction. Other closed-day edits stay forbidden. Acceptance creates one copy and records lineage, then marks its source carried. It preserves steps, tags, notes, strictness, category, and Linear reference. Original sessions remain attached to the source. Repeated acceptance returns the original successful result. Dismissal is durable and cannot create work. The destination remains editable, later than the source, and within the five-task cap.

Day-close defaults to 22:00 local. It applies to nonempty committed plans when resolved or due. Active focus, pending reflection, and pending recovery defer closure. Catch-up is bounded and restart-safe. A read or close never silently creates tomorrow's tasks.

Migration `v11-day-close` is reserved for the day-close worker. That worker has exclusive temporary ownership of Store.swift, the carry and commitment hooks in Operations.swift, and any needed prospective lineage field in Models.swift. No other worker edits these files until integration. Recovery owns the next migration, `v12-sleep-recovery`, after v11 integrates. History and strict UI need no migrations.

The coordinator owns CLI/MCP registration, AppModel, app routing, ThreeApp, and Settings composition. Workers implement focused modules and report exact integration hooks. History owns History.swift, HistoryView.swift, and its tests. Day-close owns DayClose.swift, its review view, and its tests. Strict UI owns TaskViews.swift and its focused action helper/tests. All writes use the host-created worktree. Workers do not revert others' work or delegate further.

## Execution and proof

First integrate shared contracts. Run 402, 404, and 406 in separate worktrees. Start 408 after 406 releases UI ownership. Start 403 after 402's shared reads pass. Integrate 405 accounting before final trend verification. Draft 407 against the actual final schema.

No more than three implementation workers run concurrently. Fresh Sol 6.1 High independently reviews each candidate. Terra alone owns desktop interaction. All other workers use headless checks. Same-model review follows the user's explicit restriction. The model sheet is absent at both configured fallback locations; explicit user model choices apply.

The done predicate is each ticket's documented acceptance proved by its executed checks. A required unverified native or hardware check keeps its ticket open. Compilation and deterministic event tests do not prove physical sleep, notch hardware, permission acceptance, or macOS 26.

Use disposable databases and unique QA bundle IDs, executable names, and Chrome folders. Never run make run/install, restart production, replace Three Manual Test, or sleep the shared Mac. Scheduled planning stays disabled outside local fixture commands. No paid model calls, calendar work, production installation, merge, release, tag, or force-push is authorized.

Commit and normally push verified units. Only the coordinator updates Linear. BPRO-396, 400, and 401 stay unchanged. At 18:00 Asia/Kolkata report actual progress and remaining gates, then continue ready work. Raw logs live under build/verification/non-calendar. Decisions are appended to decisions.tsv.

## Throughput checkpoint

Seven scoped tickets include six implementation units and one discovery document. History precedes trends. Recovery and day-close share accounting. Three implementation slots and one desktop owner bound contention. The first integration checkpoint is the smallest verified strict action, followed by history and day-close. Hardware gaps never block an unrelated ready unit.

## BPRO-405 ownership grant after v11 integration

The recovery worker receives exclusive temporary ownership of `Store.swift`, session accounting fields in `Models.swift`, timer hooks in `Operations.swift`, and `DayClose.swift` defaults. It owns new recovery Core/controller/review modules and recovery tests. It reserves only `v12-sleep-recovery`. Every caller must receive the durable unresolved-gap guard by default in the Store; omission by a CLI or view must not permit premature close. The worker does not edit AppModel, ThreeApp, Settings composition, CLI/MCP, History or Stats.

A separate native-setup worker receives exclusive temporary ownership of AppModel.swift, ThreeApp.swift, SettingsView.swift and MenuBarView.swift for hotkey, onboarding, login and notification integration. It owns new setup/platform modules and focused tests. It preserves integrated day-close, notch and history hooks. It does not edit Core, recovery modules, history/stats, or CLI/MCP. No other writer edits either granted area until return. The coordinator will integrate the recovery controller hooks after both return.

The sole Terra desktop owner verifies the frozen integrated candidate independently of both implementation workers. A fresh Sol reviewer checks day-close, notch and the two History date fixes. All implementation and review workers use Sol 6.1 High with no nested delegates.

A verified P2 notch race required a narrow coordinator exception to the temporary grants. The coordinator adds only expected-session ID parameters/guards to Operations.pause/resume and passes the validated Session through AppModel.togglePause. Both active owners were notified before the edits and will integrate the exact fix commit while preserving their recovery/setup work. Their remaining ownership stays unchanged.

## Final integration ownership

The initial recovery and native-setup workers have completed and been stopped. A fresh lifecycle worker exclusively owns AppModel, ThreeApp, RootView, MenuBarView, SettingsView, TimerNotifications, the recovery controller/review views, and focused App integration tests. It composes v12 with native setup and preserves the current ChangeSignal observer until the coordinator resolves the separate native diagnosis.

A fresh protocol worker owns ThreeCLI/Three.swift, MCP.swift, recovery Codable conformances only in SleepRecovery.swift, protocol documentation, packaged recovery tests, and a new Core test file for recovery-adjusted History/Stats. It exposes explicit manual-channel reads and decisions, never raw sleep/lock simulation tools or scheduled access. Stats, History, Models, Store, and Operations remain outside its ownership.

A fresh performance worker owns only the measured event-date reuse in Stats.swift, read-performance.py/swift, and its report. It starts after the coordinator's moved-commitment fix. It preserves all corrected commitment logic and validates equivalent v12 fixture results before and after the change. It makes no native latency claim.

The coordinator owns final schema discovery and cross-unit integration. One fresh Sol reviewer examines the frozen recovery Core and native setup diff. Terra remains the sole desktop owner and is investigating the submenu collapse on its separately frozen candidate. No worker delegates further.
