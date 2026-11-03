# Scheduled planning review corrections

The independent review of `5b043bc..b79853d` reproduced three defects. The command could outlive its deadline after GUI death. Enabling the switch discarded edited fields. Clock rollback hid the latest attempt. This report supplements the original [scheduled verification](bpro-399-scheduled.md).

## Ownership and chosen correction

The bundled `three planning-run` helper now owns command execution, deadline enforcement, output draining, process-group cleanup and the final SQLite result. The GUI launches it through `PlanningSupervisor` with a control pipe. Cancel, normal app quit or sudden GUI termination closes that pipe. EOF cancels the helper's own command group. No service, launchd job or new production runtime dependency is installed.

A separately installed watchdog was considered and rejected. A helper already ships in the app and can own one bounded attempt without adding another service lifecycle. Killing the helper itself remains an uncertain outcome. It never authorizes a blind retry or signalling a recovered PID.

Migration `v10-planning-supervisor` adds the helper PID without altering prior run results. A live helper retains its claim while saving the final result, including after its command group exits. Recovery checks liveness without signalling recovered processes. This prevents another app instance from stealing the final-result handoff.

Planning Settings now holds one form value. Save and Test validate and save enabled, time and command together. Toggling alone does not persist enablement or execute an older saved command. The footer states when the form applies. Last run uses attempt insertion order. Display timestamps remain wall-clock values.

## Executed proof

All commands ran in the integration checkout `/Users/divyanshudv/Documents/code-deyalla/adhd`. Database and command fixtures stayed under scratch paths. No model generation, production restart or installation occurred.

| Command | Observed result | Evidence |
| --- | --- | --- |
| `./scripts/swift.sh test --filter 'ScheduledPlanningTests|ScheduledPlanningAppTests'` | Scheduled Core and App checks passed after helper integration. Existing cancellation and shutdown tests now launch the real helper. | `build/supervisor-focused-final.log` |
| `python3 scripts/test-planning-supervisor.py --binary build/Three.app/Contents/Helpers/three` | Actual owner death, control-pipe cancellation and two-second deadline each stopped the real shell and ordinary child. Results persisted as cancelled, cancelled and timedOut. | `build/supervisor-lifetime-final.log` |
| `python3 scripts/test-scheduled-planning.py --app build/Three.app` | The relocated helper supervised a local fixture, created one routine draft, refused forbidden mutations and allowed explicit normal-channel commit. | `build/supervisor-scheduled.log` |
| `python3 scripts/test-mcp.py --binary build/Three.app/Contents/Helpers/three` | Normal MCP regression and two-server cap/timer checks passed. | `build/supervisor-mcp.log` |
| `make test` | 132 Core, 26 App and 22 extension tests passed before adding the migration regression. No extension skips. | `build/supervisor-all-tests.log` |
| `./scripts/swift.sh test --filter ScheduledPlanningTests` | The additional v9-to-v10 migration case passed with all scheduled Core checks. | `build/supervisor-migration.log` |

The original review's actual-process evidence is `/Users/divyanshudv/.t3/worktrees/adhd/t3-549f0df2/build/review/report.md`. Its settings and clock probes establish the before state. The new lifetime proof uses the packaged helper and kills only its fixture owner. It checks kernel group liveness and the durable result, rather than assuming a deadline assertion implies cleanup.

## Remaining verification

Fresh independent review of these corrections and the complete-form native Save/Test flow is pending. Final combined tests, release build and strict signing will follow that review. Hardware wake, physical notification banners, authenticated generation and VoiceOver are outside the proof claimed here. BPRO-396 release gates remain separate, and VERSION remains 0.2.4.
