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

At this checkpoint the performance optimization was still owned by its isolated worker. A fresh independent reviewer is inspecting lifecycle and adapter integration at `288b064`. Terra is attempting native recovery, fixed menus, Setup and Trends against the frozen `a305ba9` release artifact. The prior inaccessible-window and SystemUIServer tool failures remain explicit. Physical sleep/lock, login startup, notification authorization, notch/Space/display behavior, and macOS 26 acceptance remain unproved.

BPRO-407's discovery verdict passed independently. That result does not close any implementation ticket. Calendar work and BPRO-396 remain excluded. No merge, release, install, production settings change, or paid model call occurred.

## Event-date reuse integration

Worker commit `e043c9bfe4e855b4b7c6517cab917179615acff5` was imported as `dbba9ae`. Its product change only reuses History's request-scoped session civil dates for linked block events. Unlinked events retain occurrence-date conversion. The moved-commitment fix remains in its ancestry. No other product file changes in this unit.

The coordinator inspected the product and measurement-driver diffs, History's grouping owner, and the retained comparison receipts. All 144 warmup/measured responses have matching per-case output hashes. Each side has one warmup and five measured samples per path and case. Error counts are zero, storage receipts match, all cleanup exit receipts are zero, and 32 additional date responses passed. The worker's performance conclusion remains scoped to its matched v12 artifacts and fixture, as described in [the report](read-performance.md#v12-event-date-reuse-comparison). The maximum-window comparison remains inconclusive. No new timing or native rendering claim comes from integration.

Executed again against the combined product at `dbba9ae`:

| Result | Check | Evidence under `build/verification/non-calendar/` |
| --- | --- | --- |
| PASS | `make test` | `perf-integrated-full-tests.log`. 216 Core, 72 App, 22 extension tests and design lint. |
| PASS | Release bundle, strict deep signing, plist | `perf-integrated-release-build.log`, valid 0.2.4 build 146 bundle. |
| PASS | Packaged Stats, History and recovery scripts | `perf-integrated-{stats,history,recovery}.log`. Includes Keep/Trim report parity and concurrent decisions. |
| PASS | Baseline-versus-integrated event attribution | `perf-integrated-dates.log` and `perf-integrated-dates/date-checks.json`. Thirty-two CLI/MCP responses cover Cairo transitions, Apia's skipped date, and Los Angeles midnight with unchanged fixture storage. |
| PASS | Python driver parsing and Git whitespace | No source compilation or whitespace error. |

The new immutable release copy is `build/verification/non-calendar/frozen-dbba9ae/Three.app`. `perf-integrated-release-identity.json` binds it to the integrated source. ThreeApp SHA-256 is `d3ff4c1322fdaf02f3614c96e030b0107067cebb800289aff38ee9af8ee01d56`; CLI SHA-256 is `e2b864559d7e50a68dbeb194d692aee1751fb61834d9c8ac1393aea4ec52f8a2`. The copy's hashes match and strict signing passes.

The currently running reviewer and Terra retain their original frozen inputs. Their results cannot be relabelled as verification of this later product change. A fresh bounded review of event-date reuse remains required after the sole reviewer slot is free. The original supervisor failure above remains recorded; these checks did not rerun it or establish its cause.

## Independent recovery and lifecycle verdict

A fresh Codex Sol 6.1 High reviewer passed the scoped `75fc9aa` and `a305ba9` review at `288b064`. The coordinator read its report at `/Users/divyanshudv/.t3/worktrees/adhd/t3-334c5383/.audit/recovery-lifecycle-review/report.md`. No new verified correctness finding or product correction was requested.

The reviewer independently compiled the current Core and 34 App sources without the UI entry point. Forty-one focused tests passed, including a real packaged-peer Trim signal reaching AppModel, retained reflection draft state, notification deadline refresh, ordered recovery retry, and stale-action guards. Frozen executable hashes, strict signing and plist checks passed. Packaged recovery and the exact eight scheduled-tool contract passed. These are headless and protocol results, not native acceptance.

Eight additional supervisor cases passed under the original bounds, with final rows and process cleanup retained. The original concurrent failure remains intermittent and unlocalized. The reviewer traced cleanup and claim recovery but did not reproduce a concrete defect. Neither contention nor delayed group disappearance is established as its cause. No assertion, timeout, or product behavior changed.

The reviewer left only scratch audit artifacts and no surviving owned processes. Its task was stopped after receipt. The later Stats optimization is excluded from this verdict and receives a separate fresh review. Terra remains the sole native QA owner on the frozen `a305ba9` release.
