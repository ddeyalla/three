# Trends collision policy native verification

The candidate at `cb68bd82af9b303bc5862f4d0242a0287479e422` displays whole daily date labels at the tested widths and retains the fixture's accounting. At 600, 680, and 1060 points, both endpoint labels disappear. The page header supplies the full range, but the chart alone does not identify its endpoints. This is a visual limitation, not a missing numerical value. This receipt covers only the Trends axis correction.

| Before | After | Why |
| --- | --- | --- |
| At `07607eb`, daily labels showed `1...` at 680 points and `10-...` at 1060 points, as recorded in [the prior native receipt](readviews-native.md). | At `cb68bd8`, the displayed daily labels are whole at 600, 680, 1060, and 1240 points. At the first three widths the endpoint labels are absent. At 1240 all five appear. | Whole labels resolve the recorded truncation. The full range remains in the page header, but the narrow chart alone leaves its bounds ambiguous. |

## Identity and isolation

PASS. The initial worktree was clean on branch `t3/verify-trends-date-axis`, with HEAD and product source `cb68bd82af9b303bc5862f4d0242a0287479e422`. The frozen source was `/Users/divyanshudv/Documents/code-deyalla/adhd/build/verification/non-calendar/frozen-cb68bd8/Three.app`. Its adjacent identity identifies that source. Strict deep signature verification passed. SHA-256 values for `Contents/MacOS/ThreeApp` and `Contents/Helpers/three` were respectively `00e5ea3483dbf10107f3522e3f428f7ac26cb990a86607ed3e4c75a3aa635ff2` and `e2b864559d7e50a68dbeb194d692aee1751fb61834d9c8ac1393aea4ec52f8a2`.

PASS. The guarded preparation script used `ditto`, changed the bundle ID and executable name, re-signed the copy, verified its strict deep signature, and compared executable `__TEXT,__text` with the frozen source. The matching text hash was `49331038573c96638851ca4fb982dfa2b9422324498c29347f3e725981963262`. The copy was `final-7fa641595269/Three Final QA.app`, bundle ID `com.deyalla.three.finalqa.7fa641595269`, executable `ThreeFinalQA7fa641595269`. The frozen production-ID app was not launched. No rebuild was made.

PASS. `open -n` launched the copied app with explicit disposable `THREE_DB` and `THREE_CHROME_DATA`. PID 31816 opened `stats.sqlite`; PID 45480 opened `other.sqlite`. The `launch-lsof.txt` and `empty-lsof.txt` files identify each executable and its database, WAL, and SHM. Scheduled planning was disabled in both databases. The new Chrome directory belongs to the QA copy.

## Fixture and native charts

PASS. `python3 scripts/test-stats.py --binary <QA helper> --fixture-db <new stats.sqlite>` returned `PASS five fixed statistics, commitment denominators, overlapping tags, break choices, CLI/MCP/History parity, null ratios, range validation and read-only storage`. The exact output is `stats-output.txt`. Native AX agreed on 60 minutes focus, 50% completion, 66.7% actual to committed planned time, 50% focused-rated share with one unrated session, three hits and one unblock per focus hour, and a one-day streak ending November 2. AX identifies November 2 as the 60-minute bar and 66.7% point. The weekly text identifies the earlier zero-denominator periods as undefined, and the screenshots show the single defined weekly marks in chronological position. The ratio chart shows a single point and no invented values in the missing dates.

PASS for displayed label legibility. Public AX window sizing returned status 0 and actual sizes of `600 x 800`, `680 x 800`, `1060 x 800`, and `1240 x 800` points. Both daily charts were inspected at each width. Their displayed dates have no visible truncation, overlap, or clipping. At the first three widths, only `10-14`, `10-21`, and `10-28` appear on the daily axes. At 1240, `10-07` and `11-03` also appear. The header states `2026-10-07 to 2026-11-03` at every width. The missing endpoints make the chart bounds ambiguous when the chart is viewed without the header. `resize-*.txt` records actual geometry, and `trends-<width>-top.png` and `trends-<width>-middle.png` record both daily axes.

PASS. The three weekly chart axes at 600 and 1240 points display complete, ordered labels `10-05`, `10-12`, `10-19`, `10-26`, and `11-02`. The weekly completion and quality bars and the distraction markers appear at the last week. The middle and bottom screenshots retain these observations.

PASS. Selecting `@Three` produced 30 minutes focus, 100% completion, 100% actual to planned, 100% focused-rated share, six hits and two unblocks per focus hour. `trends-tag-ax.txt` records the selected value and full dates.

PASS. A newly initialized empty fixture at actual `600 x 800` displayed zero focus and streak, undefined completion and accuracy, no ratings, and undefined distraction rates. `trends-empty-600.png`, `trends-empty-ax.txt`, and `resize-empty.txt` retain the result. The first resize while the workspace was open settled at 1060 points; after opening Trends, the same AX method reached 600 points.

## Preservation and cleanup

PASS. Fresh WAL-aware before and after table fingerprints and executable hashes match each other and the prior `readviews-native/preservation-after.json` for both protected databases and executables. Production PID 92331 retained its `Tue Nov 3 06:22:12 2026` start time and open database. Manual PID 29492 was absent before and after; process preservation is not claimed. The two QA databases had no unended sessions, so no timer needed stopping. The exact QA PIDs were stopped and `pgrep` found no matching executable afterward.

Raw artifacts are in `/Users/divyanshudv/.t3/worktrees/adhd/t3-48c2fd7b/build/verification/non-calendar/trends-collision-native/`. This result does not close source review, other tickets, or broader release acceptance.
