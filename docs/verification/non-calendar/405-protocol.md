# BPRO-405 recovery protocol verification

The protocol unit exposes manual recovery status and explicit Keep or Trim through the existing Store. It adds no recovery calculation, event simulator, timer, table, or migration.

The host-prepared worktree is `/Users/divyanshudv/.t3/worktrees/adhd/t3-138376ee`. Its branch is `t3/mcp-402-recovery-mcp`. Initial HEAD was `7e0e382eab1f4f8a3b556f685fb9615f826370a1` with a clean diff. The remote is `https://github.com/ddeyalla/three`. All writes remained in this worktree or disposable test directories created by its fixtures.

## Public contract

- `three recovery [--json]` reads `Store.recoveryStatus()`.
- `three recovery-decide ID --decision keep|trim [--json]` calls `Store.decideRecovery`. The decision is required. IDs are exact gap UUIDs, preserving the returned spelling.
- `get_recovery` and `decide_recovery` expose the same Core results over MCP. MCP validates UUID spelling, decision values, types, required fields, and unknown fields before calling Store.
- Existing `RecoverySessionReview`, `RecoveryReview`, and `RecoveryStatus` gain Codable conformance. Unresolved session IDs encode in sorted order. Store already orders reviews and affected sessions. No parallel result model exists.
- Manual MCP now has 33 tools. Scheduled MCP retains exactly its original eight tools. It refuses both recovery tools, including direct calls. No sleep or lock simulation operation is public.
- Existing CLI, MCP, `get_history`, and parameterless timer behavior remain compatible.

The Model the Domain principle led to reusing Core's report types. Boundary Discipline led to argument validation at the CLI and MCP boundaries. Prove It Works led to packaged CLI/MCP tests against exact persisted outcomes.

## Accounting evidence

`scripts/test-recovery.py` creates disposable databases through `scripts/verification/recovery-fixture.py`. It sets both `THREE_DB` and `THREE_CHROME_DATA`. It places historical records at 09:00 local yesterday so a midnight run cannot split the fixture across days. No installed app launches. Scheduled provider settings remain off.

The historical fixture records 1800 wall seconds and 300 paused seconds. Its known 900-second eligible absence produces these independent expectations.

| Value | Before decision or after Keep | After Trim |
| --- | --- | --- |
| Focus actuals in shared History and Stats | 1500 seconds | 600 seconds |
| Seven-day average | 25 / 7 minutes | 10 / 7 minutes |
| Actual/planned numerator | 1500 seconds | 600 seconds |
| Actual/planned denominator | 2700 seconds | 2700 seconds |
| Committed task denominator | 1 | 1 |
| Each overlapping tag's focus | 1500 seconds | 600 seconds |
| Associated block hits | 2 | 2 |
| Associated unblock events | 1 | 1 |
| Block-rate focus-hour denominator | 1500 / 3600 | 600 / 3600 |
| Hits per focus hour | 4.8 | 12 |

The script compares real packaged CLI and MCP reports and asserts each value. Global focus is counted once despite two tags. It preserves commitment rows, event rows and IDs, ratings, reflection text, session IDs, pause totals, and start/end timestamps. A paused newer break's entire persisted session row stays unchanged after the historical decision.

Sequential duplicate and contradictory retries return the first saved gap, including its original decision timestamp. Concurrent calls through two MCP processes and the CLI return the same durable result. A restarted server retains pending reviews and saved decisions. Keep preserves session rows. Trim applies 900 seconds exactly once. Untrusted Trim and decisions on an observing gap fail without logical database changes. Unknown IDs, prefixes, missing decisions, wrong types, unknown fields, and invalid choices fail at the boundary or Store guard.

Repeated status and report reads preserve the logical SQLite dump. An observing status read leaves the observation open. The packaged historical fixture proves CLI and MCP default day-close both defer unresolved recovery without an adapter-supplied callback. Integrity and foreign-key checks pass after correction.

`RecoveryReportTests` creates observations through real Core methods. It verifies the same History and Stats outcomes, nested sleep/lock, duplicate observations, Codable round trips, stable ID order, and pause overlap. A 1000-second gap with a 500-second pause trims only 500 seconds. Its 700 recorded focus seconds become 200, and a second Trim changes nothing. Report calculations continue to use `Session.elapsed`.

## Executed checks

| Command | Result | Evidence under `build/verification/non-calendar/` |
| --- | --- | --- |
| Initial `./scripts/swift.sh build --product three` and focused test attempt | FAIL before verification completed. The host disk filled during linking and plugin generation. | `405-protocol-cli-build.log`, `405-protocol-reports.log` |
| Two CLI build retries | FAIL from the same host storage condition. No source diagnostic caused these failures. | `405-protocol-cli-retry.log`, `405-protocol-cli-build-final.log` |
| `./scripts/swift.sh test --filter RecoveryReportTests` after space became available | PASS, 3 tests with two Keep/Trim cases in one test | `405-protocol-reports-final.log` |
| `./scripts/swift.sh test --filter ThreeCoreTests` on the final source | PASS, 215 tests | `405-protocol-core.log` |
| `./scripts/bundle.sh` | PASS, debug app and packaged CLI build with ad-hoc signing | `405-protocol-bundle.log` |
| `codesign --verify --deep --strict build/Three.app` | PASS | `405-protocol-signing.log` |
| `python3 scripts/test-recovery.py --binary build/Three.app/Contents/Helpers/three` | PASS, Keep, Trim, concurrent retries, malformed inputs, restart, read-only status, default close guard, and exact History/Stats parity | `405-protocol-packaged-recovery.log` |
| `python3 scripts/test-mcp.py --binary build/Three.app/Contents/Helpers/three` with disposable Chrome data | PASS, 33 tools and existing complete protocol checks | `405-protocol-mcp.log` |
| `python3 scripts/test-scheduled-planning.py --app build/Three.app` with disposable Chrome data | PASS, original eight tools, 21 refused mutations, and 4 refused additional reads | `405-protocol-scheduled.log` |
| Python AST parsing for all three changed scripts | PASS | Executed in-thread without bytecode artifacts |
| `git diff --check` | PASS | Executed in-thread |

The first storage recovery removed only this worktree's generated `.build/repositories` cache. That recovered little space. Verification resumed when host space became available. No other checkout or cache was deleted.

## Dependencies and remaining acceptance

No commits were cherry-picked or imported by this worker. The supplied base already includes recovery accounting `ae9af2a385bdd88aac5982d456346c92be1a84ae`, pause rounding `4113ae26a4cd2ccc7ff690e3edf0ace398a58632`, native event modules `7e4691dba70f412f01c421fb5a31c3a480136bee`, and moved-commitment statistics `baf775e147b7be12a8d6abee2219a20b51dbb0b1`.

The parent reported a separate stale-reflection guard finding and owns its fix in Reflections.swift and ReflectionTests. That fix is not imported here. Final integrated verification must include it.

Native UI, physical sleep/lock, integrated notification reconciliation, and macOS 26 acceptance are COULD NOT RUN in this headless assignment. Parent-owned independent review remains outstanding. These tests do not close BPRO-405. No app composition, other Core logic, Store schema, History/Stats implementation, calendar work, BPRO-396 status, production/manual-test data, real sync, release/version metadata, Linear state, or provider settings changed.

Implementation and verification ran in-thread on Codex gpt-6.1-sol High. No nested delegates ran. The parent retains playbook, review, integration, and Linear ownership.

## Coordinator integration

The coordinator imported this unit as `75fc9aa`, on top of the shared reflection-identity correction `81be12e`. No additional recovery calculations or migration changes were needed.

| Check | Result | Coordinator evidence under `build/verification/non-calendar/` |
| --- | --- | --- |
| `./scripts/swift.sh test --filter 'Recovery\|Reflection\|reflection'` | PASS, 34 Core and 9 App tests | `405-protocol-integrated-tests.log` |
| `./scripts/bundle.sh` and `codesign --verify --deep --strict build/Three.app` | PASS, debug packaged build | `405-protocol-integrated-bundle.log` |
| `python3 scripts/test-recovery.py --binary build/Three.app/Contents/Helpers/three` | PASS, explicit Keep 1500 seconds, Trim 600 seconds, stable first decision across concurrent contradictory retries | `405-protocol-integrated-recovery.log` |
| `python3 scripts/test-mcp.py --binary build/Three.app/Contents/Helpers/three` | PASS, 33 manual tools and existing protocol regression checks | `405-protocol-integrated-mcp.log` |
| `python3 scripts/test-scheduled-planning.py --app build/Three.app` | PASS, exact eight scheduled tools, 21 refused mutations and four refused additional reads | `405-protocol-integrated-scheduled.log` |

The original signed `7e0e382` bundle was preserved with `ditto` at `build/verification/non-calendar/frozen-7e0e382/Three.app` before rebuilding. Its app/helper hashes and full signature still match the schema and native retry receipts. The fresh discovery reviewer received this stable path.

Final lifecycle composition, independent protocol review, integrated release checks, and native acceptance remain open. No app was launched during these coordinator checks.
