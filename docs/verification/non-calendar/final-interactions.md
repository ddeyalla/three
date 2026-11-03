# Final non-calendar interactions checkpoint

This is a partial native QA checkpoint for BPRO-402 through BPRO-408, not an acceptance verdict. The checkout was clean at `07607eba8db66d2da81131e5e15ef1ee3f45dd40` on `t3/final-non-calendar-qa`. No product source was changed or rebuilt. Desktop interactions used Codex Terra High. Prior native results remain scoped to their reported revisions in [final-native-recovery.md](final-native-recovery.md) and [406-native.md](406-native.md).

## Artifact and isolation

The frozen release at `/Users/divyanshudv/Documents/code-deyalla/adhd/build/verification/non-calendar/frozen-07607eb/Three.app` passed `codesign --verify --deep --strict --verbose=2`. Its ThreeApp SHA-256 was `03f8fc374112b1394e7c3cb7d930300915de22aaf70908c6395343b1e8940c6e` and its CLI SHA-256 was `e2b864559d7e50a68dbeb194d692aee1751fb61834d9c8ac1393aea4ec52f8a2`.

The exact-current scratch adapter is `build/verification/non-calendar/final-interactions/prepare.py`. It retains the earlier adapter's guards, pins the current HEAD and hashes, uses `ditto`, signs the isolated copy, verifies strict signing and compares the executable's `__TEXT,__text` with the frozen input. Its manifest is `build/verification/non-calendar/final-interactions/manifest.json`. The unique bundle ID was `com.deyalla.three.finalqa.95e9309dec27`. Each launch used a scratch database and Chrome directory. Scheduled planning was disabled in the fixtures. The initial direct executable launch exited before inspection. The documented `open -n --env` alternative opened the exact copied executable with the intended database.

All raw paths in this report are relative to `/Users/divyanshudv/.t3/worktrees/adhd/t3-593df33b`. They are ignored build artifacts and remain on disk. `build/verification/non-calendar/final-interactions/` contains the manifest, adapter, logs, AX captures, screenshot, selection receipts and preservation captures. The fixture bundle and databases remain in `build/verification/non-calendar/final-95e9309dec27/`.

## Results at 07607eb

| Check | Result and evidence |
| --- | --- |
| Trends fixture and values | **PASS, native and headless.** `python3 scripts/test-stats.py --binary <QA helper> --fixture-db <scratch>/stats.sqlite` passed five fixed statistics, CLI/MCP/History parity and null ratios. Native AX showed 60 minutes, 8.6 minute average, 50% completion, 66.7% actual/planned, 50% focused-rated, 3 hits and 1 unblock per focus hour, and one-day streak. `@Three` showed 30 minutes and 6 hits per hour. `stats.log`, `trends.ax.txt` and `trends-disclosure.ax.txt` contain the evidence. |
| Trends axis | **PASS, wide daily chart.** `trends-wide.png` shows distinct `10-07`, `10-14`, `10-21`, `10-28` and `11-03` labels. AX marks and expanded daily disclosure retain full dates and fixture values. The native sparse weekly completion data shows undefined zero-denominator weeks in AX. This does not verify visual positioning of every chart or an empty fixture. |
| Trends narrow | **COULD NOT RUN.** Two attempts to drag the observed window edge did not resize the window. No narrow screenshot or narrow verdict is claimed. |
| History | **PASS, scoped native and headless.** The retained `test-history.py` fixture passed CLI/MCP parity and fixed accounting in `history.log`. Command-6 opened History and Command-4 opened Done. Previous and next arrows changed October to November with 20m and 10m focused respectively. November 2 displayed the empty-day explanation. November 1 showed the 10m session, 5m break and reflection. A packaged CLI `add` of `History external refresh` to November 1 updated the visible detail and month total from 30m to 55m without relaunch. The 55m total remained after an exact QA restart. `history-empty.ax.txt` and `history-refresh.ax.txt` retain observations. |
| Strict action | **PASS, scoped native and protocol.** During active focus, the task menu's `m` key selected Make strict and Return applied it. The task displayed strict metadata and the reopened menu showed disabled Strict with one-way help. The packaged CLI and MCP reported strict and the native state persisted after exact QA restart. `strict.ax.txt`, `strict-cli.json` and `strict-mcp.json` retain evidence. |
| Category, Block and Schedule | **PASS, native selection and persistence.** Down and Return selected Admin on the companion task. The Block and Schedule menus selected 45m and Tomorrow. `selections.json` read the disposable database as Admin, 45 minutes and 2026-11-04. This does not establish focus return after the category popover. |
| Day review | **PASS, active-focus deferral.** The native Day review showed `This day will close after its focus block ends.` `day-focus.ax.txt` records it. Other day-close cases below remain open. |
| Notch Open Three | **PASS, native.** On the supported built-in display, the QA-only notch switch was enabled, Show Controls opened the panel, and Open Three returned to the main window. The switch was restored off. Tab then Space did not produce an observable action and the AX focused element remained the dialog. This observation does not identify whether focus navigation or automation delivery caused it. |
| Alternate shortcut | **INCONCLUSIVE.** The QA app reported Control-Option-Z registered. A Finder-injected chord did not expose a popover in the app AX tree. `shortcut-windows.txt` is the public CoreGraphics inventory taken afterward and does not show an onscreen shortcut popover. No before inventory was retained, so this does not establish a window transition. The QA shortcut was restored to its original Option-Command-Space configuration, which reported its prior conflict. No SystemUIServer request was repeated. |

The wide screenshot was inspected directly. Prove It Works guided the use of the frozen signed app, native controls, packaged adapters and persisted fixture rows. Emil design engineering guided inspection of readable labels and accessible full-date detail.

## Remaining gates

The following are **not attempted in this checkpoint**, not claimed as tool failures. They remain ready for a subsequent exclusive desktop owner:

- History date-picker entry, narrow/back layout, keyboard day selection and error/retry, plus larger-fixture native navigation timing. No speedup claim is made.
- Trends visual inspection of all five charts at wide and narrow sizes and a native empty chart fixture.
- Day-close Go menu entry, quiet summary after relaunch, reflection and recovery deferral, full-destination error, and source-history retention after accept and dismiss.
- A new reflection deadline after external Trim, draft retention through that deadline, and one fresh action. The earlier seeded draft/Trim proof remains at `a305ba9`.
- Notch Shift-Tab and Space activation with observable focus, next-session behavior, automatic presentation without stealing another app's typing focus, and app-only fullscreen or Space behavior. The current Tab/Space attempt was inconclusive.

Physical sleep and lock were excluded by the handoff. External-display disconnection, real permissions, login startup and macOS 26 remain separate hardware or authorization gates. Stale recovery action rejection is already covered headlessly; a stale native gesture was not fabricated. The shortcut attempt did not isolate a product defect from input or observation limitations.

## Preservation and cleanup

The before capture matched the earlier `t3-e9782d2c` final after capture for protected executable hashes and every SQLite table fingerprint. The fresh before and final after captures also match. Fingerprints use read-only transactions and include WAL-visible rows. Production PID 92331 retained start time `Tue Nov 3 06:22:12 2026`, its executable and open database. Manual Test executable and database fingerprints match; PID 29492 was already absent and was not restarted. Its process preservation is not claimed.

The scratch timer had no open session at cleanup. The packaged `stop` command returned `Nothing running.` Every QA PID was checked against the exact copied executable before termination. Final exact-name `pgrep` found no QA process. No production or Manual Test process was targeted. No installation, release, push, ticket update, production settings change, physical sleep or paid call occurred.
