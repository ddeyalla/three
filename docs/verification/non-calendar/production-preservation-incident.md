# Production database preservation incident

Production data preservation failed during the day-close and reflection QA pass. The coordinator owns the failed isolation boundary. No database restoration or production restart has been performed.

## Confirmed event

The [native receipt](close-reflection-native.md) records that `cua.getApp('com.deyalla.three.finalqa.7fa641595269')` launched a stopped QA bundle without `THREE_DB`. The app selected the production default database before any fixture interaction. The delegate identified PID 87242 and its production database with `lsof`, stopped that exact QA process, and reported the incident. Its subsequent isolated checks do not undo this preservation failure.

The QA startup applied migrations v8 through v12 and closed the November 2 plan at `2026-11-03 14:02:33.681 UTC`, or `19:32:33.681 Asia/Kolkata`. The installed Three executable remained unchanged. Its original PID 92331 and start time remain present. Manual Test data and executable fingerprints matched the baseline; its original PID 29492 was already absent before this incident.

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

The recommended recovery is the exact baseline-matching v7 copy, with the post-incident state retained for audit. Before any live restoration, an independent review must verify the candidate and the procedure.

1. Recheck the live database against the saved post-incident fingerprint. If it has changed, reconcile those changes before replacement.
2. Capture another consistent current backup and revalidate the candidate's hash, integrity, schema, and all baseline fingerprints.
3. Quit only the installed Three process and confirm it has exited. Verify that no process still has the database open.
4. Preserve the live database and its WAL/SHM files together in a new recovery directory. Restore the verified candidate without replaying the upgraded WAL.
5. Reopen the unchanged installed app. Verify its executable hash, the restored database schema and contents, and normal startup. Preserve the Manual Test app and data throughout.

This procedure replaces production data and requires stopping and restarting the installed app. The [handoff](../../plans/2026-11-03-non-calendar-handoff-prompt.md) explicitly requires preserving its data and running process. That instruction does not authorize this recovery action. The coordinator will request approval for the concrete restoration after validation; it will not infer approval from the earlier permission to use disposable QA apps.

No further ticket is closed on the strength of this pass. The isolated acceptance evidence remains available, but the production incident takes precedence over the remaining native backlog.
