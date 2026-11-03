# Sync and companion implementation design

BPRO-407 is discovery. This document proposes later implementation units. No sync, companion app, Linear integration, entitlement, or account change is enabled by this run.

## Start with one writing Mac and read-only companions

Keep SQLite and Store transactions authoritative on the primary Mac. The first shipping slice publishes an opt-in, private CloudKit replica and reads it on a second Mac. The second Mac cannot edit plans or control a timer. This restriction preserves the five-task cap, closed-day guards, and one-timer rule while transport reliability is proved. The next slice adds read-only Today and history on iPhone. Watch receives a compact snapshot through its paired iPhone.

A companion shows when the primary last updated its snapshot. It never presents a stale timer as an authoritative live session. The UI may calculate a labelled estimate from the primary's timestamp and pause state. It cannot start or finish a local timer. Losing connectivity does not block local planning on the primary.

Two-way editing and remote focus commands are separate follow-ups. CloudKit synchronization does not provide a globally exclusive offline timer. A device must not infer ownership from an expired wall-clock lease.

## Audit the schema that exists

The baseline is `e4f91f169bacf4e4d10c4574623fa3372d16fdc0`, migrations v1 through v10. [schema-v10.json](../verification/non-calendar/schema-v10.json) contains every actual column, type, default, primary key, foreign key, and index from the disposable v10 fixture. Source owners are `Sources/ThreeCore/Store.swift`, `Models.swift`, `Operations.swift`, `Capture.swift`, `Tags.swift`, `BlockStore.swift`, and `ScheduledPlanning.swift`.

| Table | Actual key and timestamps | Relationships and deletion | Proposed sync scope |
| --- | --- | --- | --- |
| category | Text id. updatedAt, deletedAt. No createdAt. | Unique name. Tasks reference id. Archive preserves references. | Include identity, name, color, position, and archive state. |
| dayPlan | Text id and unique day. createdAt, committedAt, updatedAt, deletedAt. | Tasks and planningRun reference id. v8 merges date collisions and physically deletes redundant plan rows. | Include canonical local day and lifecycle, with transaction-level plan revisions. |
| task | Text id. updatedAt, deletedAt, doneAt. No createdAt. | Optional dayPlanId, required categoryId. Removal drops worked tasks or soft-deletes untouched tasks. Baseline lacks carry lineage. | Include task and prospective lineage. Preserve unavailable historical lineage as null. |
| session | Text id. startedAt, pausedAt, endedAt, updatedAt. No deletedAt. | Optional taskId. Partial unique index permits one local running session. Reflection fields and reflectionPending belong to this row. | Include completed history and the primary's current-session snapshot. Never import a remote running row into the local timer table on a companion. |
| step | Text id and updatedAt. No createdAt or deletedAt. | Required taskId with delete cascade. removeStep physically deletes. | Requires persistent deletion metadata before syncing. |
| tag | Text id, createdAt, updatedAt. No deletedAt. | Case-insensitive unique name. Archive flag. | Include archive state and stable identity. |
| taskTag | Composite taskId and tagId. No timestamps or row id. | Both foreign keys cascade. Replace/remove physically deletes links. | Stable composite record name plus explicit membership tombstone. |
| preference | Text key, JSON value. No timestamps. | Device and timer settings share a table. | Allowlist only timer defaults later. Never replicate the entire table. |
| blockRule | Text id, createdAt, updatedAt, deletedAt. | Partial live uniqueness on kind/value. Events reference rules. | Defer policy replication. Read-only history may carry minimal rule labels. |
| focusWindow | Text id, createdAt, updatedAt, deletedAt. | Weekly local-time windows. Partial live uniqueness. | Device-local in the first slice. |
| blockEvent | Text id and at. No updatedAt or deletedAt. | References rule and optional session. Retains unblock reason and expiry. | Private sensitive history, opt-in separately. Exclude reasons from companion snapshots by default. |
| browserClient | Text id, connectedAt, seenAt. No updatedAt/deletedAt. | Old clients are physically pruned. | Never sync. This is local installation health. |
| planningRun | Text id, startedAt, deadline, finishedAt, notifiedAt. No updatedAt/deletedAt. | Optional draftPlanId. Local processGroup and supervisorPID. Stores command, stdout, stderr, errors. | Never sync execution state, commands, process IDs, or logs. |
| grdb_migrations | Migration identifier. | Local schema bookkeeping. | Never sync. |

The older PRODUCT claim that every row has UUID/update/delete metadata and needs no migration is false. Storage uses text IDs, and public model types do not prove all persisted columns. `doneAt` is one example. Migration history, raw schema, and mutation code must all be audited.

### Integrated day-close and recovery schema

The integrated audit is [schema-v12.json](../verification/non-calendar/schema-v12.json), built from `7e0e382eab1f4f8a3b556f685fb9615f826370a1`. It records 20 tables and 12 migrations, including `v11-day-close` and `v12-sleep-recovery`, with no views or triggers. The following additions extend the v10 inventory above.

| Table or field | Actual identity, constraints, and timestamps | Mutation and deletion | Proposed sync treatment |
| --- | --- | --- | --- |
| task.carriedFromTaskId | Nullable self-reference. A partial unique index allows one copy per source. | Set when an accepted carry creates the copy. The source remains with its original sessions. Existing rows default to null. | Include the source identity. Publish the copy, source status, copied steps and tags, and carry decision as one plan transaction. Never infer missing historical lineage. |
| planCommitment | planId primary key and foreign key. capturedAt and tasksJSON are required. | First commitment inserts once. JSON contains taskId and plannedMinutes. No update/delete API or update/delete timestamps. JSON task IDs have no SQL foreign keys. | Include the original snapshot as immutable evidence under the plan identity. Validate embedded IDs and version the JSON format. Preserve it when tasks move or disappear. Never recalculate the denominator from the current plan. |
| dayClose | planId primary key and foreign key. Unique day. Required closedAt and summaryJSON. | Store inserts the summary and closes the plan in one transaction. The summary has task outcomes, commitment, session outcomes, break decisions, and focus totals. No update/delete API or update/delete timestamps. | Include the original close record as an immutable snapshot. Version and validate embedded references. Label it as the close-time record. Recompute current History and Trends from accepted session records, without summing the snapshot again. |
| carryDecision | sourceTaskId primary key and foreign key. Optional unique copyTaskId references task. destinationDay and decidedAt. | Checked accepted/dismissed enum. Accepted requires copy and destination. Dismissed forbids both. Store preserves the first decision. No update/delete API or update/delete timestamps. | Use sourceTaskId as record identity. Conflicting decisions require explicit resolution. Import with source/copy changes atomically. A duplicate delivery cannot create a second copy. |
| breakDecision | sessionId primary key and foreign key. Checked taken/skipped enum and decidedAt. | Recorded once with the reflection transition. No update/delete API or update/delete timestamps. | Include the decision under the focus session identity. Preserve missing historical decisions as unavailable. A conflicting terminal decision is rejected for review. |
| session.recoveryTrimSeconds | Required nonnegative DOUBLE, default zero. Session retains its existing identity and updatedAt. | A trim increments this value inside the same transaction that decides its gap. Session.elapsed subtracts it and plannedEnd accounts for it. | Publish the corrected session revision. Never sum this field with received adjustments or invoke decideRecovery while importing a decided gap. Duplicate revisions must leave elapsed time unchanged. |
| recoveryGap | Text id. startedAt, optional endedAt, lastObservedAt, optional continuousSeconds/clockID, clockReliable, sleeping, locked, awaySeconds, state, optional decidedAt. | Checked observing/review/notRequired/kept/trimmed states. One observing row is allowed. Only observing has no endedAt. A state/startedAt index supports pending reads. Observation mutates the row until a first terminal decision. No updatedAt/deletedAt or delete API. | Keep active observations, clock identity, monotonic readings, and sleep/lock flags on the owning device. Publish only terminal decision evidence needed by a read-only replica, with a source revision. A replica cannot observe, resolve, or reopen a gap. |
| recoveryImpact | Composite gapId/sessionId primary key. Both are foreign keys. Session lookup index. Nonnegative baselineWork and eligibleSeconds. No timestamps. | Captures affected focus sessions and eligible unpaused time. No deletion API. Fractional-pause corrections can update the baseline before the gap ends. | Keep baselineWork local. If terminal provenance is included, identify it by the composite key and include eligibleSeconds as evidence only. It is not another amount to subtract from session elapsed. |

Five added tables use foreign keys without delete cascades. `recoveryGap` has no parent foreign key. These relationships retain references rather than automatically erasing evidence when a parent is deleted. None of the six tables has general sync revision or tombstone columns. S1 must add transport metadata and retain any future explicit deletion intent. A retention policy cannot physically purge these rows without addressing their dependents and offline replicas.

The Store defers day-close while affecting recovery is observing or pending review. A close summary is stored JSON and is not rewritten by a later session mutation. A future correction imported after close therefore changes current session reads, while the original close record remains historical evidence. A companion must distinguish those values. It must not silently overwrite a close snapshot with a new aggregate.

None of these JSON columns contains a payload-version field. The CloudKit record format must provide one before transport begins. Local migration identifiers alone are not a network schema contract. Device preferences remain local, including the new day-close setting and native setup settings.

`scripts/verification/audit-schema.py` captures columns, keys, index definitions, triggers, views, migrations, and the packaged helper hash. It uses a new disposable database, checks SQLite integrity and foreign keys, and refuses to replace a receipt. The caller supplies the commit of the freshly verified build. Reproduce this audit with the following commands at that revision.

```sh
./scripts/bundle.sh
codesign --verify --deep --strict build/Three.app
python3 scripts/verification/audit-schema.py --binary build/Three.app/Contents/Helpers/three --source 7e0e382eab1f4f8a3b556f685fb9615f826370a1 --output build/verification/non-calendar/schema-v12-rerun.json
```

The audit proves the packaged local schema. Live CloudKit, signed-device/account behavior, and crash recovery of a future sync migration remain S1/S2 acceptance work.

## Record identity and transport

Use one private CloudKit custom zone per account and a versioned record format. A record name combines entity kind with the existing stable id. Membership uses its two stable IDs. Never regenerate IDs on retry or derive task identity from title. Keep CloudKit system fields/change tags separately from user data. Each record includes schema version, owning device id, monotonically increasing device revision, and an optional tombstone. Wall-clock updatedAt is display information, not conflict ordering.

The primary writes its Store mutation and a durable outbox entry in the same SQLite transaction. An acknowledged outbox item is removed only if its revision still matches the sent revision. An edit during upload remains queued. Record IDs and revisions make uncertain delivery safe to retry. A fetch applies validated records and saves its engine checkpoint transactionally. A crash before checkpoint persistence replays the same revisions without duplicate sessions or tasks.

Create CKSyncEngine only after opt-in, account identity resolution, and migration success. Persist its opaque state separately for each account/zone. Let the engine handle transient network throttling and retry-after. Handle application errors explicitly. Schema incompatibility, permissions, quota, or conflicting content produce a visible paused/error state with last successful sync time. They must not roll back local work or silently discard outbox entries. Manual retry uses the same durable queue.

Validate inbound fields and bounded record sizes at the sync boundary. Resolve dependencies before applying references. Missing category/task parents hold a dependent record in a bounded pending import queue and request its parent. Tombstones count as valid known parents for historical records. An unresolved import never weakens Store constraints or disables foreign keys.

No secrets, shell commands, process IDs, Chrome profile paths, global hotkeys, login-item state, notification permissions, or local file paths enter CloudKit. User notes and reflections are personal data. Explain their upload before opt-in and keep them in the user's private database. Do not describe private CloudKit storage as application-level end-to-end encryption.

## Conflicts and deletion

The first slice has one registered writer. A replica rejects local mutations before they reach Store. If it detects an unauthorized writer id or competing primary generation, it pauses publication and preserves both records for review. It does not choose a winner using clock time.

Later two-way editing needs these rules before it is enabled.

| Concurrent change | Required rule |
| --- | --- |
| Different fields on the same task | Merge only when both changes share a known base revision and affect independent fields. Validate the resulting task through Store. |
| Two titles or notes edited from the same base | Keep the current accepted value and preserve the other value as an explicit conflict. No silent last-write-wins loss. |
| Two task lists or orders for one date | Treat the whole plan revision as a transaction. Do not union into more than five counted tasks. Preserve rejected additions as unresolved proposals, not silently scheduled work. |
| Closed day versus an old edit | Closed wins for ordinary edits. Preserve the rejected edit as a proposal. Only the explicit carry transition may create later work. |
| Carry accepted twice | Source id plus carry-decision identity determines one destination copy. A second different destination is a conflict. No duplicate copy. |
| Task done versus earlier active status | Session history is immutable evidence; a stale active flag cannot resurrect a timer. Task reopening is an explicit guarded command. |
| Strict false versus strict true | True wins. Sync cannot introduce a loosening path. Policy fields stay local until equivalent guards are designed. |
| Delete versus offline edit | Tombstone wins in normal reads. Retain the edit for explicit recovery as a new identity, never resurrection of the deleted id. |
| Duplicate category/tag names from two installations | Preserve both IDs. Require an explicit merge/rename with reference rewriting in one transaction. Do not discard one because its display name matches. |

Persist tombstones for steps and membership removals before transport can observe those entities. Include task/category tombstones even though their rows already have deletedAt. Tombstones remain until every registered replica acknowledges the deletion or that replica is explicitly retired. A returning retired device performs a fresh bootstrap and cannot upload its old state. A plain CloudKit record deletion without a durable application tombstone is insufficient for an arbitrarily old offline writer.

Never purge a task's original sessions to solve a conflict. Session corrections, sleep trims, and reflection updates need revisions that cannot apply the same adjustment twice. Aggregates are rebuilt from accepted source records. Do not synchronize mutable cached totals as another authority.

## Timer ownership and account changes

The primary's local partial unique index continues to enforce one timer across the app, CLI, and MCP. Companions have no write path into that timer. A future remote command includes command id, expected primary generation, session id, and expected session revision. The primary validates and records its result atomically. The caller displays pending until it reads that result. Retrying one id returns the same result. Finishing an old session cannot finish a newer timer.

Ownership transfer requires the old primary online, quiescent, fully uploaded, and explicitly relinquishing ownership before the new primary gains it. Offline force-takeover is excluded from the first implementation. If later added, it must clearly permit conflict on reconnection and preserve both session histories for resolution; it cannot promise global exclusivity.

On sign-out or account change, stop the engine and publication immediately. Retain the local database and unsent changes in their original account partition. Clear only credentials and in-memory account access. Never upload account A's outbox to account B. A new account starts its own explicit pairing/import flow. Returning to A resumes its own checkpoint after identity validation. Permission revocation becomes a paused sync state. Local planning continues.

A device returning after zone deletion performs an explicit restore/import choice. It must not republish all old rows automatically and undo a user's cloud deletion. A visible local backup/export precedes any destructive reset. Disabling sync stops network work and leaves local data intact. Deleting cloud data is a separate confirmed action outside the scope of enabling/disabling sync.

## Platforms and permissions

Apple's live documentation was read on 2026-11-03. [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5) is available from macOS 14, iOS/iPadOS 17, and watchOS 10. It requires CloudKit and remote notifications entitlements. Its schedule is indeterminate and its opaque state must be persisted. The existing macOS 26 minimum is above that API minimum, but the current ad-hoc SwiftPM bundle has no CloudKit provisioning or entitlement setup. Runtime availability is not signing readiness.

The future Mac slice requires a registered app identifier, private iCloud container, CloudKit service entitlement, remote notification capability, correct development and distribution provisioning, and development/production CloudKit schema deployment checks. Use a signed test target and test account, not the installed production app. No credentials or Apple portal access are needed to review this design.

[WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity) connects an iPhone app and its paired Watch app. It is not direct Mac-to-Watch transport. The read-first companion therefore depends on the iPhone slice and handles delayed/background transfer explicitly.

[Family Controls](https://developer.apple.com/documentation/familycontrols) is a separate iOS/iPadOS capability. [Distribution entitlement approval](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) is required for the app and applicable Screen Time extensions. Individual authorization, privacy-preserving selection tokens, revocation, DeviceActivity, and ManagedSettings need a separate real-device investigation. The Mac blocker cannot enforce iPhone restrictions by copying its rules. A user's phone is never blocked merely because Mac sync was enabled.

## Ordered implementation backlog

| Slice | Scope and dependencies | Acceptance and remaining external checks |
| --- | --- | --- |
| S1. Local sync preparation | Add account partition/device identity, durable outbox, record metadata, and missing tombstones. Audit all current migrations, including this run's additions. No network. | Upgrade populated old fixtures, retry writes, remove steps/tags offline, and recover after injected crash. All existing Store/protocol tests still pass. |
| S2. Private Mac replica | Depends on S1. One writing Mac, one read-only Mac, opt-in CKSyncEngine, status/error UI. | Real signed builds and two Macs on a test account. Offline edits, duplicate delivery, throttling/quota, sign-out, account switch, zone deletion, relaunch, and rollback. Source/replica records and totals agree. |
| S3. Read-first iPhone | Depends on S2 record contract. Today, task/session history, and stale timer snapshot. No editing or timer start. | Physical iPhone, denied/offline account, background fetch limits, accessibility, date/time-zone changes, and sign-out isolation. |
| S4. Read-first Watch | Depends on S3. Compact Today/timer snapshot through paired iPhone. | Physical paired Watch and phone, stale/offline transfer, reconnection, small screen, complications if separately selected. |
| S5. Remote focus commands | Depends on S2 and explicit owner transfer/command protocol. No offline independent timer. | Duplicate commands, stale session ids, newer timer, owner unavailable, account change, and acknowledged transfer across two signed devices. |
| S6. Two-way Linear | Independent opt-in scope after a mapping design. Keep the existing link-only behavior until then. | Define issue-to-task mapping, field owners, OAuth scopes, webhook signature verification, pagination, rate limits, idempotency, deleted/private issues, conflicts, and audit logs. Test workspace required. No auto-close of issues from a local timer. |
| S7. iOS Screen Time | Depends on iPhone app and separate entitlement approval. Start with explicit personal-device authorization and one bounded selection. | Distribution approval, physical device, denial/revocation, schedule termination, reboot, extensions, and restoration. No claim based solely on simulator behavior. |

S1 and S2 are the recommended first implementation request. Two-way record editing follows only after the conflict policy has its own acceptance scope. Each slice gets its own ticket and review before production activation.

## Migration, rollback, and alternatives

Use additive local migrations and retain existing IDs. Back up the database through SQLite's backup API before the first sync migration. Never copy a live database file without its WAL. Test from every supported upgrade fixture, including v10 and the final non-calendar schema. A minimum compatible sync-schema version prevents an older binary from consuming records it cannot preserve. An unsupported client remains locally usable only if its local schema is compatible; it must not overwrite newer fields on the cloud.

Ship sync disabled first. A feature disable stops the engine without deleting metadata or user records. Roll back by disabling transport and returning to the last compatible binary. Restoring an old database is a separately confirmed data-loss operation and requires reconciliation of unsent changes. Cloud schema changes remain additive while any older supported client exists. Do not drop fields or tombstones during a client rollback.

Direct SQLite file synchronization was rejected because WAL, simultaneous writers, and device-local process state make the file an unsafe synchronization unit. A custom server was deferred because CloudKit fits private Apple-device data without adding server operations. SwiftData/iCloud replacement was rejected because it would replace the existing GRDB Store and its transaction guards. General multi-writer offline CRDTs were deferred because plan limits, close rules, and timer ownership need product decisions beyond text merging. A read-first replica proves useful cross-device visibility while preserving current invariants.

Discovery closes only after a fresh reviewer challenges deletion resurrection, competing timers, offline edits, account switching, and the final schema audit. It does not close S1 through S7 or prove live CloudKit behavior.
