# BPRO-405 durable recovery

The recovery unit starts at `3270869ce3165137f228e3a36243450929bfcfd3` on `t3/durable-sleep-recovery` in the host-prepared worktree. Its scope is recovery accounting, explicit native events, and a quiet review component. App composition belongs to the coordinator. Calendar work, BPRO-396, native setup, and real sync remain outside this unit.

## Accounting contract

Migration `v12-sleep-recovery` adds `session.recoveryTrimSeconds`, with zero for old records, and the `recoveryGap` and `recoveryImpact` tables. Old JSON sessions also decode with zero trim. The unique running-session index stays unchanged.

`Session.elapsed(at:)` subtracts the additive trim after the existing pause calculation. `remaining` uses that result. `plannedEnd` adds the trim to the shared deadline. Task totals, history, and day-close use the same elapsed owner. The coordinator must repeat final trend verification after integrating v12.

A gap stores the actual begin observation and each affected focus session's unadjusted elapsed value. At return, the difference in unadjusted elapsed is the eligible absence. Completed pauses cancel through the cumulative pause total. An active pause caps elapsed at its begin. No historical pause intervals are inferred. Focus starts, pause, resume, extend, and the shared end helper record transitions against the open gap on the same transaction. Reflection completion and deferred reflection use that end helper.

When a pause ends inside a gap, recovery adds its fractional rounding credit to the baseline. The existing integer pause total would otherwise include that fraction as work. Recovery cannot trim it as unpaused absence. A negative difference within two milliseconds clamps to zero because GRDB stores dates at millisecond precision. Larger regressions disable trim.

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

## Coordinator lifecycle hooks

The new app files deliberately do not change AppModel, ThreeApp, Settings, or MenuBarView. The coordinator owns the following composition.

1. Create one `SleepRecoveryController(store: store)` immediately after opening Store. Call `start()` before the initial `closeEligibleDays`, snapshot reconciliation, notification schedule, or reflection timeout. Start registers observers and records `.relaunched` synchronously. A persisted observing gap becomes a pending review before launch catch-up can freeze totals.
2. After AppModel initializes, assign `recovery.didChange = { [weak self] affectedIDs in ... }`. The callback runs after the event or decision commits. Its IDs are the union of unresolved sessions before and after the operation, including an ended historical session. The callback must invalidate only those session notifications and timer caches. It must not cancel an unrelated newer session's notification.
3. Route wake through this controller before any AppModel reload. Replace the existing independent wake observer instead of relying on observer registration order. The controller maps workspace will-sleep and did-wake, distributed screen-lock and screen-unlock, and local clock-change notifications into explicit Core events. Display sleep and app activation do not fabricate a gap. Time-zone changes can keep their normal reload path.
4. Refresh recovery during normal reload before close, expiry, and notification reconciliation. While `suspendsReconciliation(for: running)` is true, suppress expiry chimes, automatic reflection presentation, live-reflection timeout/defer, and focus-end notification scheduling. Do not pause, stop, replace, or extend the shared session. Retain a live reflection's draft and give it a fresh prompt deadline after the explicit recovery decision. Preserve saved reflection answers and notes.
5. Remove pending and delivered notifications for the callback's affected IDs. Clear `scheduledNotification` only if its cached ID is affected. Rearm `reflectedBlock` only for an affected current session. After keep or trim, reload the Store snapshot and run normal reconciliation against the new shared `plannedEnd`. Other processes can also decide recovery, so compare same-session trim values across ordinary reloads and invalidate the same caches when they change.
6. Surface `controller.error` and a retry when event persistence fails. The controller retains failed events and their original timestamps in order. Its refresh retries the queue before reading state. Until that succeeds, suspend focus reconciliation and app catch-up close. Action errors on a historical review do not suspend an unrelated newer focus timer.
7. Offer an explicit quiet entry point when `reviews` is nonempty. Compose `RecoveryReviewView(controller: recovery, dismiss: { ... })` in the existing presentation flow. Keep and Trim are explicit buttons without a default keyboard action. Later and Escape dismiss only the view. They leave the durable decision pending. Stop the controller's observers during app teardown.

The controller has no timer, AppModel dependency, notification permission request, app activation, or automatic review window. `refresh()` does not call `didChange`, so the callback can invoke the owner's normal reload without recursion. Native timestamps use sleep-inclusive `mach_continuous_time` and the boot-session UUID. If that UUID is unavailable, a process identity makes a cross-process relaunch conservative and disables trim.

The UI follows the Emil design engineering skill and Three's existing typography and glass controls.

| Before | After | Why |
| --- | --- | --- |
| No recovery decision component | Explicit Keep, Trim, and Later controls | Later leaves the decision durable and unresolved |
| No interruption detail | Per-session titles, saved/current identity, and eligible trim | A historical correction remains distinguishable from a newer timer |
| No trustworthy measurement after a clock change | Trim is disabled and the reason is visible | The UI cannot offer an invented duration |
| No recovery motion | Native controls with no authored animation or default decision shortcut | Keyboard use stays immediate and cannot silently choose a correction |

## Scratch native fixture

Run this opt-in command after the integrated QA app is built.

```sh
python3 scripts/verification/recovery-fixture.py --binary build/Three.app/Contents/Helpers/three --create --scenario historical
```

The script creates a new temporary directory and prints its `fixture.json`. It never accepts an existing database path or launches an app. The manifest supplies `THREE_DB`, isolated Chrome data, session and gap IDs, and expected accounting. Scheduled planning stays disabled through its default settings in the new database. The exclusive desktop owner can use that environment with a uniquely identified QA app.

Scenarios are `pending`, `historical`, `untrusted`, and `observing`. Historical records preserve a reflection and verify the real packaged CLI and MCP default close guard. A known 900-second absence is eligible for trim, reducing recorded work from 1500 to 600 seconds. Pending uses the same gap with a running session. Untrusted disables trim. Observing tests relaunch after a durable begin and deliberately lacks native clock evidence, so relaunch offers Keep only. Native physical sleep is still a separate acceptance gate. Do not sleep or lock the shared Mac.

## Decision trail

The implementation compares unadjusted elapsed snapshots instead of adding a pause-interval ledger. Existing cumulative pause accounting provides the required difference and preserves unknown historical placement. Recovery states and source flags persist together instead of maintaining app-local gap state. Store guards remain mandatory instead of relying on callback composition.

The Model the Domain principle led to the durable gap and impact records. Make Operations Idempotent led to a single transaction for observation and decision. Sequence Work into Verifiable Units led to a verified accounting commit before native adaptation. The user forbids nested delegates. Design exploration and cleanup run in-thread, and the parent owns independent review.

The coordinator's `d4cd2567449c14d591d9c713cf88e7133f9ebf7d` is imported as `4e4defd728dbffecaa9a713f29df9543ccdb5478`. This dependency adds the transaction-owned expected-session guard to pause and resume. The recovery hooks remain after that guard. The decision-log conflict retains both upstream rows. This worker does not claim the identity fix as its own feature.

## Executed checks

| Check | Result | Evidence |
| --- | --- | --- |
| `./scripts/swift.sh test --filter DayCloseTests` | PASS, 24 tests | `build/verification/non-calendar/405-initial.log` |
| First recovery test compile | FAIL, missing `try` in the new reflection fixture, corrected | Initial `405-core-focused.log`, superseded by the rerun |
| `./scripts/swift.sh test --filter ThreeCoreTests` | PASS, 192 tests | `build/verification/non-calendar/405-core.log` |
| `./scripts/swift.sh test --filter fractionalPauseRoundingCannotTrimTimeOutsideUnpausedAbsence` before the precision fix | FAIL, 1.3 seconds of pause-rounding credit was incorrectly eligible | `build/verification/non-calendar/405-fractional-before.log` |
| `./scripts/swift.sh test --filter SleepRecoveryTests` after the precision fix | PASS, 18 tests | `build/verification/non-calendar/405-fractional-after.log` |
| `./scripts/swift.sh test --filter ThreeCoreTests` after the imported identity fix and precision fix | PASS, 194 tests | `build/verification/non-calendar/405-final-core.log` |
| `./scripts/swift.sh test` on the complete candidate | PASS, 194 Core and 49 App tests | `build/verification/non-calendar/405-final-tests.log` |
| `./scripts/lint-design.sh` | PASS | `build/verification/non-calendar/405-design-lint.log` |
| `./scripts/bundle.sh` | PASS, app and packaged helper build and ad-hoc signing | `build/verification/non-calendar/405-final-build.log` |
| `codesign --verify --deep --strict build/Three.app` | PASS | `build/verification/non-calendar/405-signing.log` |
| `python3 scripts/verification/recovery-fixture.py --binary build/Three.app/Contents/Helpers/three --create --scenario historical` | PASS, packaged CLI and MCP recovery deferral, shared history read, SQLite integrity and foreign keys | `build/verification/non-calendar/405-packaged-historical.json` |
| The same fixture command with `pending`, `untrusted`, and `observing` | PASS, isolated fixtures created and integrity checked | `build/verification/non-calendar/405-packaged-{pending,untrusted,observing}.json` |

The local decision log is `build/verification/non-calendar/405-decisions.tsv`. This worker leaves all shared app composition to its assigned owner. No nested delegates, app launches, desktop control, production mutations, real sync, release changes, or provider calls ran.

Physical sleep, physical lock, native review interaction, integrated app lifecycle acceptance, and final v12 trend integration remain COULD NOT RUN under this worker's scope. Headless event and Store tests do not close those gates. The coordinator must integrate the lifecycle hooks before native acceptance. Independent parent review remains pending. The candidate is not claimed as BPRO-405 acceptance.
