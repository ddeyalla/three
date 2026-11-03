# BPRO-399 final correction review

Three needs bounded unattended planning, saved settings that match the displayed form, and the newest attempt visible after clock rollback. **PASS for the reviewed corrections. No new verified product findings.** Native output-disclosure expansion remains unverified. Parent integration and ticket closure remain with the parent.

## Scope and artifact

Reviewed only `b79853d867d07ca748afcb1b5c76836d9b96ca0a..5b9cd9abd937102839b8141072856aa94e744a90`. Starting HEAD was `5b9cd9abd937102839b8141072856aa94e744a90`, with a clean worktree. This includes `b000a8d`, `01a0f69`, `ddaae80`, and `5b9cd9a`. The earlier feature was not reviewed again.

This independent run used `codex/gpt-6.1-sol`, High, in-thread with no children. Only `/Users/divyanshudv/.t3/worktrees/adhd/t3-6b0bc9e3` was writable. No product file was modified or committed.

Inputs were `docs/verification/bpro-399-review-fixes.md`, `docs/scheduled-planning.md`, and the original report at `/Users/divyanshudv/.t3/worktrees/adhd/t3-549f0df2/build/review/report.md`.

The release bundle was built from starting HEAD on macOS 27.0.1. VERSION remained 0.2.4. `CONFIG=release ./scripts/bundle.sh` and `codesign --verify --deep --strict build/Three.app` both exited 0. Artifact SHA-256 values are:

| Artifact | SHA-256 |
| --- | --- |
| `build/Three.app/Contents/MacOS/ThreeApp` | `58c7fbc7d449a42dbb6445d8ef4692594dc413974967199b6169fa39b1e7bad4` |
| `build/Three.app/Contents/Helpers/three` | `ea727f3df52f9fa2f13592117a29216dc85b4b58189c9e26dce947d8683c97b2` |

`scripts/verification/bpro-399-qa.py prepare` copied, relabelled, and signed the scratch native app. Its executable instructions matched the release app. The `__TEXT,__text` hash was `efcf1cd57c623fc1fe5701a029b464957e844ea27155ef8643af88a784ae518f`. The QA executable was `ThreeB399QA`, bundle ID `com.deyalla.three.b399qa`. Its manifest is `build/verification/bpro-399/native/run.json`.

## Ownership trace and correction verdicts

`PlanningSupervisor` launches the bundled helper with a control pipe. `PlanningRunCommand` fences its helper PID before launching a command, rejects an expired claim before spawning, and monitors pipe EOF. `PlanningCommand` owns the suspended shell, records its group before resuming, drains output, enforces the deadline, and cleans up the owned group. The helper writes the final result. Recovery checks a live helper before releasing a missing group and never signals recovered PIDs.

`PlanningSettingsView` holds a complete `PlanningSettings` form. The switch edits that form. Save and Test call the same validated save before any Test execution. `latestPlanningRun()` orders by SQLite rowid. No extra service is installed.

| Prior finding or added guard | Verdict | Executed proof |
| --- | --- | --- |
| GUI death removed the lifetime bound | PASS | The actual release helper survived the fixture owner's SIGKILL, cancelled its shell and child, and persisted `cancelled`. Group 70184 and child 70392 were gone. |
| Pipe cancellation and independent deadline | PASS | Real groups 70395 and 70613, including ordinary children 70610 and 70834, were gone. Results were `cancelled` and `timedOut`. The deadline fixture used a real two-second stored deadline. |
| Expired claim before launch | PASS | The release helper finalized `timedOut`, left `processGroup` null, and created no readiness marker. No configured command started. |
| Enablement discarded command and time | PASS | Native switch editing retained displayed fields without changing saved settings or creating a run. Save persisted all three displayed values together. Test saved all three new values before the successful fixture execution. |
| Clock rollback hid the newest result | PASS | `lastRunUsesAttemptOrderAfterClockRollback` returned the second attempt and its output after the test moved its timestamp backward. |
| v9 migration preservation | PASS | `supervisorMigrationPreservesEarlierRunResults` retained the earlier result, output, exit code, and null helper owner. |
| Live helper final-result handoff | PASS | `recoveryDoesNotStealALiveSupervisorsFinalResult` executed a real command, let its group finish, and proved another Store could not steal the live owner's claim before the final result. |

The process proof was `python3 scripts/test-planning-supervisor.py --binary build/Three.app/Contents/Helpers/three`. It killed only its fixture owner. It checked actual kernel group liveness and SQLite results. See `build/final-review/supervisor.log`.

## Executed checks

Every command below exited 0. Logs are under `build/final-review` in this worktree.

| Command | Observed result | Log |
| --- | --- | --- |
| `make test` | 133 Core tests, 26 App tests, and 22 extension tests passed. Extension summary reported zero skips. | `make-test.log` |
| `./scripts/swift.sh test --filter 'ScheduledPlanningTests\|ScheduledPlanningAppTests'` | 18 scheduled Core tests and 4 scheduled App tests passed. App cancellation and FIFO shutdown checks used the real helper. | `focused.log` |
| `python3 scripts/test-scheduled-planning.py --app build/Three.app` | A relocated packaged helper supervised the fixture, refused forbidden MCP mutations, created a routine draft, and allowed explicit normal-channel Commit. | `scheduled.log` |
| `python3 scripts/test-mcp.py --binary build/Three.app/Contents/Helpers/three` | Real stdio, shared-store, restart, and two-server timer and cap checks passed. | `mcp.log` |
| `CONFIG=release ./scripts/bundle.sh` | Release app and helper built and signed. | `bundle.log` |
| `codesign --verify --deep --strict build/Three.app` | Strict signature verification passed. | `signature.log` |

The Core test count includes the environment-gated `scheduledFixtureCommand` case. Its complete real runner and MCP behavior was separately executed by `test-scheduled-planning.py`. The total suite count is 181, not an additional 181 independent end-to-end scenarios.

## Actual native Save, Test, and draft review

All native actions used the relabelled release app with `THREE_DB` and `THREE_CHROME_DATA` set to scratch paths. QA PIDs were 71728 and, after native Quit and restart, 90022. The old offscreen SettingsProbe was not reused. Its auto-saving-switch expectation is obsolete. The actual native sequence tested explicit Save instead.

Evidence in this section is under `build/verification/bpro-399/native`.

| Native action | Actual result | Evidence |
| --- | --- | --- |
| Edit command to the local exit-7 fixture, time to 23:58, and switch on without Save | New values remained displayed. SQLite still held the disabled 09:30 exit-9 fixture. There were zero runs. | `unsaved-toggle.json`, native AX observations in this review |
| Click Save | SQLite held enabled=true, time=23:58, and the complete new command. Zero runs remained. | `saved-all-fields.json` |
| Click Test | Last run displayed failed and exit 7. Exact captured output was `CORRECTED_NATIVE_STDOUT` and `CORRECTED_NATIVE_STDERR`. | `failed-status.png`, `failed-status-ax.txt`, `native-test-results.json` |
| Focus the native fields, enter the Python draft fixture, change time to 23:56 and switch on, then click Test directly | Test persisted all three values before execution. The release helper returned succeeded with exit 0 and created a routine draft. | `succeeded-status.png`, `native-test-results.json` |
| Change time to 25:99, command to a harmless invalid-form marker, and switch off, then click Save and Test | A visible HH:mm validation error appeared. All saved fields remained unchanged and no fourth run was created. | `invalid-form.png`, `invalid-save-test.json` |
| Quit and restart only QA | Today displayed `Draft from Routine · 3 tasks · 1h 30m` and an explicit Commit control. No new run appeared. | `routine-draft.png`, `routine-draft-ax.txt` |
| Edit the first title to `Final correction reviewed task` | SQLite remained draft with source routine. No timer existed. | `reviewed-before-commit.json` |
| Click Commit | The draft notice and Commit control disappeared. SQLite became committed and retained every reviewed task field. No timer existed. | `committed.png`, `committed-after-native.json` |

There were three native Test attempts. The middle attempt is excluded from the complete-form success proof. An unfocused accessibility `setValue` changed the command's AX display without delivering a native edit to its binding. Test consequently ran the previously saved exit-7 fixture. Focused editing through CUA's native paste then enabled Save and produced the expected complete-form success. This automation mismatch is recorded in `before-unsaved-test.json` and `after-unsaved-test.json`. It is not a verified product finding. The two failed attempts and the successful attempt remain visible in `native-test-results.json`.

Native output disclosure expansion is **COULD NOT RUN**, not PASS. AX clicking stdout scrolled the form but left the disclosure collapsed. One screenshot-based coordinate fallback returned `Computer Use server error -10005: noWindowsAvailable`. Exact stdout and stderr are proven in SQLite and App tests. No product defect is inferred from the failed automation.

The existing `scripts/shot.sh` capture also returned `no window for pid 71728`. CUA's native screenshot API captured the actual QA window successfully. The report uses those screenshots.

## Preservation, cleanup, and limits

`build/final-review/cleanup-and-preservation.json` records zero remaining owned processes and no scheduled future writes. Both BPRO-399 QA instances quit through native Command-Q. The optional frozen BPRO-396 instance also quit before this handoff. Every long-running test command completed with exit 0. No QA copy remains running. Desktop ownership is released.

The production table fingerprints, installed executable hash, PID 92331, and start time `Tue Nov 3 06:22:12 2026` matched exactly before and after. Evidence is `build/verification/bpro-399/preservation-before.json` and `preservation-after.json`. QA open-file inspection proved its scratch database was open and the production database was absent. See `native/open-files.txt`.

No real browser profile was operated. Native CUA paste uses its documented clipboard restoration. No Copy action or browser paste was used. There was no independent byte-for-byte clipboard snapshot. No credentials, authenticated model, paid provider, production restart, install, new service, push, tag, or release was used.

Hardware sleep and wake, physical notification delivery, VoiceOver, authenticated generation quality, macOS 26 runtime, and physical hide refusal remain outside this proof. Killed-helper and recovered-PID uncertainty retains the documented conservative block. BPRO-396's separate limits are in [the bounded fresh status probe](bpro-396-final-status-probe.md). No ticket was marked Done by this review.

Prove It Works determined the use of actual helper processes, native fields, displayed results, and database comparisons. The complete correction review ran in-thread because the user prohibited children.
