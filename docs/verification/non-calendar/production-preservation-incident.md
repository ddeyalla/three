# Production database preservation incident

Production data preservation failed during the day-close and reflection QA pass. The coordinator owns the failed isolation boundary. No database restoration or production restart has been performed.

## Confirmed event

The [native receipt](close-reflection-native.md) records that `cua.getApp('com.deyalla.three.finalqa.7fa641595269')` launched a stopped QA bundle without `THREE_DB`. The app selected the production default database before any fixture interaction. The delegate identified PID 87242 and its production database with `lsof`, stopped that exact QA process, and reported the incident. Its subsequent isolated checks do not undo this preservation failure.

The QA startup applied migrations v8 through v12 and closed the November 2 plan at `2026-11-03 14:02:33.681 UTC`, or `19:32:33.681 Asia/Kolkata`. The installed Three executable remained unchanged. At 14:40 UTC its original PID 92331 and start time were still present. That process has since exited; see the quiescent capture below. Manual Test data and executable fingerprints matched the baseline; its original PID 29492 was already absent before this incident.

The coordinator stopped the completed desktop delegate and confirmed no pending child runs. No other desktop delegate is active. Further desktop QA is stopped. Checking an environment after launch was insufficient because Store migration and day-close run during startup. A future QA entry point must enforce disposable paths before the app starts, including launches initiated by automation.

## Read-only assessment

The coordinator captured the current database through a read-only SQLite connection into a consistent private copy. Raw database, WAL, and SHM copies were also retained. The raw copies are not claimed as a transactionally consistent set. No production checkpoint, rollback, schema edit, process stop, or app restart occurred.

Private artifacts are under `build/verification/non-calendar/production-incident-20261103T141845055376Z/`. They include current and recovery database copies, hashes, table fingerprints, exact row-difference reports, and disposable CLI outputs. These files contain user data and are not committed.

The consistent current copy passes SQLite integrity and foreign-key checks. Comparing original columns against the pre-incident fingerprints proves that all six task rows and all three session rows are unchanged. Their raw fingerprints changed because v11 adds nullable `carriedFromTaskId` and v12 adds zero-valued `recoveryTrimSeconds`. All original tables except `dayPlan` and the migration registry match their baseline contents.

An existing backup at `~/Library/Application Support/Three/Backups/before-icon-20261103-061957/three.sqlite` matches every pre-incident table fingerprint and row count exactly. It has the same 13 tables and seven migration entries. The coordinator copied it into the private incident directory as `recovery-candidate-v7.sqlite`. Its SHA-256 is `0ef0b0c3c8354317f7b7712c2cff051b60b22e7fc9a52e5153146680973fe32e`. The candidate passes integrity and foreign-key checks.

Comparison with this matching backup resolves the earlier uncertainty about row changes:

- The November 2 plan changed from committed to closed, and its `updatedAt` changed to the incident timestamp.
- The November 3 draft plan is unchanged. Neither plan's date changed.
- The migration registry gained five entries. Seven tables were added. Only `dayClose` contains a new row; the other six new tables are empty.
- Existing task and session values are unchanged. All new lineage values are null and all trim values are zero.

The installed packaged CLI ran `today --json` against separate disposable copies of both the upgraded state and the matching v7 backup. Both exited successfully and returned identical output. This is a basic CLI-read compatibility check, not proof of every installed-app behavior on the upgraded schema. No installed app was launched or restarted for this check.

Other nearby backups did not match the full baseline. `tmutil listlocalsnapshots /` reported no local snapshots. The raw main database without its WAL is older than the baseline and is not a recovery candidate.

## Proposed restoration, not executed

The recommended recovery is the exact baseline-matching v7 copy, with the post-incident state retained for audit. The independent review below validated the candidate and required stronger replacement gates. This revised procedure remains unexecuted.

1. Obtain approval for the production stop, replacement, and restart. Establish an exclusive maintenance interval with no app, CLI, MCP, native-host, planning, or other database writes. If writer exclusion cannot be maintained, do not replace the database.
2. Verify the exact installed app path and its pre-incident executable hash before stopping or reopening it. Revalidate the candidate's hash, schema, integrity, foreign keys, complete table set, and all baseline fingerprints. Keep the original backup and candidate unchanged as sources. Record the production files' owner, group, access mode, ACLs, flags, extended attributes, and file identity. Confirm space for retained evidence and a same-filesystem replacement copy.
3. Capture the current live state, then quit only the authorized installed Three process. Confirm that every database owner has exited and no handle remains to the main database, WAL, SHM, or an old/renamed database inode. Stop if another owner needs an action outside the approval. Prevent relaunch and new connections throughout replacement.
4. **After all owners exit**, take a fresh consistent capture and compare the complete logical contents and schema with the independently reviewed post-incident state. This comparison includes graceful-shutdown writes. Any inserted, deleted, or changed data stops replacement for reconciliation. A match before quitting is not sufficient. Close the capture connection and reconfirm writer exclusion and file identity before replacement.
5. Preserve the quiescent original main/WAL/SHM set and the validated consistent pre-replacement snapshot. Stage a separate copy of the verified v7 candidate with the intended production metadata. Do not use the noncoherent `raw-current` files for rollback. Stop on unexpected sidecars, metadata differences, identity changes, or inability to preserve the current state.
6. Replace the database on the same filesystem while writer exclusion holds. The restored database must not inherit the upgraded WAL/SHM or unrelated candidate sidecars. Verify the restored hash, integrity, schema, table set, baseline fingerprints, metadata, and absence of old handles before reopening anything.
7. Reopen only the unchanged installed app. Verify its executable, database path, expected schema, contents, and startup. Stop further acceptance on unexpected migration, data differences, or startup failure. Do not automatically roll back over subsequent user work. Any rollback requires another no-new-writes comparison and must remain within the user's actual approval. Preserve Manual Test app/data and all recovery evidence throughout.

This procedure replaces production data and requires stopping and restarting the installed app. The [handoff](../../plans/2026-11-03-non-calendar-handoff-prompt.md) explicitly requires preserving its data and running process. That instruction does not authorize this recovery action. The coordinator will request approval for the concrete restoration after validation; it will not infer approval from the earlier permission to use disposable QA apps.

No further ticket is closed on the strength of this pass. The isolated acceptance evidence remains available, but the production incident takes precedence over the remaining native backlog.

## Independent review and current checkpoint

Codex Sol 6.1 High independently passed 82 captured-artifact checks. The coordinator inspected `/Users/divyanshudv/.t3/worktrees/adhd/t3-402455b5/.audit/production-recovery-review/report.md` and its command/probe receipts. It confirmed the complete 13-table baseline match, original-row differences, added schema/data, candidate integrity, foreign keys, and identical installed-helper results on owned copies. It did not access production or approve a live restoration.

The reviewer found a P1 race in the original proposal because the comparison preceded process shutdown. It also required explicit handle/WAL exclusion and identity/metadata/rollback gates. The revised sequence above incorporates those requirements. These are required execution preconditions, not completed live checks. The reviewer is stopped with no pending children or owned persistent processes.

A fresh read-only coordinator capture at `2026-11-03 14:40:21 UTC` still matches the reviewed post-incident schema and all table fingerprints. The installed executable hash still matched, and PID 92331 still had its original start time at that capture. The capture's temporary read-only Python connection exited; a subsequent handle check found only the installed process. No production stop, restoration, or restart has occurred. This checkpoint does not substitute for the required post-shutdown comparison.

## Quiescent capture after production exit

At `2026-11-03 15:01:50 UTC` no Three process was running. PID 92331 had exited. The exit cause was not recorded, and no crash report exists. `lsof +D` on the Three data directory showed no handles.

The production `three.sqlite-wal` mtime was 20:29:00 local, or 14:59:00 UTC. That is after the 14:40 checkpoint. The `three.sqlite` mtime was November 2 18:58:12 local, and the `three.sqlite-shm` mtime was November 3 06:22:12 local. Inodes 337183820, 337183822, and 337183823 and the file sizes were identical before and after copying.

The three files were copied with `cp -p` to `build/verification/non-calendar/production-incident-20261103T141845055376Z/quiescent-20261103T150232Z/`. Their SHA-256 values are:

- main: `3bca2704edf8d87f1e1a172f37aceb77056154ca398448972140db52d3e75f96`
- WAL: `c00b787c62800243fd9e9577793d91531482d4f1f1923db470d89de513fc4f3f`
- SHM: `14ac980f9b8e9f99f3015837bcbaa269949251be0caa3268405c8b20f1121fd8`

Analysis ran on a second scratch copy, not on the preserved set. The scratch copy passes the integrity check and has no foreign-key violations. Its schema is identical to `production-current-consistent.sqlite`. Every table is identical at row level except `step`. One step row changed:

- Row `92EF683A-39DD-43FE-B947-BE5B2D32B5D1`, on task `F972A51F-7834-46E7-BDE3-D2335A5F0859` ("Build the v1 and clear the tasks"), changed `done` from 0 to 1.
- Its `updatedAt` changed from `2026-11-03 00:47:38.313` to `2026-11-03 14:59:00.305`.

This is real user work after the incident. The step 4 gate of the proposed v7 restoration would correctly stop on it. A v7 restore would now lose this step completion unless it is reconciled.

Two options remain for the user:

- (a) Keep the upgraded v12 database. The packaged CLI read check already found it compatible. The only incident artifacts in it are the closed November 2 plan and its `dayClose` row.
- (b) Restore v7, then re-apply the single step completion, under the same gates.

No decision has been made. The user declined installing a new app build for now. Nothing is recommended for execution here.

The coordinator's read-only assessment at 19:51 local created an empty `-wal` file and a 32 KB `-shm` file next to each of the five `three-backup-*.sqlite` files in the production data directory. Those sidecars have a 19:51 mtime. The main backup files are unchanged and keep their older mtimes. The sidecars are harmless, but they contradict the earlier statement that no production-directory writes occurred. They are left in place.
