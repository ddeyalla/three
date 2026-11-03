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
