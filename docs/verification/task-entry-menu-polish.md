# Task entry and menu follow-up

The user reported a flickering Planning Test button and nested task menus that flash, move, or disappear before selection. They also requested category selection before task creation. This follow-up changes the native app only. It does not change Store migrations, the public CLI or MCP contracts, VERSION, or CHANGELOG.

## Source and design

Worktree is `/Users/divyanshudv/.t3/worktrees/adhd/t3-fe1cb47d`, branch `t3/scheduled-planning-runner`. Starting HEAD was `f18c657b0511d099ca9917ea58467a11c27caeaf`. Work ran in-thread with no children.

- `add3ef7` records the failing regression for idle Planning checks.
- `ba8b224` keeps background admission separate from visible command execution. Manual Test requests that arrive during an idle poll wait for that poll. Cancel clears the queued request. Existing durable claims still prevent overlapping commands.
- `aa50799` adds category selection to the existing QuickAddField and moves the live task duration into a separate view.
- `b49942f` moves the live day summary into its own view. PaneList accepts a subtitle view and retains its existing String convenience initializers.

Two task-entry designs were compared. Extending QuickAddField preserves one parser and one Store write path across Today, Inbox, Upcoming, and the menu bar. A separate creation sheet would duplicate the entry flow. The shared picker was chosen. Its local choice is associated with the current inline category token, so a later typed `#category` changes the effective category. A later picker choice overrides the current token. The preview and capture use the same resolved category. Successful creation clears the choice. Validation failure keeps the draft.

For menus, the timer remains on the existing app tick. The original TodayTaskCard read `model.now` when constructing its trailing duration, rebuilding the card that owned both the right-click and ellipsis menus. TaskDurationLabel now owns that observation. A subsequent real-focus check exposed the remaining day-summary refresh path. TodaySummary now owns that clock observation, so a changed focus total does not recreate the task list. Freezing the app clock or replacing native menus would change unrelated behavior and was rejected.

## Reproduction and verification

Artifacts are under `build/ui-polish/` in the worktree. Temporary diagnostic logging was removed before the final build.

The new Planning regression failed on the original implementation:

```text
Expectation failed: !busyWhenDisabled
Expectation failed: !busyBeforePlanningTime
Test run with 1 test in 1 suite failed ... with 2 issues.
```

The seven focused Planning app tests then passed. They include idle checks, a manual request during admission, cancellation of a queued request, output, settings, startup cancellation, and shutdown cleanup.

A native scratch SQLite write lock made the original false busy state observable with scheduling off and no command running. The original view disabled Test and inserted Cancel. The corrected view kept Test enabled and did not insert Cancel under the same condition. Database lock errors remained visible. The lock was released and its process exited.

Temporary native tracing recorded both original Today cards rebuilding each second while a submenu was open. After duration isolation, the trace contained the initial two card builds at `14:04:39.778` and no further card builds until a real task creation at `14:05:35.107`. The live duration and timer continue to read the app clock.

Native entry checks created and persisted:

| Action | Saved result |
| --- | --- |
| Choose Writing before typing a Today task | `QA selected before creation`, Writing, 30 minutes, today |
| Type `#admin`, then choose Learning before Inbox submission | `QA inline category`, Learning, 15 minutes, Inbox, with its tag |
| Choose Writing before Upcoming submission | `QA future category`, Writing, 20 minutes, tomorrow |
| Leave Category open, then choose Writing | The selected task changed category |
| Choose 45m through Block | The selected task changed to 45 minutes |
| Choose Tomorrow through Schedule | The selected task moved to tomorrow |

These values are also recorded in `native-results.json`. The menu-bar field uses the same QuickAddField implementation. Native status-item interaction was not accepted as part of this follow-up.

The first release bundle was also exercised using the unique `com.deyalla.three.uifinal` scratch app. Its real-focus check exposed the remaining summary-refresh path before final acceptance. The final verification uses another unique app identity after that correction. Earlier diagnostic copies shared a QA bundle identifier, which made a later automation target ambiguous. Those processes were stopped. Their ambiguous interaction errors are not counted as product failures or final acceptance. The unique final app uses its own database and Chrome folder.

The corrected build 97 used `com.deyalla.three.uiverified`. With a real focus session running, Schedule stayed open as the visible day total advanced from 6m to 7m and the countdown changed from 17:52 to 17:02. Selecting Tomorrow then persisted the chosen task on `2026-11-04`. Block and Category selections also persisted 45 minutes and Writing. `verified-native/results.json` records those final assertions. The scratch timer was paused for the remaining selections and stopped before cleanup.

## Automated and packaged checks

| Check | Result | Artifact |
| --- | --- | --- |
| `make test` | PASS, 134 Core, 29 App, and 22 extension tests. No extension skips. | `summary-make-test.log` |
| `CONFIG=release ./scripts/bundle.sh` | PASS, 0.2.4 build 97. | `verified-bundle.log` |
| `codesign --verify --deep --strict build/Three.app` | PASS. | Command output was empty with exit zero. |
| Real packaged MCP protocol fixture | PASS, schemas, resources, malformed requests, shared Store, persistence, and races. | `final-mcp.log` |
| Relocated scheduled planning fixture | PASS, restricted real MCP draft path and packaged guidance. | `verified-scheduled.log` |
| Real planning supervisor fixture | PASS, owner death, cancellation, deadline, owned descendants, and terminal results. | `final-supervisor.log` |

## Manual test copy and limits

The user's existing Three Manual Test bundle was updated to the signed release artifact. Its original scratch database, Chrome path, and settings were preserved. The database fingerprints matched before and after the bundle replacement. `updated-manual.json` records the input hash, source commit, and data-preservation receipt. A SQLite backup and the previous test bundle are retained under `build/ui-polish/`.

Production Three remains separate. No installation, production restart, push, tag, release, browser-profile change, or authenticated model generation is part of this follow-up. The Mac runs 27.0.1. BPRO-396 remains In Progress because macOS 26 runtime acceptance and its other reported gates remain open. These focused fixes do not establish a stable release or a full accessibility acceptance result.
