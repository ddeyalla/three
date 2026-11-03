# Non-calendar delivery evidence

Work is on `dv/non-calendar-backlog`, based on the committed handoff at `81e5a96`. The current product candidate is `07607eb`; later evidence-only commits do not change that product. No merge, release, version change, production install, calendar work, or real sync is included. BPRO-396 remains open and unchanged.

This index separates implemented behavior from required acceptance. Historical receipts retain their exact candidate revisions. Later passes do not rewrite earlier failures.

| Ticket | Implementation commits | Verified behavior and remaining gate |
| --- | --- | --- |
| BPRO-402 | `9d1bb33`, `d0a9118`, `9921b03` | Shared bounded History, civil-date fixes, CLI/MCP parity, native two-month drill-down and Done navigation passed. Remaining native navigation, narrow layout, refresh, error/retry and latency checks are assigned to Terra. [Evidence](402.md). |
| BPRO-403 | `b1d28dc`, `04d16fb`, `baf775e`, `dbba9ae`, `07607eb` | Five shared metrics, denominators, tags, recovery-adjusted reads, independent reviews, and native fixture values passed. Date-axis source review passed. Corrected rendering and remaining native interactions/latency await Terra. [Evidence](403.md), [performance](read-performance.md), [axis correction](trends-axis.md). |
| BPRO-404 | `529b8ba`, `c0dc6ed` | Transactional close/carry, durable decisions, frozen summaries, protocol checks and native accept/dismiss/skip/resolved-close passed. Remaining native entry, deferral and error presentation checks await Terra. [Evidence](404.md). |
| BPRO-405 | `76bb3b8`, `ae9af2a`, `81be12e`, `75fc9aa`, `a305ba9` | Recovery Core, manual adapters, lifecycle/draft/notification guards and independent review passed. Native seeded Keep/Trim and relaunch passed. Shortcut/status-item, notification/login acceptance, physical sleep/lock and macOS 26 remain open. The intermittent supervisor failure is separately retained below. [Core](405-recovery.md), [protocol](405-protocol.md), [lifecycle](405-integration.md), [setup](405-setup.md). |
| BPRO-406 | `b6ec011`, shared signal fix `7e0e382` | One-way strict action, active-focus policy, persistence, external refresh and stale closed-day error passed. Submenu stability now has native proof. Final keyboard/help/selection checks await Terra. Broader browser/path/category/network filtering remains deferred. [Evidence](406.md), [earlier native receipt](406-native.md). |
| BPRO-407 | `4fb7e62`, `bb1444b`, `288b064` | **Done for discovery.** Actual v10/v12 schema, deletion/conflict/timer/account rules and S1–S7 implementation slices independently reviewed. No CloudKit or companion implementation claimed. [Design](../../plans/2026-11-03-sync-companion-design.md), [review receipt](407.md). |
| BPRO-408 | `2697f9e`, `c0dc6ed`, `d4cd256` | Optional supported-display controls share the existing timer. Stale-session guards and explicit native pause/resume/finish/Escape passed. Automatic focus behavior, keyboard, Spaces/fullscreen and display fallback remain open. [Evidence](408.md). |

Only BPRO-407 is closed. Other tickets remain In Progress while their required acceptance is incomplete. The sole active verification owner is Terra on frozen `07607eb`; all completed implementation and independent-review delegates were stopped.

## Combined proof

The [integration checkpoint](integration-checkpoint.md) records 216 Core, 72 App and 22 extension tests, design lint, release build and strict local signing, packaged MCP/History/Stats/day-close/recovery/draft-review/scheduled-planning checks, independent reviews, and exact source/artifact identities. The last product delta changes only chart axes; its newly built helper is byte-identical to the independently reviewed optimized helper. All signatures are local ad-hoc signatures, not notarized release proof.

The [native recovery receipt](final-native-recovery.md) records seeded recovery decisions, draft preservation, three submenu minute transitions, unrelated-database isolation, legitimate watched-database refresh, five Trends values, and explicit notch controls. Those native observations used `a305ba9`. Corrected-chart and remaining-interaction proof belongs to the next receipt at `07607eb`.

One initial concurrent `test-planning-supervisor.py` run failed its existing deadline bound. Three parent isolated runs and eight independently reviewed cases subsequently passed without changing a timeout or assertion. The original temporary database was not retained by the old script. No concrete cause was reproduced. This remains intermittent and unlocalized, rather than an erased failure or an invented fix.

## Preserved state and local artifacts

The latest completed native bracket matched installed Three's executable and WAL-visible table fingerprints, PID 92331 and its original start time. Manual Test's executable and data also matched. Its original PID 29492 exited during the first baseline for an unknown cause and time; it was never restarted and its process-preservation check did not pass.

The current signed local candidate is `build/verification/non-calendar/frozen-07607eb/Three.app`, with identities in its adjacent `identity.json`. It has the production bundle identity and must not be launched as the isolated QA app. Terra prepares a separately identified copy with explicit disposable `THREE_DB` and `THREE_CHROME_DATA`; its receipt supplies the safe app/fixture paths. Neither `make run` nor `make install` is part of this run.

Raw logs, fixtures and screenshots remain under the paths named in each receipt. They are local ignored artifacts. Reusable repository scripts cover packaged parity, recovery fixtures, schema audit, and read performance. Existing historical preparation helpers deliberately reject source/artifact drift. [Contracts](contracts.md) and [the decision trail](decisions.tsv) explain ownership, defaults and exceptions.
