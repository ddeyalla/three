# Non-calendar integration checkpoint

Product candidate `a305ba916ddc334206530ab0303a71c5bc2c127b` combines recovery lifecycle, manual CLI/MCP decisions, and the reviewed trim-identity guard. Recovery starts before App reconciliation and updates a live reflection prompt without replacing its draft. The scheduled channel retains exactly eight tools. No release metadata changed.

## Executed combined checks

All logs below are under `build/verification/non-calendar/` in the coordinator checkout. Tests use disposable databases and Chrome directories. No installed app was launched.

| Result | Check | Evidence |
| --- | --- | --- |
| PASS | `make test` | `integrated-full-tests.log`. 216 Core, 72 App, 22 extension tests and design lint. |
| PASS | `CONFIG=release ./scripts/bundle.sh` | `integrated-release-build.log`. Local 0.2.4 build 146 bundle. |
| PASS | Strict deep codesign and plist validation | Signed local bundle and valid Info.plist. |
| PASS | Packaged MCP, History, day-close, Stats, recovery, draft-review, and scheduled-planning scripts | `integrated-release-{mcp,history,day-close,stats,recovery,draft-review,scheduled-planning}.log`. |
| FAIL | Initial packaged planning-supervisor script, run concurrently with the other scripts | `integrated-release-planning-supervisor.log`. Owner death and cancellation passed. Deadline case remained `running` beyond its existing bound. |
| PASS | Unchanged packaged planning-supervisor script in isolation | `integrated-release-planning-supervisor-isolated.log`. All four cases passed. |
| PASS | Two additional diagnostic executions of all four unchanged supervisor cases | `integrated-supervisor-diagnostic.log`. Original 2-second lifetime and assertion bounds retained. Scratch databases remain in `supervisor-diagnostic/attempt-{0,1}`. |

The initial supervisor failure remains unresolved evidence. The later isolated runs do not erase it. No timeout, assertion, or supervisor behavior changed. The initial temporary database was removed by the existing script, so its final persisted row is unavailable. The diagnostic reruns retained their databases but did not reproduce the failure. Contention and delayed process-group disappearance are hypotheses only. The final integration reviewer must inspect this path before the run reports an overall verification result.

## Release identity

`integrated-release-identity.json` records the source, plist and executable hashes.

- ThreeApp SHA-256 is `16f7e02fa0800c54f0c9628f3d10491c635a1128a75e355491a9b5f3175705be`.
- Packaged CLI SHA-256 is `88afe0fc9857f6627689e5cc1e66a8f8b11ce0d8777de1493e33c9f408a1a0ea`.

The immutable copy for further verification is `build/verification/non-calendar/frozen-a305ba9/Three.app`. It is copied with `ditto` to preserve signature metadata and independently verified before handoff.

## Remaining gates

The performance optimization is still owned by its isolated worker. A fresh independent reviewer must inspect final lifecycle and adapter integration. Terra must attempt native recovery, fixed menus, Setup and Trends against an identified release artifact. The prior inaccessible-window and SystemUIServer tool failures remain explicit. Physical sleep/lock, login startup, notification authorization, notch/Space/display behavior, and macOS 26 acceptance remain unproved.

BPRO-407's discovery verdict passed independently. That result does not close any implementation ticket. Calendar work and BPRO-396 remain excluded. No merge, release, install, production settings change, or paid model call occurred.
