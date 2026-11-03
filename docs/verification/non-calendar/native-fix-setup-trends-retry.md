# Native fix, setup, and trends retry

This is an incomplete debug-native verification of product source `7e0e382eab1f4f8a3b556f685fb9615f826370a1`. The worktree began clean at `35e9da278d31311db18006371dbe6988ef274b2d` on `t3/noncalendar-desktop-qa-retry`. No release or recovery acceptance is claimed.

## Frozen input and fixture

The source was `/Users/divyanshudv/Documents/code-deyalla/adhd/build/Three.app`. Before copying, `codesign --verify --deep --strict` passed. SHA-256 for `Contents/MacOS/ThreeApp` was `41095bbf08ac0d5e1a80ff213acf6b8b931f2ed401b60f103ff0881f783e1f73`. SHA-256 for `Contents/Helpers/three` was `5123937f55ab4c2bc21c73896c3fd186644372e36f80f8da4c73f408cfde778d`. Both copied hashes matched before signing. The original was not launched or modified.

`scripts/verification/native-fix-retry-prepare.py` repeats those checks, creates a unique bundle identity, signs the copy, compares Mach-O text, and seeds separate watched and unrelated databases. It does not bypass the older helpers' guards. The retained manifest, bundle, databases, and logs are at `build/verification/non-calendar/retry-46527c3f2f6c/`. The copied executable's signed SHA-256 is `c933ff8ae50580adc6d10394749b37be28774792113d96276ed6df383da2e385`. The app's text section SHA-256 is `7f8baaae41b615caee98dccc16f9472443ed466b25af044bf6fab583c34f448d`.

## Results

| Check | Result | Evidence and limit |
| --- | --- | --- |
| Isolated process and watched database | PASS | PID 67574 ran the exact QA executable and `lsof` showed the watched database, WAL, and SHM. It was stopped by exact path. The subsequent QA PID was 75446. |
| Native window | COULD NOT RUN | `cua.getApp` for the QA bundle returned `Computer Use server error -10005: cgWindowNotFound`, including after `open -a` on the copy. Finder accessibility worked. This observation does not establish why the QA window was unavailable. |
| Status item and alternate shortcut | COULD NOT RUN | `cua.getApp('com.apple.systemuiserver')` returned `timeoutReached` after five seconds. As a fallback, the unique QA defaults were set to Control-Option-Shift-Command-Z and the app was relaunched. Sending that key from Finder did not produce an accessible QA window. Registration and uniqueness were not observed, so no shortcut or status-item pass is claimed. The production shortcut was not changed or invoked. |
| Menu diagnosis | COULD NOT RUN | No accessible window or visible submenu was available. Unrelated and watched writes, each full-minute observation, selection persistence, and legacy notification behavior remain open. No candidate screenshots or AX evidence were captured. |
| Setup | COULD NOT RUN | Conflict messaging, guide, Connect, status-item count, shared timer controls, reflection, keyboard and focus, relaunch persistence, permissions, and notification delivery remain open. No QA login item was registered. |
| Statistics protocol fixture | PASS | `python3 scripts/test-stats.py --binary <QA bundle>/Contents/Helpers/three --fixture-db <new fixture>` passed twice. The second output is `stats-rerun.log`. It reports five fixed statistics, commitment denominators, overlapping tags, break choices, CLI/MCP/History parity, null ratios, range validation, and read-only storage. The retained range is 2026-10-28 through 2026-11-03, with 3600 focus seconds. This is not native chart acceptance. |
| Trends, History, Day Review, notch, latency | COULD NOT RUN | The requested native views, navigation, external refresh, focus checks, and selection latency were not observed. Physical sleep, macOS 26, external-display fallback, and Spaces remain open. No speedup is claimed. |

## Preservation and cleanup

`scripts/verification/non-calendar-qa.py capture before` and `capture after` recorded WAL-aware table fingerprints and executable hashes. Production table fingerprints and executable hash matched. PID 92331 retained its original start time and open production database. Manual Test table fingerprints and executable hash matched. PID 29492 was absent before and after; its earlier exit remains unexplained and process preservation did not pass.

Both QA processes were stopped after verifying their exact executable path. The final `pgrep -fl 'ThreeRetryQA46527c3f2f6c'` returned no process. No fixture timer was started. The fixture, signed app, and manifest remain in place. No production install, release, calendar action, or product source change occurred.

The next desktop pass needs a working way to expose the unique QA app window and status item. It must run the three one-minute menu observations and the setup and Trends checks on the frozen candidate, then repeat recovery acceptance after the separate lifecycle integration.
