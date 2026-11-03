# Non-calendar native baseline

Baseline source is `e4f91f169bacf4e4d10c4574623fa3372d16fdc0`. The checkout was clean on `t3/non-calendar-qa-baseline` before this work. Desktop QA ran on Codex `gpt-6.1-terra` with high reasoning effort. This is baseline evidence, not acceptance of the planned features.

## Fixture and artifacts

`python3 scripts/verification/non-calendar-qa.py prepare` creates a fresh temporary app, database, Chrome data directory, and a separate pre-upgrade v10 database. Run `./scripts/bundle.sh` first at the baseline commit. Preparation requires the baseline as an ancestor and rejects changes to the build inputs. It does not replace existing fixtures. Each run uses a distinct bundle identifier and executable name. The fixture contains dates in two months, an empty date, a carried source and copy, a paused focus session, a completed break, and a reflection. Existing v10 has no copy lineage field. Scheduled planning is explicitly disabled. The manifest records the dates and expected values.

The actual desktop session used `build/verification/non-calendar/native-session-manifest.json`. Its app and databases are in `/var/folders/jr/y2s2287d3zz6lhqjxr3hqp200000gn/T/three-non-calendar-qa-lgw_jihy/`. The pre-upgrade copy was made before the app opened. Temporary directories can be removed by the OS. The rerun manifest identifies another unused fixture. Raw build logs, screenshots, accessibility captures, process evidence, and database fingerprints are in `build/verification/non-calendar/`, which Git ignores.

`./scripts/bundle.sh` passed. The preparation rerun passed uniqueness checks, SQLite integrity and foreign-key checks, v10 migration identity, disabled planning, three sessions, and the empty date check. The first QA launch exited because the fixture used an invalid empty planning command. The fixture now uses `true` while planning remains disabled. The failure log and manifest remain in the raw artifacts.

## Native observations

- Today showed three fixture tasks, one done, and the paused task with its category, edit, and action controls. Resume and Pause operated on the disposable session.
- The category popover stayed open while the live timer changed from 19:55 to 18:55, and the Today focus total changed from five to six minutes. `category-live.png` and `category-after-minute.png` are reference captures.
- The task action menu exposed Schedule, Block, and Category submenus. The Block submenu opened while the timer ran. Its stability across a full minute and the Schedule submenu interaction were not tested.
- Done showed the completed fixture task. `today.png`, `done.png`, `task-menu.png`, and `block-menu.png` capture the baseline layout.
- The native app menu bar was visible in the accessibility tree. The status-item menu was not verified. `cua.getApp('com.apple.systemuiserver')` timed out.
- AppKit reported the built-in display at 1512 by 982 points with a 32-point top safe area and auxiliary top areas. Two external displays reported zero top safe area. See `displays.txt`. This records geometry, not physical notch interaction.

## Preservation and cleanup

The initial exact-PID `lsof` capture found production PID 92331 using `/Users/divyanshudv/Library/Application Support/Three/three.sqlite`. It found Manual Test PID 29492 using `/Users/divyanshudv/.t3/worktrees/adhd/t3-fe1cb47d/build/manual-testing/20261103-133256/three.sqlite`. The initial and final logical table fingerprints match for both databases. These fingerprints include WAL-visible rows and expose hashes and row counts rather than contents.

Production PID 92331 retained its original start time and executable hash `0deae8b1f98dcdb7c739a77cefca95f67b4bc3b064cef1cfcd96dbb8141c4dcc`. Manual Test's executable hash stayed `d866b61ce34b8c9c850ce589f8608022a2771901b4a12798b9b2d0ae895372a0`, but PID 29492 had exited by the final capture. Its cause and exact exit time are unknown. No stop command was sent to that PID, and it was not restarted. Process preservation for Manual Test therefore failed.

The isolated QA process was PID 15370. After checking its exact executable path, the QA owner sent SIGTERM to that PID and verified it was absent. The app and databases remain. The production and Manual Test processes were not targeted for cleanup. `preservation-before.json`, `preservation-after.json`, and `cleanup.txt` contain the evidence.

## Independent evidence correction

Sol 6.1 High independently reviewed candidate `4fb7e62` and proved that the original manifest's unscoped 1,500-second focus expectation omitted the paused session's 300 seconds. The coordinator reran its SQLite/package probe. New fixture manifests explicitly record 1,800 total focus seconds, 1,500 for reflection, 300 for paused focus, and the corresponding day totals. These expectations apply before native timer interaction. Preserved older manifests remain historical artifacts with this correction, not current acceptance oracles. The reviewer also verified all 14 audited tables, deletion behavior, session preservation, the local one-timer index, and the saved preservation evidence.
