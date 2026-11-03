# Release History and Stats read baseline

The goal is direct, repeatable evidence for the larger-fixture History and Stats read boundary in BPRO-402 and BPRO-403.
This report measures the v11 candidate at `04d16fbb05401e455131b5a8c4472ee422932471`.
It makes an absolute latency claim for the retained disposable dataset, with no speedup comparison or native chart-rendering claim.
The maximum Stats read takes several seconds and merits a focused follow-up.

## Candidate and reproducible command

The host-prepared worktree is `/Users/divyanshudv/.t3/worktrees/adhd/t3-2187731a`, on `t3/noncalendar-read-performance`.
Initial HEAD matched the assigned SHA and the initial diff was clean.
Only the verification Python driver, linked Swift probe, and this report are owned changes.
No product code changed. No nested delegate ran. Execution used Codex gpt-6.1-sol High.

The following commands ran in that worktree.

```sh
CONFIG=release ./scripts/bundle.sh > build/verification/non-calendar/read-performance-build.log 2>&1
python3 scripts/verification/read-performance.py --output build/verification/non-calendar/read-performance-v11-run4 --through 2026-11-03 --samples 5 > build/verification/non-calendar/read-performance-run4.log 2>&1
git diff --check
```

The driver runs `codesign --verify --deep --strict build/Three.app` before fixture setup.
It links its Swift probe with `-O -g` against the actual release `ThreeCore.o` and `GRDB.o`.
The exact compiler command is retained in `probe-compile-command.json`.
The bundle is built with the real optimized configuration. It is never launched.
The packaged CLI SHA-256 is `fcf358e3a8038116ee7e9ffe1c1e5254ccae9091f384d67bcd5a0d39408ce5f7`.
The host runs macOS 27.0.1, build 26A434, on arm64 with 12 logical cores reported by `sysctl -n hw.ncpu`.
The compiler is Apple Swift 6.4. The build wrapper and probe use the macOS 26.5 SDK.
This does not establish macOS 26 runtime acceptance.

To rerun, choose a new output directory under `build/verification/non-calendar`.
The driver refuses an existing directory, dirty product inputs, fewer than five samples, or a schema other than v11.
The true default Stats case requires `--through` to equal today's UTC date.
On a later date, use that date to regenerate the same size and numerical pattern with shifted civil dates.
The retained SQLite file preserves this exact run's dates and records for explicit historical reads.

## Frozen fixture and independent expectations

The fixture spans 2025-11-03 through 2026-11-03, inclusive, in UTC.
One full year exercises the supported 366-date maximum while keeping setup and output inspection practical.
Five tasks per date exercise the product cap. Two focus sessions per task exercise repeated session attribution.
Six tags bound overlap without an artificial explosion of tag groups.
The expectation manifest is written before fixture generation or timing.

| Record | Count |
| --- | ---: |
| Dates and committed plans | 366 |
| Tasks | 1,830 |
| Focus sessions | 3,660 |
| Break sessions | 1,098 |
| Steps and task-tag links, each | 3,660 |
| Tags and blocker rules | 6 and 3 |
| Prospective commitment snapshots | 313 |
| Legacy plans with unknown commitment snapshots | 53 |
| Recorded break decisions | 2,928 |
| Block events | 12,810 |

Every date has block lengths of 25, 30, 45, 20, and 40 minutes, totaling 9,600 derived planned seconds.
Each task records 1,200 and 600 actual focus seconds. The first session has a 120-second accumulated pause.
Daily focus is 9,000 seconds, excluding 900 seconds of recorded breaks and 600 paused seconds.
Three tasks are done on their plan date and two remain partial.
Each task belongs to the common tag and one of five distinct work tags.
The global focus total counts each session once. The common tag receives that total, and each work tag receives one fifth.

The first session per task is rated focused. Four second sessions are rated okay, and the fifth has no recorded rating.
Daily quality therefore has five focused, four okay, and one unrated session.
Daily break choices have five taken, three skipped, and two unknown decisions.
Each focus session has two linked hits and one linked unblock.
Each date also has three ambient hits, one ambient unblock, and one hit associated with a break.
The last event remains unassociated with focus. Daily linked rates are eight hits and four unblocks per focus hour.

Every seventh plan starting at fixture index zero lacks a commitment snapshot.
The driver never backfills that unavailable denominator.
For known commitments, completion is three of five and actual-to-planned is 9,000 divided by 9,600.
The seven-day average becomes 150 minutes after the first six included dates.
Every included date qualifies for the bounded streak.

| Case | Dates | Focus seconds | Derived planned seconds | Known and legacy plans | Commitment seconds | Completed original tasks |
| --- | ---: | ---: | ---: | --- | ---: | --- |
| October History | 31 | 279,000 | 297,600 | 27 and 4 | 259,200 | 81 of 135 |
| Default Stats, October 7 through November 3 | 28 | 252,000 | 268,800 | 24 and 4 | 230,400 | 72 of 120 |
| Maximum History and Stats | 366 | 3,294,000 | 3,513,600 | 313 and 53 | 3,004,800 | 939 of 1,565 |

History returns 4,758 session details and 1,830 task details at the maximum.
Stats returns 366 daily entries, Monday-based weeks, six tags with their daily and weekly results, coverage flags, and the bounded streak.
The driver validates daily, weekly, aggregate, and tag totals, ratios, unknown counts, dates, task identities, session durations, steps, and cardinalities.
Every response is fully parsed and compared with the entire direct-Store result after removing only the top-level read timestamp.
A fast empty result, rejection, incomplete response, or changed record fails the run.

## Measurement boundaries and results

Setup, compilation, fixture writes, pool initialization, MCP initialization, initial checkpointing, and warmup are outside timing.
There is one warmup for each case and path, followed by five measured samples per case and path.
Each round rotates the starting case. Within each case the order is Store, persistent MCP, then one-shot CLI.
Only one request is in flight. OS caches are warm. Every CLI sample still starts a new packaged process.

The Swift probe times `Store.historyReport` or `Store.stats`, including small scalar cardinality and focus assertions.
It separately times compact sorted JSON and pretty sorted JSON encoding of that same materialized result.
Store initialization, request parsing, transport, Python validation, and output encoding are excluded from the Store interval.
The JSON intervals exclude query execution and pipe transport.
MCP timing starts before request serialization and ends after full parsing, independent validation, and complete parity comparison.
It excludes server startup and initialization. CLI timing includes process startup, Store opening, query, pretty JSON, transport, parsing, and validation.
`samples.jsonl` also retains the earlier parsed-response boundary to expose the validator's contribution.

All values below are milliseconds. Each cell gives median, then the observed minimum to maximum.

| Case | Direct Store query | Persistent MCP, parsed and validated | Packaged CLI, parsed and validated |
| --- | --- | --- | --- |
| October History, 31 dates | 78.10, 76.07 to 110.59 | 234.70, 228.00 to 252.01 | 118.84, 114.82 to 148.99 |
| Default Stats, 28 dates | 282.47, 279.61 to 283.16 | 458.70, 447.34 to 469.19 | 332.12, 319.58 to 360.48 |
| History, 366 dates | 906.22, 892.56 to 917.36 | 2,761.17, 2,705.57 to 3,180.01 | 1,117.53, 1,087.32 to 1,129.82 |
| Stats, 366 dates | 5,413.06, 5,345.45 to 5,583.61 | 7,458.33, 7,418.23 to 7,755.54 | 5,782.83, 5,635.64 to 8,432.11 |

The following encoding intervals use the linked probe's materialized result.

| Case | Compact sorted JSON | Pretty sorted JSON |
| --- | --- | --- |
| October History | 8.83, 8.74 to 9.78 | 9.19, 8.93 to 9.62 |
| Default Stats | 10.46, 10.33 to 10.96 | 10.95, 10.80 to 11.36 |
| History, 366 dates | 105.12, 102.24 to 105.76 | 109.29, 107.87 to 118.19 |
| Stats, 366 dates | 132.87, 129.27 to 134.19 | 138.52, 135.49 to 141.56 |

| Case | Compact report bytes | Pretty report bytes | MCP wire bytes, including envelope and newline |
| --- | ---: | ---: | ---: |
| October History | 569,024 | 1,016,786 | 649,072 to 649,073 |
| Default Stats | 607,734 | 1,215,726 | 675,028 to 675,029 |
| History, 366 dates | 6,715,794 | 12,002,356 | 7,659,646 to 7,659,647 |
| Stats, 366 dates | 7,495,398 | 15,054,531 | 8,324,828 to 8,324,829 |

The CLI adds one trailing newline to pretty report bytes. The MCP request ID accounts for the one-byte envelope variation.
At the maximum Stats size, the direct query median is about 94 percent of the CLI median and 73 percent of the MCP median.
Pretty encoding is about 2.4 percent and 1.9 percent of those end-to-end medians.
These ratios show scale across separate observations. They do not isolate components of a single CLI or MCP sample.

These are medians and observed minima and maxima from five samples, not population percentiles or performance budgets.
The paths run at different instants and have different process and encoding boundaries.
Subtracting their medians would not isolate startup or protocol overhead.
There is no claim that one path is faster as a general property.

## Contention, profile, and responsible-layer finding

`uptime`, top CPU processes, and owned CPU and I/O counters were recorded before and throughout the run.
The final run's observed one-minute load ranged from 6.60 to 20.53 on 12 cores.
The earlier discarded run reached 83.32. Other workers' Swift compilation and system background processes were visible.
No other worker or production process was stopped or sampled.
The final CLI maximum Stats range includes a substantial outlier, so the range stays visible beside the median.

After all reported samples, the driver ran two additional maximum Stats reads for profiling only.
They took 15.12 seconds including profiling and validation and are excluded from every timing table.
`sample` successfully captured the owned release probe for five seconds at a requested one-millisecond interval.
Of 2,934 captured query-thread stacks, 1,589 pass through `Stats.swift:207` into `NSDateFormatter.stringForObjectValue`.
The profile shows formatter regeneration and ICU date-format construction beneath that call.
The enclosing event-map call at `Stats.swift:203` accounts for 1,645 captured stacks.
`DayKey` constructs the formatter in `Sources/ThreeCore/Models.swift:54` and formats dates in its date initializer.
The event loop converts a session start date again for every linked event, even when events share the same session.
This is a sampled hot path, not an exact fraction of the complete request's CPU time.

Across the profile counter window, the probe accumulated about 12.56 CPU seconds over 14.86 wall seconds.
Its sampled CPU repeatedly approached 100 percent of one core.
Its disk-read counter increased by 786,432 bytes, its disk-write counter stayed at the initial 4,096 bytes, and page-ins stayed at 17.
The Python generator used 0.264 user seconds and 0.166 system seconds across the 15.12-second profile.
The observed limit is serial date conversion and aggregation work on the query thread, with scheduler contention affecting wall time.
The generator did not saturate a core. The low warm-read I/O does not support disk bandwidth as the dominant limit.
Encoding the 7.5 MB Stats result in roughly 0.13 seconds is plausible memory processing and is far smaller than the roughly 5.4-second query.
No disk, network, or speedup bound is claimed from the dataset's logical size alone.

The recommendation is a focused Core change that reuses each selected focus session's civil date during Stats event attribution.
Prefer a request-scoped lookup and date conversion over a shared mutable formatter.
Preserve current Gregorian civil dates, report time zones, skipped dates, and start-day attribution.
Prove the change against the existing date and accounting cases and remeasure the affected Stats paths on this fixture.
No optimization or predicted speedup is included in this unit.
The captured profile does not isolate every cause of the MCP-versus-CLI gap.

## Preservation, failures, and evidence

The final run completed 60 measured responses and 12 warmup responses, plus the two separate profiling reads.
All 72 timed and warmup responses passed independent expectations and full cross-path parity.
The two profile reads also passed independent expectations.
There were zero unexpected errors or rejections and no MCP stderr output in the final run.
The fixture passed SQLite integrity and foreign-key checks before measurement.
Both owned persistent processes exited successfully. The generator and sampler completed, leaving no owned QA process running.

The retained database is 4,521,984 bytes before and after the reads and process cleanup.
Its main-file SHA-256 stayed `e4657e4a5fe742b0e2af62c059b003f39eed890da94318e42c8b91f7977b06b8`.
Its logical dump SHA-256 stayed `419ca50f5afe9100537982a6a6ba6aeec7b174df234ae0c19d473a1a28629f20`.
All table counts and the schema stayed identical.
The probe SHA-256 is `ffe19fa0050b1cd0e967a3568e5aacd9cf9ed4d2182b26b63ed53b20c4f29466`.

The first warmup attempt failed because the harness expected a null key for a Swift optional that is omitted from JSON.
The second attempt used an unsupported `ps` keyword and was explicitly interrupted. Its timings are excluded.
The third attempt completed all responses, but its physical preservation assertion failed.
Its logical dump and schema were unchanged. GRDB's `Database.setUpWALMode` creates and drops `grdb_issue_102` when the WAL is empty.
That initial pool startup grew the database by 8 KB.
The final harness primes both persistent pools and performs a full checkpoint without truncating the WAL before the preservation baseline.
It keeps the same byte-for-byte assertion and the same fixture rows and numerical assertions.
This also matches a CLI reading while persistent Store owners keep the WAL open.
An entirely cold database open with no persistent pool is a different startup boundary.
Run 3's `errors.json` predates the corrected cleanup error accounting and reports only response failures.
Its nonzero exit and preservation failure remain explicit in `read-performance-run3.log`.

All raw evidence is retained under `build/verification/non-calendar`.

- `read-performance-build.log` contains the release build and signing receipt.
- `read-performance-run4.log` contains the final execution result.
- `read-performance-v11-run4/manifest.json` freezes source, binary hashes, expectations, dates, and host metadata.
- `read-performance-v11-run4/fixture.sqlite` is the retained disposable dataset.
- `read-performance-v11-run4/samples.jsonl` and `summary.json` contain raw samples and medians and ranges.
- `read-performance-v11-run4/history-month.json`, `history-366.json`, `stats-default28.json`, and `stats-366.json` retain fully parsed results.
- `read-performance-v11-run4/owned-counters.jsonl`, `host-snapshots.jsonl`, `profile.json`, and `probe.sample.txt` retain contention and the separate profile.
- `read-performance-v11-run4/storage-before.json`, `storage-after.json`, and `errors.json` retain preservation and failure counts.
- `read-performance-run1.log`, `read-performance-run2.log`, `read-performance-run3.log`, and their output directories preserve failed attempts.

Native month selection, chart updates, chart rendering, keyboard interaction, and physical hardware acceptance remain outside this proof and with Terra.
Pending v12 trim integration is unmeasured. This report describes the exact v11 candidate.
Future changes need focused remeasurement when they affect this read path, not a blanket acceptance claim from these timings.
No desktop app, browser, protected application database, installation, permission, login item, hotkey, sleep, paid model, release, push, merge, or Linear operation ran.

Build the Lever determined the retained fixture and reusable driver.
Model the Domain determined the fixed case table and independent per-date expectations.
Explain the Number determined separate query and encoding clocks, five interleaved samples, full validation, contention records, and a separate profile.
Prove It Works keeps this release Store and packaged protocol evidence separate from native and v12 acceptance.

## v12 event-date reuse comparison

This follow-up measures the focused event-date reuse change on v12.
The v11 report above remains historical evidence and is not a causal baseline for this change.
The host prepared `/Users/divyanshudv/.t3/worktrees/adhd/t3-9af4ee21` on `t3/event-date-reuse` at `7e0e382eab1f4f8a3b556f685fb9615f826370a1`.
The starting diff was clean. The base includes `baf775e`, which preserves moved commitment evidence.
No commits or dependencies were imported. Commitment, outcome, elapsed accounting, schema, app, CLI, and MCP implementation code are unchanged.

The request-scoped session lookup now stores the `HistoryDay.day` beside each selected focus session.
History already grouped those sessions by start date using the report calendar.
Linked events reuse that civil date. Unassociated events still convert their occurrence timestamp using the same calendar.
The event SQL, event order, tag membership, and reference accounting are unchanged.
There is no shared formatter or mutable cache.

The predeclared decision is to compare optimized v12 artifacts on identical data and retain only a demonstrated reduction in repeated conversion work.
A measured latency difference is inconclusive where run-to-run spread exceeds the median gap.
The Explain the Number principle requires a separate owned-process profile and visible ranges.
Model the Domain determines the local `(day, session)` tuple instead of a formatter cache.
Prove It Works determines the complete result comparisons and real packaged protocol checks.
All work runs in-thread on Codex gpt-6.1-sol High, without delegates or desktop control.

### Matched artifacts and fixture

The unmodified v12 product was built and measured before editing `Stats.swift`.
Its signed bundle, optimized linked probe, source hashes, fixture, canonical responses, and timing samples remain in `event-date-v12-baseline`.
After the small Core edit, a second release build produced the candidate artifacts.
The comparison preserves those separately in `event-date-v12-comparison2`.
Neither bundle is launched as an app.

The comparison starts from a byte-identical copy of the retained baseline SQLite file.
Both sides use that same comparison database and separate persistent Store and MCP processes.
Every tracked Source file except `Stats.swift`, the package manifest and lockfile, and the build wrappers must hash identically across the two builds.
The Swift probe source must also match. Each measured CLI and probe has its own recorded SHA-256.
The driver verifies the original and archived candidate bundle and the preserved baseline bundle with deep, strict codesign verification.

The schema guard now requires `v12-sleep-recovery`, empty `recoveryGap` and `recoveryImpact` tables, and zero `recoveryTrimSeconds` on every session.
The 366 dates, 3,660 focus sessions, 1,098 break sessions, 12,810 events, all other cardinalities, and all independent numeric expectations above remain unchanged.
The fixture deliberately measures no recovery decisions or trims. Recovery correctness is a separate acceptance boundary.
This fixture contains 10,980 linked events and 1,830 unassociated events.
The changed code therefore avoids 10,980 repeated event-level civil-date conversions at the maximum window.
It retains the 1,830 occurrence-date conversions and all existing History grouping work.
That arithmetic describes removed work, not a predicted speedup.

Each side receives one warmup for every case and path, then five measured samples.
For each case and round the driver runs baseline Store, MCP, and CLI, then candidate Store, MCP, and CLI.
Each individual boundary therefore alternates baseline and candidate across five rounds.
The starting case rotates each round. Requests remain serial, caches remain warm, and every CLI request starts a new packaged process.
The direct Store and encoding intervals retain their original boundaries.
MCP and CLI end-to-end intervals include full parsing, independent validation, and complete output comparison.
Only top-level `takenAt` is removed before canonical JSON byte comparison.
Every response records that canonical SHA-256 and its output byte counts.
Every result must match the actual pre-change response as well as the independent expectations.
The database must still match its physical bytes, logical dump, schema, and counts before and after measured reads and cleanup.

The successful build and measurement commands run from this worktree.

```sh
CONFIG=release ./scripts/bundle.sh > build/verification/non-calendar/event-date-baseline-build-resumed.log 2>&1
python3 scripts/verification/read-performance.py --output build/verification/non-calendar/event-date-v12-baseline --through 2026-11-03 --samples 5 > build/verification/non-calendar/event-date-v12-baseline.log 2>&1
CONFIG=release ./scripts/bundle.sh > build/verification/non-calendar/event-date-candidate-build.log 2>&1
python3 scripts/verification/read-performance.py --output build/verification/non-calendar/event-date-v12-comparison2 --through 2026-11-03 --samples 5 --baseline build/verification/non-calendar/event-date-v12-baseline > build/verification/non-calendar/event-date-v12-comparison2.log 2>&1
```

The driver uses disposable `THREE_DB` and `THREE_CHROME_DATA` paths and UTC for timed reads.
The default 28-date request remains a true default with no explicit bounds and ends on the current UTC date.
No installed or Manual Test app, database, scheduler setting, login item, notification permission, or browser is changed.

### Failed attempts retained without timings

The first baseline build and its retry failed with `No space left on device`.
The logs are `event-date-baseline-build.log` and `event-date-baseline-build-retry.log`.
Only this active worktree's newly created package repository cache was removed locally.
A third build was interrupted in its verified owned process group when the coordinator requested a capacity pause.
Its log is `event-date-baseline-build-retry2.log` and its exit was 130.
After the coordinator recovered 7.3 GiB elsewhere, the resumed baseline build passed.
The product source remained unchanged throughout baseline capture. No timing from a failed build exists.

The first comparison stopped before opening its measurement processes because the baseline archive failed deep signature verification.
Python's bundle copy had dropped the shell native-host launcher's signature metadata.
The measured CLI and probe hashes were intact.
The driver now uses macOS `ditto` and verifies the archived bundle immediately.
The baseline launcher's bytes matched the candidate launcher exactly.
`ditto` restored that unchanged launcher's metadata, after which the original baseline bundle's full signature verified and its recorded CLI SHA-256 still matched.
No binary was rebuilt or resigned for this repair. No verification assertion was removed.
`event-date-v12-comparison.log` and `event-date-archive-repair.log` retain the failure and repair evidence.

### Measured verdict

The default 28-date Stats read is measurably faster on this fixture.
The direct Store median decreases from 288.28 ms to 168.29 ms, or 41.62 percent less latency.
Its baseline range is 283.80 to 289.50 ms and its candidate range is 163.87 to 172.99 ms, with five measured samples per side.
The median gap exceeds each side's spread. Packaged MCP and CLI also have separated ranges at this size.

The maximum 366-date comparisons are inconclusive under the predeclared noise rule.
Their medians are lower, but at least one side's full spread exceeds the median gap at every boundary.
The maximum Store ranges happen to be separated, while the MCP and CLI ranges overlap.
No maximum-window percentage speedup is claimed, and no outlier is removed.
There is no measurable change in either History control case.

All values below are milliseconds, with the median followed by the full minimum to maximum range.
Each row has five measured samples per side, after one warmup per side.

| Stats case and boundary | Baseline median and range | Candidate median and range | Verdict |
| --- | ---: | ---: | --- |
| Default 28, direct Store query | 288.28, 283.80 to 289.50 | 168.29, 163.87 to 172.99 | Faster |
| Default 28, persistent MCP end to end | 460.95, 438.70 to 475.56 | 351.43, 320.08 to 353.95 | Faster |
| Default 28, packaged CLI end to end | 332.32, 329.98 to 336.67 | 212.33, 210.50 to 214.28 | Faster |
| Maximum 366, direct Store query | 5,425.10, 5,391.55 to 8,671.79 | 3,901.53, 3,849.09 to 4,745.38 | Inconclusive |
| Maximum 366, persistent MCP end to end | 7,572.81, 7,387.11 to 8,795.03 | 5,910.40, 5,755.75 to 8,811.24 | Inconclusive |
| Maximum 366, packaged CLI end to end | 5,770.04, 5,755.93 to 5,812.42 | 4,165.49, 4,158.12 to 7,232.03 | Inconclusive |

The default query median is about 87 percent of the baseline CLI median and 63 percent of the baseline MCP median.
These are approximate component shares from separate requests, not additive spans from one trace.
The query is a material part of the end-to-end wait, and the default-window improvement appears at both packaged boundaries.
It does not establish native selection, rendering, or interaction latency.

The unchanged History Store control medians are 79.10 versus 79.03 ms for the month and 911.02 versus 914.73 ms for 366 dates.
Their differences are smaller than the observed spreads.
`summary.json` retains query, encoding, parsed, and fully validated timing distributions for all four cases and both sides.
The separate initial v12 baseline run also remains available, but the causal table uses only the alternating comparison.

Compact and pretty encoding still process the full materialized result.
At the default size, their candidate medians are 10.31 and 10.65 ms.
At 366 dates, their candidate medians are 127.13 and 132.89 ms.
These costs remain far below the query interval. The change does not skip encoding or return fewer results.

Both sides produce the same measured output sizes.

| Stats case | Compact JSON bytes | Pretty JSON bytes | MCP wire bytes | CLI stdout bytes |
| --- | ---: | ---: | ---: | ---: |
| Default 28 | 607,734 | 1,215,726 | 675,028 to 675,029 | 1,215,727 |
| Maximum 366 | 7,495,398 | 15,054,531 | 8,324,828 to 8,324,829 | 15,054,532 |

The CLI includes its trailing newline. MCP request IDs account for the one-byte wire variation.
Every timed and warmup response has the same normalized result hash for its case, across both sides and all three paths.

### Limiter and contention evidence

The comparison's one-minute load samples range from 4.07 to 17.21 on 12 logical cores.
Its manifest host snapshot is at 2026-11-03 11:54:01.981 UTC, or 17:24:01.981 Asia/Kolkata.
The last timed-case host snapshot is at 11:58:58.537 UTC, or 17:28:58.537 local.
The post-profile host snapshot is at 11:59:25.171 UTC, or 17:29:25.171 local.
These timestamps and the raw counters allow the coordinator to identify overlap with its combined-source test and release builds.
The later integrated `a305ba9` lifecycle and `75fc9aa` protocol commits are not imported into either measured side.
The host snapshots show another Swift compiler and system analysis processes during the high-load interval.
No other process was stopped or sampled. This worker ran no test compilation during the timed comparison or its profiles.

Each side then runs an owned-probe profile, excluded from the timing table.
Both five-second `sample` captures exit successfully.
The baseline performs two additional validated maximum Stats reads over 12.79 seconds, and the candidate performs three over 13.65 seconds.
Those wall times include the profiler and Python validation and are not speedup measurements.

The baseline profile has 3,100 query-thread stacks, with 1,524 passing through the event map at old `Stats.swift:203`.
Of those, 1,481 pass through the event-date conversion at old `Stats.swift:207`, predominantly into `NSDateFormatter` regeneration and ICU.
The candidate has 3,042 query stacks, with 226 through the event map at `Stats.swift:205` and 206 through its remaining occurrence-date conversion at `Stats.swift:209`.
The candidate instead spends 1,300 sampled stacks in the per-tag daily calculation at `Stats.swift:239` and 691 in History at `Stats.swift:191`.
These are sampled stack frequencies, not exact request CPU fractions or an Amdahl bound.
They support the narrower finding that the repeated linked-event formatter work has been removed while existing aggregation and History work remain.

The owned probe reaches 100 percent CPU in each profile, consistent with serial query work limiting this path.
Across each profile's counter window, its disk read and write byte counters and page-ins do not increase.
The Python generator uses 0.227 user and 0.157 system seconds during the baseline profile, and 0.328 user and 0.171 system seconds during the candidate profile.
The generator is not saturated. These observations support CPU work and scheduler contention, rather than warm-read disk bandwidth, as the limit.
Remaining History date grouping, per-day/tag aggregation, and the retained ambient-event conversions prevent the whole query from disappearing.
The profiles do not isolate every cause of the MCP-versus-CLI difference.

### Correctness, cleanup, and acceptance

PASS. The pre-change v12 run validates all 72 timed and warmup responses with zero unexpected errors or rejections.
PASS. The alternating comparison validates 120 timed and 24 warmup responses with zero unexpected errors or rejections and empty MCP stderr for both sides.
PASS. All five additional comparison-profile reads pass independent numeric and cardinality expectations.
PASS. Both databases preserve their physical bytes, logical dumps, schema, and table counts across measured reads and owned-process cleanup.
Their logical SHA-256 is `20f5c0219db7ee83a64d94c96cf2a64e56b515af607228f6a3f6027632bb5a80`.
The comparison database remains 4,550,656 bytes, with main-file SHA-256 `105da3c97901eea368461922c249e83b70364f243eb4c620bac3368f9606a2d9` before and after reads.
The initial baseline has a different physical header after pool startup, with identical logical contents. Its own before/after main-file SHA-256 stays `4067a70b2b2f50b72e943cfc13a61907438b0952b33b3d68c0e4ba960f8fc40b`.
The copy is asserted byte-identical to the initial baseline before the comparison pools are opened.
All four comparison persistent processes and both initial baseline processes exit zero, recorded with their owned PIDs in `cleanup.json`.

PASS. Thirty-two additional packaged CLI/MCP responses preserve expected event attribution in Cairo's skipped midnight hour and repeated late hour, Apia's skipped date, and a Los Angeles cross-midnight session.
Each disposable fixture includes two linked hits, one linked unblock, an ambient hit, and a hit linked to a break.
Linked focus events follow the session start day; the other hits follow occurrence day; skipped dates stay empty.
Both sides agree on full History and Stats output, and each fixture's logical storage is unchanged.
`date-checks.json` records all four cases and each case directory retains its database and canonical responses.

The following focused checks run against the optimized candidate. They use disposable data and Chrome folders.

```sh
THREE_DB="$PWD/build/verification/non-calendar/event-date-focused-default.sqlite" THREE_CHROME_DATA="$PWD/build/verification/non-calendar/event-date-focused-chrome" ./scripts/swift.sh test -c release --filter 'stats|history' > build/verification/non-calendar/event-date-focused-tests.log 2>&1
THREE_CHROME_DATA="$PWD/build/verification/non-calendar/event-date-stats-parity-chrome" python3 scripts/test-stats.py --binary build/verification/non-calendar/event-date-v12-comparison2/Three.app/Contents/Helpers/three > build/verification/non-calendar/event-date-stats-parity.log 2>&1
THREE_CHROME_DATA="$PWD/build/verification/non-calendar/event-date-history-parity-chrome" python3 scripts/test-history.py --binary build/verification/non-calendar/event-date-v12-comparison2/Three.app/Contents/Helpers/three > build/verification/non-calendar/event-date-history-parity.log 2>&1
git diff --check
```

PASS. All 29 selected Swift tests pass, including Apia skipped-date cases, DST, start-day event attribution, missing references, tag overlap, and the inherited moved-commitment regression tests.
Cairo is covered by the additional packaged fixtures, not by an invented pre-existing unit test.
PASS. Fixed packaged Stats parity verifies all five metrics, denominators, tags, breaks, null ratios, bounds, and read-only storage.
PASS. Fixed packaged History parity verifies elapsed accounting, carry history, deleted references, empty dates, legacy compatibility, and read-only storage.
PASS. `git diff --check` and Python source compilation pass. The historical v11 report remains a byte-identical prefix of this document.

Raw evidence remains under `build/verification/non-calendar/event-date-v12-baseline` and `event-date-v12-comparison2`.
Each contains artifact hashes, manifest, exact probe compiler command, canonical outputs, raw samples, summaries, host snapshots, owned counters, preservation checks, cleanup receipts, and separate profiles.
`event-date-final-verification.log` records the final artifact checks of alternating sample order, canonical hashes, artifact signatures and hashes, unchanged storage, dead owned PIDs, and focused test receipts.
The measured CLI hashes are `d64d39bea4375f322c75a0578c7058a218d7a194924d3ae5684eec880005d26d` for baseline and `d5a2807f9093f01bd192f4d8b4c1d57900a1088b99a4aaf54168b66ec4947458` for candidate.

COULD NOT RUN. Native rendering and interaction acceptance are outside this worker's authorization. No native latency claim is made.
COULD NOT RUN. macOS 26 runtime acceptance is unavailable on this macOS 27 host.
The full integrated suite and independent review remain coordinator responsibilities. The focused checks do not replace them.
No calendar, BPRO-396, production data, manual-test data, release metadata, paid model, real sync, Linear, merge, or PR operation is part of this unit.
