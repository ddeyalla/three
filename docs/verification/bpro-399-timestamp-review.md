# BPRO-399 timestamp boundary review

Three needs the original planning start accepted and the exact deadline rejected after numeric database persistence. **PASS for this correction. No new verified findings.** Parent acceptance and tracker state remain with the parent.

## Scope

Reviewed only `1cb1393dfae4821de0e58aa2abb9d323c620dd37..08cd936ad2222bc75ee8d0d5bdc409a9fc5f4cb4` on 2026-11-03. The worktree was clean at starting HEAD. The correction is `5d2cb4a`; `08cd936` adds its audit record. Scope comprises `PlanningRun.isWithinWindow(at:)`, scheduled admission, CLI prelaunch, command-runner epoch comparisons, and `timestampBoundariesSurviveNumericDatabaseRoundTrips`.

This fresh `codex/gpt-6.1-sol` High verification ran in-thread in `/Users/divyanshudv/.t3/worktrees/adhd/t3-c69254a6`. No children, desktop actions, authenticated model calls, production database access, or product edits occurred. Earlier feature and native reviews in [the final correction review](bpro-399-final-review.md) were not repeated.

## Ownership and boundary proof

`PlanningRun` stores and decodes dates with `timeIntervalSince1970`. Its window helper requires the same local day and the half-open epoch interval `[startedAt, deadline)`. Scheduled admission and CLI prelaunch use that helper. The command runner compares the same epoch values while retaining its separate monotonic timeout and cancellation behavior.

`build/timestamp-review/CombinedProbe.swift` links this worktree's freshly built `ThreeCore.o` and `GRDB.o`. It creates scratch databases through the real Store, reads raw SQLite values and decoded records, exercises actual draft admission, and launches harmless `/usr/bin/true` commands through `PlanningCommand` with an injected clock. It checks every owned group is gone.

The probe also executes the original `scheduledRun` function extracted from `git show 1cb1393:Sources/ThreeCore/ScheduledPlanning.swift`. Only the function name and visibility change for standalone compilation. Its database fetch, Date comparisons, and rejection remain intact. The extracted source is `build/timestamp-review/OriginalAdmission.swift`.

Both inputs use the regression's local 01:00 reference time with `nextDown` and `nextUp`. Observed timezone was `Asia/Kolkata`.

| Value | Original reference seconds | Decoded reference seconds | SQLite epoch seconds |
| --- | --- | --- | --- |
| `nextDown` start | 815340599.99999988 | 815340600 | 1793647800 |
| `nextDown` deadline | 815341199.99999988 | 815341200 | 1793648400 |
| `nextUp` start | 815340600.00000012 | 815340600 | 1793647800 |
| `nextUp` deadline | 815341200.00000012 | 815341200 | 1793648400 |

SQLite reported `integer` for these whole epoch values. The epoch values survived exactly. Foundation reference seconds shifted by one ULP, `0.00000011920928955078125` seconds, in opposite directions for the two inputs.

The original function **rejected the original start and accepted the original exact deadline for `nextDown`**. These are the two assertions the deterministic regression requires to behave oppositely. The `nextUp` input was a passing control under the original function. Therefore the regression detects the original defect without relying on wall-clock timing.

The current code passed 15 boundary cases. Each input covered the original start, decoded start, the preceding representable epoch value, the last representable epoch value before deadline, the original deadline, decoded deadline, and the following representable epoch value. Starts and inside-deadline values were accepted. Before-start values were rejected and the command returned `cancelled`. Exact deadlines and later values were rejected and the command returned `timedOut`. Rejected draft calls left the day empty. A successful call at each original start created a draft.

The fifteenth case crossed local midnight while remaining inside the numeric interval. The helper and draft admission rejected the different local day, and the command returned `cancelled`. All 15 real command groups were gone. Full values, outcomes, and group IDs are in `build/timestamp-review/boundary-probe.log`.

## Executed checks

All final commands exited 0. Evidence paths are relative to this worktree.

| Check | Observed result | Evidence |
| --- | --- | --- |
| `./scripts/swift.sh test --filter 'ScheduledPlanningTests/(scheduledDraftIsAtomicOnceAndRoutineWithBoundaryGuards\|timestampBoundariesSurviveNumericDatabaseRoundTrips)'` | Both requested boundary tests passed. | `build/timestamp-review/boundary-tests.log` |
| `./scripts/swift.sh test --skip-build --filter ScheduledPlanningTests` | 19 scheduled Core tests passed, including both boundary tests. | `build/timestamp-review/scheduled-core.log` |
| Standalone original-source and current-code probe | Both original failure modes reproduced; all 15 current cases passed. | `build/timestamp-review/CombinedProbe.swift`, `build/timestamp-review/probe-build.log`, `build/timestamp-review/boundary-probe.log` |
| `python3 scripts/test-scheduled-planning.py --app /Users/divyanshudv/Documents/code-deyalla/adhd/build/Three.app` | One actual fixture test passed. A relocated packaged helper created a routine draft, refused 18 forbidden mutations, and allowed explicit normal-channel commit. | `build/timestamp-review/packaged-scheduled.log` |
| `python3 scripts/test-planning-supervisor.py --binary /Users/divyanshudv/Documents/code-deyalla/adhd/build/Three.app/Contents/Helpers/three` | Four cases passed. Owner death and pipe cancellation persisted `cancelled`; the real deadline persisted `timedOut`; expired prelaunch started no command and persisted `timedOut`. | `build/timestamp-review/packaged-supervisor.log` |

The two focused tests overlap the 19-test run. `scheduledFixtureCommand` returns without its fixture environment during the ordinary 19-test run; the packaged script separately executed its real supervisor and MCP path. These counts do not imply a new full-suite run.

The fresh debug helper SHA-256 is `8f9bfac360afea8ce2e58bf0023316945f7c6da0c19abcce236bfafab371c984`. The linked `ThreeCore.o` SHA-256 is `9394ce36c6308cfe5e4a91b8c46c4252b5edf75d1665c4a7117932533e9fb53a`. The parent-provided release helper SHA-256 was unchanged before and after, `ff03e34736117aef2d013007e36cdc4040aa82a0e693d9e28b8d7e14341d251c`. This review did not rebuild or independently establish the parent release bundle's source provenance.

## Cleanup and limits

`build/timestamp-review/cleanup.json` records all 15 probe groups and three packaged supervisor groups absent, all three recorded supervisor children absent, and no remaining relevant helper or worktree processes. Retained scratch planning records are terminal. Fixture scripts completed and removed their temporary databases. No process, service, timer, or scheduled future write remains from this verification.

The product diff against reviewed HEAD is empty. Only this report is committed. No production database was opened. The parent app was read without modification; the scheduled fixture used its own relocated copy. No install, push, tag, release, tracker update, or UI review occurred. Full-suite, signing, and earlier native evidence remain the parent's separate proof.

Prove It Works determined the use of actual SQLite round trips, the extracted original admission function, real command groups, and packaged helper fixtures. Investigation and verification ran in-thread because the user prohibited children. No new finding needs a recommendation.
