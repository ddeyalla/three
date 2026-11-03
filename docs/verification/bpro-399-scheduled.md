# BPRO-399 scheduled planning verification

BPRO-399 adds opt-in app-owned local planning after the manual MCP draft path. Implementation and fixture checks pass. Native Settings Test, routine-source draft review, edit, and explicit Commit pass in a scratch app. Independent parent review remains open, and the ticket stays In Progress.

## Source and ownership

| Input | Value |
| --- | --- |
| Prepared worktree | `/Users/divyanshudv/.t3/worktrees/adhd/t3-fe1cb47d` |
| Branch | `t3/scheduled-planning-runner` |
| Initial HEAD | `5b043bc50838ae47269c29764912dc1f5581050b` |
| Core and scheduled MCP unit | `11e9eca88a6a0fdeba12124304e3668fb588174e` |
| App integration and Settings unit | `8d6637d7503552d7bfe1f7ed8a4d30e57bee6a82` |
| Final code and automated proof | `9b5701aa484f0ed4f133a49d2dcc19008d551204` |
| Native tested source | `8d6637d`, release app, macOS 27.0.1 arm64 |
| Native executable instruction hash | `4bca1b25394a7d69daa2547ea82eb63a19930c3b7a36887359d5cb9650da41ca` |
| Agent | In-thread `codex/gpt-6.1-sol`, High. No children or other model runs. |

The worktree began clean. This worker owns scheduling, its app integration, policy, tests, and these reports. The parent owns independent review and integration. VERSION, CHANGELOG, root audit, v0.3 code, and older native reports were not changed.

All artifact names below are relative to:

`/Users/divyanshudv/.t3/worktrees/adhd/t3-fe1cb47d/build/verification/bpro-399/`

## Chosen design and contract

The native app design reuses the existing one-second tick and wake, clock, and timezone notifications. A launchd runner was rejected because it adds a separately installed lifecycle and duplicates notification coordination. No extra scheduler timer or service was added.

SQLite owns planning preferences and run claims. One running row excludes every other scheduled or manual Test attempt across app instances. A prior attempt consumes automatic admission for its local date. Catch-up targets only today's date. Test can retry a known failure when no plan or running command exists.

The native process runner creates a suspended child group, records ownership, and then resumes it. It uses the login shell, home working directory, closed stdin, continuous-clock timeout, 64 KiB retained prefixes for each output stream, and process-group cleanup before releasing its claim. Both pipes continue draining after their caps.

The scheduled MCP boundary validates the run UUID, target date, absolute database path, active claim, and deadline. It lists eight read-or-draft tools and refuses all eighteen normal mutation tools by name. Draft creation is one atomic Store operation, with source `routine`, no prior plan, no prior draft write, no timer, and the existing five-task cap. It cannot commit or start focus.

The Codex default constructs a per-invocation local MCP configuration, ignores broader user configuration, and reads the bundled plan-day guide. Installed CLI help and actual TOML parsing support the command shape. No authenticated Codex or Claude model command ran.

## Automated proof

| Command | Observed result | Artifact |
| --- | --- | --- |
| `./scripts/swift.sh test --filter 'ScheduledPlanningTests\|ScheduledPlanningAppTests'` | Focused Core and App tests pass. | `focused-tests.log` |
| `make test` | 130 Core tests, 26 App tests, and 22 extension tests pass. Extension suite reports zero skipped tests. | `make-test.log`, `final-make-test.log` |
| `python3 scripts/test-mcp.py --binary build/Three.app/Contents/Helpers/three` | Normal 26-tool protocol, resources, malformed input, CLI sharing, caps, timers, carry-over, and restart checks pass. | `mcp-regression.log`, `release-mcp.log`, `final-mcp-regression.log` |
| `python3 scripts/test-scheduled-planning.py --app build/Three.app` | Real local fixture command runs through the native runner and relocated packaged helper. Restricted draft, source, eighteen forbidden mutations, commit=true, wrong date, duplicate write, expired startup, malformed startup, and normal-channel explicit commit checks pass. | `scheduled-protocol.log`, `release-scheduled-protocol.log`, `final-scheduled-protocol.log` |
| `CONFIG=release ./scripts/bundle.sh` | App and CLI release products build and bundle. Packaged helper resources survive relocation to a path with spaces. | `bundle-release.log`, `final-bundle-release.log` |
| `codesign --verify --deep --strict build/Three.app` | Ad-hoc signature verification passes. This is not notarization or release. | `signature.log`, `final-signature.log` |

Core behavior checks cover default-off preferences, strict local time validation, v8 migration, no backlog replay, next-day admission, multi-instance and manual races, existing draft/committed/closed/full work, claim expiry, backward clock, source, duplicate draft, timer and human-edit races, no-draft failure, notification dedupe through retry, unknown crash state, proven-gone recovery, login PATH, working directory, permission and nonzero failures, capped output, timeout, cancellation, and descendant cleanup.

App behavior checks cover shared settings and timer-preference preservation, native state output and errors, notice delivery count across reload, startup cancellation, and shutdown cancelling an already-running group after a FIFO readiness barrier. The shutdown assertion waits for real process cleanup without an arbitrary sleep. The optional `scheduledFixtureCommand` test performs its real protocol work only when invoked by the scheduled proof script, which supplies its scratch environment.

One focused test initially found SQLite text timestamp rounding at the exact deadline. The fix stores planning-run dates numerically. Deadline assertions stayed unchanged. No timeout or sleep was raised to hide a failure.

## Native Settings and Today proof

`scripts/verification/bpro-399-qa.py prepare` copied and relabelled the release bundle as `Three B399 QA.app`, bundle ID `com.deyalla.three.b399qa`, executable `ThreeB399QA`. It verified that every executable instruction matched the source app and re-signed only the QA copy. The process used `native/three.sqlite` and an empty scratch Chrome-data directory. It installed no CLI link or browser extension.

| Native action | Observed result | Artifact |
| --- | --- | --- |
| Open Planning | Scheduled planning is off. Local time is 09:30. Test, Save, default command, and trusted-command explanation are present. | `native/settings-before.png`, matching AX |
| Click Test with `printf 'native fixture stdout'; printf 'native fixture error' >&2; exit 9` | Status is failed, exit status is 9, and the error is visible. Both exact output strings are durable. | `native/failed-status.png`, matching AX, `native/native-run-results.json` |
| Edit the command through the native field, Save, and click Test | The local Python test fixture uses the actual packaged helper over restricted MCP. Status becomes succeeded with exit 0, routine draft, and no timer. | `native/succeeded-status.png`, matching AX, `native/native-run-results.json` |
| Restart only the QA app with the same database | Today shows `Draft from Routine · 3 tasks · 1h 30m`. No new planning run appears. | `native/routine-draft.png`, `native/native-run-results.json` |
| Edit the first title through the native pencil editor | The draft becomes `Reviewed scheduled fixture`, still uncommitted. | `native/reviewed-before-commit.json` |
| Press native Commit | The draft line and Commit button disappear. The saved plan is committed and retains every reviewed task ID, title, duration, and order. | `native/native-committed.png`, matching AX, `native/committed-after-native.json` |
| Click Test again | Settings says that the completed planning attempt and existing work are preserved. No third run is created. | `native/preserved-test-refusal.png`, matching AX, `native/acceptance-assertions.txt` |
| Quit the QA app with Command-Q | Its process exits. No timer session was created during the entire native flow. | `native/acceptance-assertions.txt`, final process checks |

The two native run UUIDs are `C3B9FAF4-74CF-4480-A777-BAF8DCBD9646` and `B0F14BF3-2812-4CD5-9D4B-DE53E3D9AC41`. Only the first has a notification claim. The explicit successful retry does not produce a repeated notice for that date.

Native stdout and stderr disclosure expansion remains unaccepted. CUA could operate fields and buttons and inspect the disclosures, but its coordinate fallback returned `noWindowsAvailable`. AX clicks left the disclosures unchanged, and setting their values correctly reported that they are not settable. Their exact saved output is proven through SQLite and App tests. No UI defect is inferred from the automation limitation.

Closing Settings also caused subsequent CUA reads to return `timeoutReached`. A process sample showed the app's main thread servicing its normal event loop. Only the identified idle QA PID 48418 was terminated. Restarting that QA copy and resetting the CUA session restored native access and enabled the Today review checks. Production PID 92331 was never signalled or restarted.

The final startup notification cleanup also removes stale UUID timer requests while preserving `planning.<date>` requests. That small follow-up is covered by a fresh app test run and final bundle verification. The native screenshots above precede that notification-only follow-up.

## Limits and preservation

- Real authenticated generation, model quality, account authentication, actual sleep/wake hardware timing, VoiceOver, physical notification-banner delivery, and native output-disclosure expansion are not claimed.
- Notification dedupe and the denied-delivery path are proven through durable claims and the injected app delivery callback. Last-run results remain visible independently of OS permission.
- Forced app termination can interrupt the supervisor. Unknown or surviving process groups hold the global claim. Three never kills a recovered PID or automatically retries an uncertain command. The app's timeout is not a launchd watchdog after the app itself crashes.
- A trusted command can have arbitrary external side effects and can deliberately escape its inherited process group. The restricted MCP channel is not an OS sandbox. Nothing silently rolls back those effects.
- The production database logical snapshot, installed executable hash, PID, start time, and command compare equal before and after QA. See `preservation-before.json`, `preservation-after.json`, and `native/acceptance-assertions.txt`.
- `native/open-files.txt` shows that the QA process opened the scratch database and did not open the production database. No browser profile was operated.
- All owned QA apps, fixture commands, MCP servers, and child groups are stopped at handoff. Scratch evidence remains on disk. No future writes are scheduled.

The implementation follows Model the Domain by keeping scheduling state in `PlanningSettings`, `PlanningRun`, and a restricted context. Make Operations Idempotent shaped date admission, atomic draft creation, and durable notice claims. Prove It Works shaped the actual packaged-helper fixture and native Test-to-review evidence.

The parent must independently review the final diff and these limits before marking BPRO-399 Done. A README link to [Scheduled planning](../scheduled-planning.md) is suggested for the parent integration pass.
