# BPRO-406 native acceptance receipt

Desktop QA: Codex `gpt-6.1-terra`, high reasoning effort, 2026-11-03. Candidate source `b6ec011752ed14e56aee4de9ecab0b23ba31d8ea`; clean checkout at start, `/Users/divyanshudv/.t3/worktrees/adhd/t3-a2ae7e58`, branch `t3/bpro-406-native-qa`. No product edits or Linear writes.

## Isolation and build

| Executed check | Result |
| --- | --- |
| `./scripts/bundle.sh` | PASS, build 109; log `build/verification/non-calendar/406-native/three-406-build.log`. |
| `python3 scripts/verification/non-calendar-qa.py prepare` | Expected rejection: `Build inputs differ from the specified baseline commit`. This baseline helper was not bypassed. |
| `THREE_STRICT_FIXTURE_DB=/tmp/three-406-qa-SR4XMXmc/three.sqlite ./scripts/swift.sh test --filter StrictTaskActionTests/prepareStrictTaskNativeFixture` | PASS, one fixture test; log `build/verification/non-calendar/406-native/three-406-fixture.log`. It asserts scheduled planning disabled and refuses an existing path. |
| `python3 /tmp/three-406-prepare.py` | PASS. Copied candidate bundle into a new temporary directory, renamed executable and bundle ID, ad-hoc signed helpers and app, verified deep strict signature and compared `__TEXT,__text` instructions with the built candidate. Script and manifest are in `build/verification/non-calendar/406-native/`. |
| `codesign --verify --deep --strict '/tmp/three-406-qa-SR4XMXmc/Three 406 QA.app'` | PASS. |

The isolated app is `/tmp/three-406-qa-SR4XMXmc/Three 406 QA.app`, bundle ID `com.deyalla.three.qa406.sr4xmxmc`, executable `Three406QASR4XMXmc`; database `/tmp/three-406-qa-SR4XMXmc/three.sqlite`, Chrome data `/tmp/three-406-qa-SR4XMXmc/chrome`. Source executable SHA-256 `6db84f6cacd81b043a96c907e9a4a37a8908a24bcd85695ceaa10ee4a894e6c1`, relabelled signed executable `5d26d9c4dc288b22ef1e7616cd502472e37bc3aa31e35bb1bbe967d6830dd51c`, matching instruction-text digest `e50c7995bf4f462fcb62ec27ddd8001d71ef2f68cbca853ed308dfc1514a3c95`. `open -n --env THREE_DB=... --env THREE_CHROME_DATA=...` launched this bundle. An initial direct background invocation exited before UI inspection; it did not supply native evidence.

## Native observations

| Check | Result |
| --- | --- |
| Active task Make strict | PASS. CUA selected **Make strict (one-way)**; the card displayed Strict, countdown continued from 59:17 to 59:05, and its menu subsequently showed disabled **Strict (one-way)**. Its accessible help stated the one-way effect and existing-unblock expiry. Focus menu showed **Unblock for 5 Minutes** disabled. |
| Real packaged CLI and MCP | PASS. `today --json` before and after, and MCP `get_today` after `set_task_strict` on the non-strict companion, agree on task IDs and strict values; the active session and task IDs match. The CLI running state was unpaused. JSON receipts are `before.json`, `cli-after.json`, and `mcp-after.json` in the raw directory. An initial comparison script exited with `KeyError: 'task'` because CLI and MCP have different response shapes; a corrected comparison of their actual shapes passed. |
| External refresh | PASS. MCP `set_task_strict` changed companion `2D554401-C00C-4866-AF6E-FBEA350C2913`; the already-open native app displayed its Strict metadata without relaunch. |
| Relaunch | PASS. After verifying PID 86098's exact isolated executable and sending SIGTERM, relaunched the same isolated app. Native card remained Strict and countdown continued; packaged CLI confirmed session `8CAD6349-050B-424F-A05B-73105E365F08` and task `8E056DF0-E7B5-46BC-B68B-68105932F3A6` unchanged and unpaused. `relaunch.json` is in the raw directory. The initially strict task's menu also showed disabled **Strict (one-way)** and no loosening action. |
| Category menu | PASS for observed transition and selection. The companion's Category submenu was visible at 56:57, 56:26, 56:05 and 55:58 while focus total changed from 3m to 4m. Selected Admin; SQLite readback confirmed Admin. |
| Block menu | PASS for observed transition and selection, with a stability caveat. After relaunch the submenu was visible at 52:04 and 51:55, crossing the displayed minute and focus total 7m to 8m; selected 25m and SQLite confirmed it on the already-strict task. Earlier, a companion Block submenu visible at 55:38 was collapsed by 55:13 while its parent remained open; cause was not established. Another selection of 45m persisted on that companion. Longer unattended stability remains open. |
| Schedule menu | PASS for observed transition and selection. On the non-running companion, Schedule remained visible at 54:17 and 53:59 as focus total advanced 5m to 6m. Selected Tomorrow; SQLite showed 2026-11-04, Admin, 45 minutes and strict=1. |
| Category keyboard | PASS for Down and Return: focus moved Coding to Writing with a subdued highlight, Return selected Writing. Reopened, Down then Escape closed the popover without changing Writing. **COULD NOT RUN:** verify focus returned to the triggering chip: the post-dismissal AX tree did not identify a focused element. |
| Stale closed day | PASS. Added a separate non-strict fixture task, stopped the fixture session with the packaged CLI, opened its menu, then changed only the disposable fixture day to `closed` via SQLite while the menu was open. Selecting Make strict displayed native error **A closed day cannot be changed.** SQLite confirmed the task remained strict=0 and no session remained running. |

CUA screenshots were inspected during the session but were not saved as files; no screenshot artifacts are claimed. AX help text was observed, but actual VoiceOver speech, help tooltip readability, category focus return, status-item menu and physical notch behavior were not verified. The prior baseline's SystemUIServer timeout was not retried. No global accessibility settings were changed. The Block collapse observation warrants a controlled follow-up if long-duration submenu stability is an acceptance requirement; a single successful minute transition does not explain it.

## Preservation and cleanup

`python3 scripts/verification/non-calendar-qa.py capture before` and `capture after` produced `build/verification/non-calendar/preservation-before.json` and `preservation-after.json`. Each fingerprints all table rows in a read transaction, including WAL-visible data, and hashes the executable. Both protected databases' table fingerprints and executable hashes matched before/after and the prior raw `t3-95b0b183/build/verification/non-calendar/preservation-after.json`. Production PID 92331 retained start time `Tue Nov 3 06:22:12 2026`, expected executable and open DB. Manual PID 29492 remained absent, as in the earlier receipt; it was not restarted. No production/manual process was targeted.

The direct-launch PID 82982 was already absent. For relaunch and cleanup, PID 86098 and then PID 17143 were each checked against the exact `/private/tmp/three-406-qa-SR4XMXmc/Three 406 QA.app/Contents/MacOS/Three406QASR4XMXmc` command before SIGTERM. Final `ps` found all three absent, and exact-path `pgrep` found no candidate process. The fixture timer was stopped via `THREE_DB=... '<QA app>/Contents/Helpers/three' stop` before cleanup. Temporary app/database remain for inspection and may be removed by the OS. Raw receipts are ignored build artifacts; this document is the committed evidence.
