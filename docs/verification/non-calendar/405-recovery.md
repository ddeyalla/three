# BPRO-405 durable recovery

The recovery unit starts at `3270869ce3165137f228e3a36243450929bfcfd3` on `t3/durable-sleep-recovery` in the host-prepared worktree. Its scope is recovery accounting, explicit native events, and a quiet review component. App composition belongs to the coordinator. Calendar work, BPRO-396, native setup, and real sync remain outside this unit.

## Accounting contract

Migration `v12-sleep-recovery` adds `session.recoveryTrimSeconds`, with zero for old records, and the `recoveryGap` and `recoveryImpact` tables. Old JSON sessions also decode with zero trim. The unique running-session index stays unchanged.

`Session.elapsed(at:)` subtracts the additive trim after the existing pause calculation. `remaining` uses that result. `plannedEnd` adds the trim to the shared deadline. Task totals, history, trends, and day-close use the same elapsed owner.

A gap stores the actual begin observation and each affected focus session's unadjusted elapsed value. At return, the difference in unadjusted elapsed is the eligible absence. Completed pauses cancel through the cumulative pause total. An active pause caps elapsed at its begin. No historical pause intervals are inferred. Focus starts, pause, resume, extend, and the shared end helper record transitions against the open gap on the same transaction. Reflection completion and deferred reflection use that end helper.

Nested lock and sleep share one observing gap. Duplicate begin events for an active source and duplicate end events converge. All observed sources must end before the gap closes. A relaunch closes an already durable observing gap at the relaunch observation. A relaunch with no begin record creates no absence.

Above 600 seconds away, an affected focus session requires review. Exactly 600 seconds does not. Short observations use the distinct `notRequired` state. They do not silently record a keep or trim decision. Break-only observations have no focus impact or review. Focus expiry does not end a session in this module.

Keep changes only the gap decision. Trim adds each saved eligible amount to that exact session. End times, task status, reflection, identity, and newer sessions stay intact. Decisions use one database write transaction. A retry or a competing decision returns the first durable result. A failed decision rolls back both the elapsed correction and the decision.

## Clock policy

`RecoveryInstant` accepts an injected date and optional continuous-clock value with a boot identity. Native integration supplies both continuous evidence and the boot identity. A rollback, an out-of-order timer transition, a boot mismatch, a wall/continuous difference above two seconds, or an explicit clock-change event disables trim for that gap. A delayed observation beginning before a previously closed gap also disables trim. This conservative rule prevents an overlapping historical interval from being subtracted twice. The review explains why only Keep is available.

Ordered date-only instants support deterministic callers and fixtures. Native events must use continuous evidence. Recovery never invents the period before an observed begin, including time before launch or after a crash without a begin record.

## Store hooks

- `observeRecovery(_:at:)` records a typed begin, end, relaunch, or clock-change event and returns the durable `RecoveryStatus`.
- `recoveryStatus()` reads observing state, pending reviews, affected session IDs, and saved eligible amounts.
- `decideRecovery(_:decision:now:)` applies the first explicit keep or trim decision transactionally.
- `RecoveryStatus.suspendsReconciliation(for:)` identifies an affected session whose expiry and notification reconciliation must wait.

`closeDay`, `closeEligibleDays`, and `dayCloseStatus` always query unresolved recovery on their own database connection. The query covers both the session's attributed start day and its task's plan. An injected `DayCloseRecoveryCheck` can add a deferral. Even an explicit false callback cannot disable the durable guard. This protects CLI, MCP, and the existing DayCloseView.

## Decision trail

The implementation compares unadjusted elapsed snapshots instead of adding a pause-interval ledger. Existing cumulative pause accounting provides the required difference and preserves unknown historical placement. Recovery states and source flags persist together instead of maintaining app-local gap state. Store guards remain mandatory instead of relying on callback composition.

The Model the Domain principle led to the durable gap and impact records. Make Operations Idempotent led to a single transaction for observation and decision. Sequence Work into Verifiable Units led to a verified accounting commit before native adaptation. The user forbids nested delegates. Design exploration and cleanup run in-thread, and the parent owns independent review.

## Executed checks

| Check | Result | Evidence |
| --- | --- | --- |
| `./scripts/swift.sh test --filter DayCloseTests` | PASS, 24 tests | `build/verification/non-calendar/405-initial.log` |
| First recovery test compile | FAIL, missing `try` in the new reflection fixture, corrected | Initial `405-core-focused.log`, superseded by the rerun |
| `./scripts/swift.sh test --filter ThreeCoreTests` | PASS, 192 tests | `build/verification/non-calendar/405-core.log` |

Physical sleep, physical lock, native review interaction, and integrated app lifecycle acceptance remain unproved. Headless event and Store tests do not close those gates. The coordinator must integrate the lifecycle hooks before native acceptance.
