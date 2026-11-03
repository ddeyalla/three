# Native submenu diagnosis

Candidate `e033b4fd5321918451fb165a6d2deb8f98fb52f6` has product inputs matching `d4cd2567449c14d591d9c713cf88e7133f9ebf7d`. The checkout was clean before instrumentation. This is diagnosis, not a product fix. Times below are 2026-11-03 in Asia/Kolkata.

## Findings

**PROVED: an unrelated database write can collapse a native submenu.** In an instrumented debug copy, a 60-minute session ran on Active focus while the companion task's Block submenu was open. The 16:50:40 screenshot shows the submenu. A packaged CLI `capture` against a different disposable database ran at 16:50:48.185-48.251. The watched database's table fingerprints matched before and after. At 16:50:48.245 the app logged a ChangeSignal callback, at 48.246 a reload, and at 48.265-48.267 a TodayList and both task-card body evaluations. The 16:50:54 screenshot shows the parent menu still open and Block absent. The displayed focus total did not cross a minute in this interval. This establishes a reproducible trigger and correlated reload path, not that every collapse has this cause or the exact internal AppKit operation.

A second Category check had the same callback, reload, card evaluations and collapsed screenshot after an external write at 16:51:23.181-23.273. Its before screenshot at 16:51:12 and after screenshot at 16:51:30 also straddle a focus-minute change, so it is corroboration rather than an independently isolated cause. The watched database fingerprints again matched. After 16:51:30, a burst of unsolicited global callbacks occurred. Their sender is unknown.

**INCONCLUSIVE: the original 3270869 collapses' exact cause.** Their screenshots show the submenus disappearing while the parent stayed open. They contain no callback trace, so they cannot identify whether unrelated writes triggered those particular collapses.

**INCONCLUSIVE: the unisolated clock-only observation.** Schedule was visible at 16:52:01 and absent at 16:53:26. A scheduled close check at 16:52:53.881 logged `closed=false` without a reload then. From 16:53:11, unsolicited callbacks and reloads contaminated the interval. The exact visual collapse time is unknown.

**REFUTED for this observed interval: an unchanged minute check or advancing focus total necessarily collapses Schedule.** A second diagnostic build changed the notification name for both posting and observing to the unique `com.deyalla.three.diagnostic.fb0b0e512b9f`. This is an experiment, not a proposed product fix. With a new database and a 60-minute session, Schedule remained visible in screenshots at 16:55:01 and 16:56:19. The timer advanced from 59:37 to 58:19 and the focus total changed to one minute. The 16:55:38.972 close check logged `closed=false`; there were no callback, reload, or TodayList or card body logs between the screenshots. This does not rule out a different clock-related cause under other conditions.

## Native check results

| Check | Result |
| --- | --- |
| Controlled Block external write | FAIL for menu stability. The submenu collapsed after the unrelated write. The watched database was unchanged. |
| Controlled Category external write | FAIL for menu stability. The submenu collapsed, but the focus-minute change confounds timing. |
| Unisolated Schedule minute observation | COULD NOT RUN as a clean clock-only comparison. Incidental callbacks occurred. |
| Isolated-notification Schedule minute observation | PASS for the observed 78-second interval. Schedule stayed visible across a close check and focus-minute change. |
| Original 3270869 cause | COULD NOT RUN retrospectively. The prior run has no callback trace. |

## Source and diagnostic identity

`Sources/ThreeCore/Operations.swift` names one global Darwin notification for all Stores and posts it after `Store.write`. `Sources/ThreeApp/AppModel.swift` subscribes without a database identity and reloads the snapshot on every callback. The same file reloads after a minute check only when a day actually closes. `Sources/ThreeCore/DayClose.swift` posts on a close only when `didClose` is true. `TodaySummary` and `TaskDurationLabel` own the clock reads in `Sources/ThreeApp/TodayView.swift`. The trace demonstrates the callback, reload and card evaluations, but does not isolate which SwiftUI assignment or AppKit menu operation closes the submenu.

The baseline debug copy had bundle ID `com.deyalla.three.menudiagnosis.fb0b0e512b9f` and PID 50001. Its signed executable SHA-256 was `2b79bb99c01b05a8e98dd2df382feb4c860bb6df47c13bdbdd626615bdf3ea7c`; the original built executable was `188eac30284e89e2dafa837f20d17476d43e082483e2bef4ececf613713019d0`. Their instruction digest matched at `660428d306cd9e3c48d731d31092d336235998b4428a2ad9af5ec70e3d003884`. The temporary logging patch SHA-256 was `a54f3f1d96353d28564d01596b0a239d6a2f32e27bcedf2b1dc3fcac67bd17f3`.

A scratch helper checked the candidate and product input diff, the exact instrumentation patch, the signed bundle, and matching instructions. It created distinct databases and Chrome directories, and disabled scheduled planning. The existing `integrated-native-prepare.py` guard rejected the current changed inputs and was not modified. A separate committed-input comparison also shows candidate inputs differ from its pinned `3270869` source. The scratch artifacts, manifests, exact patches, screenshots, build logs, CLI output, table fingerprints, and timestamped app logs are retained in `.audit/menu-diagnosis/` in this worktree. AX alone is not proof of menu visibility.

The isolated variant used bundle ID `com.deyalla.three.menudiagnosis.d6f3abd46ce5` and PID 65532. Its signed executable SHA-256 was `e20a86765c7537d843795d8b79bfcee0712c31a93ca9f5331561dd6e0b937373`, built executable SHA-256 was `213a961d55746a104606216df727d5962ca8f4e7ee5a1dd630148f5047d7d698`, and matching instruction digest was `b79f0142a71765ce2290b8db67400707df704b266ea050d3d60089e4c2241bb6`. Its patch SHA-256 was `f8a497bc9b9143c34974a1ff04827562acec7e05ccd7e5474411c822c6e618c0`. Both temporary source patches were removed before this report.

## Preservation and cleanup

Before and after captures used `python3 scripts/verification/non-calendar-qa.py capture before` and `capture after`. Both protected databases' table fingerprints and executable hashes matched across this run and the prior `t3-f5d699d2` and `t3-a2ae7e58` after captures. Installed Three PID 92331 retained its original start time and open database. Manual Test PID 29492 was absent before and after; its earlier exit remains unexplained. Each fixture timer stopped through its own packaged CLI. Both QA PIDs were terminated after exact executable-path checks, and subsequent `ps` and exact-path `pgrep` found neither process. No product source changes or installation were made.

The next owner can use the controlled trigger to test a fix. A durable fix must also preserve updates from legitimate writes to the watched database. This experiment does not validate a proposed implementation, native menu stability after a fix, or the source of the incidental notification bursts.
