# History and Trends native acceptance at 07607eb

Run on 2026-11-03 in `/Users/divyanshudv/.t3/worktrees/adhd/t3-a0720c7c`, branch `t3/a0720c7c`, initial HEAD `02685b67dc346f1a447a9278a98d87c09fec171a`. Initial tracked and untracked status was clean. This report covers only the assigned History and Trends checks, not overall delivery acceptance.

Raw screenshots, AX trees, fixtures, launch receipts, resize helper and preservation captures are retained in `/Users/divyanshudv/.t3/worktrees/adhd/t3-a0720c7c/build/verification/non-calendar/readviews-native/`. These local build artifacts are not committed.

## Identity and preservation

PASS. The frozen source identity identifies `07607eba8db66d2da81131e5e15ef1ee3f45dd40`. Its app executable SHA256 is `03f8fc374112b1394e7c3cb7d930300915de22aaf70908c6395343b1e8940c6e` and helper SHA256 is `e2b864559d7e50a68dbeb194d692aee1751fb61834d9c8ac1393aea4ec52f8a2`. Both the frozen source and reused isolated QA bundle pass `codesign --verify --deep --strict`. The QA executable and helper hashes match the assigned values, and `otool -s __TEXT __text` matches the source with text hash `15337f1c90f212ea8fd5a5727aa6ff3477d0d7cd20080aa46e8e535d286eca58`. The source app was never launched.

PASS. Fresh WAL-aware before and after table fingerprints and executable hashes match the previous owner's `final-interactions/preservation-after.json` for production and manual databases. Production PID 92331 retains its stated start time, executable and open database. Manual PID 29492 was already absent and remained absent. Manual process preservation is not claimed. Four isolated launches used new databases and a new Chrome directory. `launch-*-lsof.txt` records the actual executable and database for each. Scheduled planning was disabled in each launch database. No fixture session was running at cleanup. The exact-path QA process was stopped and no matching process remained.

## History

- PASS. `scripts/test-history.py`'s `run` function ran with the packaged helper and a new retained scratch directory. It checked fixed records and CLI/MCP parity, including 1,800 seconds focus, 300 seconds break and 4,500 seconds planned. The retained fixture is `history/history.sqlite`.
- PASS. Public AX window-size mutation returned status 0 and actual `680 x 800` points, after `1240 x 800`. `resize.txt` and `history-wide.png` and `history-narrow.png` record the result. AX trust was checked without a prompt.
- PASS. The native date picker accepted `31/10/2026` and changed November to October. The October summary displayed 20 minutes focus and 45 minutes planned. The selected October 31 detail showed the carried task, archived category, 20-minute session and 10-minute pause. Narrow list to detail, Days in Month, Today and Done worked. `history-recorded-ax.txt` and `history-recorded.png` retain the selected detail. The prior pass in `final-interactions.md` supplies the separately passed previous/next, empty-day, reflection and external-refresh evidence.
- COULD NOT RUN. Keyboard-only day selection was attempted with Tab and Space after focusing the picker. The focused AX element remained the date picker and the day did not change. An AX click selected a day as an alternative and proved detail, but does not establish keyboard-only access. Retest focus traversal with a reliable keyboard-access configuration and inspect focus before activating the day. No global setting was changed.

## Trends

- PASS. `python3 scripts/test-stats.py --binary <QA helper> --fixture-db <new stats.sqlite>` checked the fixed fixture against packaged CLI and MCP. The native AX tree agrees on 60 minutes focus, 50% completion, 66.7% actual/committed, 50% focused-rated share with one unrated, three hits and one unblock per focus hour, and a one-day streak ending November 2. The native `@Three` choice and Return produced 30 minutes focus, 100% completion and six hits per focus hour. `trends-retry-ax.txt` retains selected-tag results. The tag menu and provenance disclosure were exercised. Return applied the menu selection; broader keyboard navigation remains unproven.
- PASS with the visual defect below. All five charts were inspected and saved at actual `1240 x 800` and `680 x 800` points. `trends-1240-*.png` and `trends-680-*.png` show the chart positions and values. The single defined weekly completion and quality bars appear at November 2; the distraction markers appear at three and one on that week. The page range is year-qualified. Undefined weekly values are listed explicitly.
- PASS. A newly initialized empty database displayed zero recorded focus, zero streak, undefined completion, accuracy and distraction rates, and no recorded ratings. `trends-empty-ax.txt` and `trends-empty.png` retain the native state.

| Before | After | Why |
| --- | --- | --- |
| At 680 points the daily focus and actual/planned x-axis dates render as `1...`. At 1060 points the daily axis showed `10-...`. | Keep each displayed date legible at supported widths. | The date of a plotted value cannot be read from the chart axis. At 1240 points the same fixture displays full `MM-DD` labels. Reproduce with `trends-680-top.png`, `trends-680-0.4.png`, `trends-narrow-0.png`, and `trends-1240-0.png`. |

This is a verified visual failure at the immutable release, not a product fix. The charts' accessibility labels and disclosures contain dates, but do not make the visual axis legible.

## Load errors and retry

PASS. History reads `session` inside `historyReport`; Trends reads the same history and `blockEvent` inside `stats`. Both views set failed state on a thrown read and increment their refresh key for Try Again. Healthy SQLite backups were captured before faults. On only the disposable History fixture, `ALTER TABLE session RENAME TO qa_fault_session` followed by Refresh produced the native missing-table error. `ALTER TABLE qa_fault_session RENAME TO session`, then Try Again, restored October 31 detail and the 20-minute value without relaunch. On only the disposable Stats fixture, the same procedure renamed `blockEvent` to `qa_fault_blockEvent` and back. Try Again restored the selected tag's values without relaunch. Both restored databases passed `PRAGMA integrity_check` and `foreign_key_check`. The app also briefly displayed a separate snapshot error notice from the induced Stats fault; it was dismissed after restoration. Error and recovery AX captures are retained as `history-error-ax.txt`, `history-retry-ax.txt`, `trends-error-ax.txt`, and `trends-retry-ax.txt`.

## Larger fixture

COULD NOT RUN. SQLite backup copied the original to `large-prelaunch.sqlite` and then `large.sqlite`; the original was not modified. The source had 4,758 sessions, integrity check `ok`, and no planning preference. The launch copy explicitly disabled planning. The packaged QA PID 89594 and its open copied database are recorded in `launch-large-lsof.txt`. Load average was 3.66, 3.67, 3.39 on 12 logical CPUs. The native workspace appeared, but a direct History button click returned `elementHasNoFrame`. A fresh AX state and screenshot each returned `timeoutReached`. This prevented a safe Trends navigation attempt as well as direct observation of month selection, opening, or refresh. No timing bound, latency, or speedup is claimed. A responsive native automation surface is required to repeat both paths against this same retained prelaunch copy.

Prove It Works guided direct native observation and kept packaged parity separate from UI acceptance. Explain the Number and the benchmark checklist prevented a latency claim when the native result could not be observed.
