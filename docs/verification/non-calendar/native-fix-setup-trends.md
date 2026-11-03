# Native fix, setup, and Trends verification checkpoint

The desktop owner started from clean branch `t3/native-trends-qa` at `7e0e382eab1f4f8a3b556f685fb9615f826370a1`. This is an incomplete native verification checkpoint. No candidate app was launched and no recovery acceptance is claimed.

## Build and preparation

| Result | Check | Evidence |
| --- | --- | --- |
| PASS | `python3 scripts/verification/non-calendar-qa.py capture before` | `build/verification/non-calendar/preservation-before.json` |
| PASS | The two existing preparation guards rejected this changed source. | `integrated-native-prepare.py` reported `Candidate inputs changed`. `non-calendar-qa.py prepare` reported `Build inputs differ from the specified baseline commit`. Neither guard was modified. |
| FAIL | `CONFIG=release ./scripts/bundle.sh` | `build/verification/non-calendar/native-fix-build.log`. ThreeApp compiled, but the packaged CLI build failed with `accessing build database ... build.db: database or disk is full`. `df -h .` reported 131 MiB available and 100% capacity. No signed app bundle was produced. |
| COULD NOT RUN | Fresh signed candidate, instruction comparison, and controlled native tests | The build failure prevented safe preparation. The unexecuted scratch preparation script in `build/verification/non-calendar/native-fix-prepare.py` has not been verified and is not an acceptance artifact. |

The prior controlled trigger and screenshots remain in `/Users/divyanshudv/.t3/worktrees/adhd/t3-74a586de/.audit/menu-diagnosis`. They describe the earlier revision and do not prove the fix. A complete retry needs a successful frozen-input build, a unique signed bundle, instruction and helper hashes, separate watched and unrelated databases, and the visible timed submenu observations described in `menu-diagnosis.md`.

## Native acceptance still open

All requested native checks are **COULD NOT RUN** on this candidate. These include unrelated and same-database writes, the old global notification, three one-minute submenu observations and persisted selections, setup and shortcut conflict handling, guide and Connect, shared timer controls, Trends charts and routing, fixture parity, external refresh, relaunch, and notification delivery. No screenshot or AX observation was captured for this candidate. Native selection latency was not measured. Recovery lifecycle and decisions are not composed at this revision.

## Preservation and cleanup

`python3 scripts/verification/non-calendar-qa.py capture after` passed. The before and after table fingerprints and executable hashes match for production and Manual Test. Both also match the previous `t3-74a586de` and `t3-f5d699d2` after captures. Production PID 92331 retained its original start time, executable hash `0deae8b1f98dcdb7c739a77cefca95f67b4bc3b064cef1cfcd96dbb8141c4dcc`, and open database. Manual Test PID 29492 was absent in both captures, as at the initial baseline. Its earlier exit remains unexplained.

No QA app or fixture timer was started. The build command exited and no owned candidate process remains. No protected app or data was changed. No source or product changes were made.
