# Scheduled planning

Three runs one trusted local command to propose today's draft. Scheduling is off by default. The default local planning time is 09:30.

## Design and ownership

Two designs were considered before implementation.

| Design | Ownership and consequences |
| --- | --- |
| Native app with SQLite claims | Uses AppModel's existing tick and wake notifications. The app owns process execution, Settings, and notifications. SQLite coordinates app instances, Test, and MCP. The bundled helper supervises each command. No extra service or scheduler is installed. |
| A launchd job invoking a separate runner | Can run without the app, but introduces installation, service lifetime, permissions, and separate notification coordination. It duplicates the app's existing wake path. |

The native app design fits PRODUCT section 10. `PlanningSettings` uses the existing preference table under key `planning`. Migration `v9-scheduled-planning` adds `planningRun`. Migration `v10-planning-supervisor` records its helper owner. Existing timer preferences and plans remain unchanged.

The implementation uses three verifiable units. First, prove the claim, restricted draft transaction, and bounded runner against scratch databases. Second, connect the existing app loop and Settings to those operations. Third, prove the packaged MCP path and native Test controls. Independent integration review belongs to the parent task.

## Configure and run

1. Open Settings, then Planning.
2. Set the local time in `HH:mm` format.
3. Keep the Codex default or enter a command you trust.
4. Set Scheduled planning as desired, then click Save. The switch, time, and command save together.
5. Click Test to save the complete form and run immediately, including when automatic scheduling is off.
6. Inspect Last run, stdout, stderr, and any error. Review a successful draft in Today and press Commit yourself.

Test also works while automatic scheduling is off. It uses the same claim and limits. It can explicitly retry a failed, timed-out, cancelled, or interrupted attempt when no plan or active run exists. Test preserves existing work, including empty draft, committed, closed, and deleted plan records. It does not start a timer.

The shell command has your account's access. It can modify files, use credentials, invoke another CLI, and contact external services. Three does not sandbox it or roll back external actions. Only configure commands you trust. Cancel stops the process group Three owns. A command that deliberately escapes that group is outside this containment.

## Default Codex command

The saved default is:

```sh
codex exec --ignore-user-config --ephemeral --skip-git-repo-check --sandbox read-only --cd "$THREE_PLANNING_DIRECTORY" --config "$THREE_CODEX_MCP_CONFIG" "$THREE_PLANNING_PROMPT"
```

The runner uses your account's login shell with `-l -c`, so its startup files resolve PATH. It changes to your home directory before invoking the command. It closes stdin to prevent an unattended terminal prompt. The bundled helper path, database path, run UUID, and target date are supplied for that invocation. No CLI symlink, user MCP configuration edit, Node runtime, or Python runtime is required.

`THREE_CODEX_MCP_CONFIG` is a TOML override for `mcp_servers.three`. It uses the current app's `Contents/Helpers/three`, argument `mcp`, and explicit environment entries for the database, run, and date. `--ignore-user-config` keeps this invocation from inheriting broader user-configured MCP servers. Codex authentication remains Codex's responsibility. The default prompt reads `three://plan-day-guide` and requests a single draft for the target date. Missing planning context must be reported rather than invented.

The installed `codex exec --help` confirms these flags. Fixture commands prove the runner and MCP contract. No real authenticated Codex or Claude generation was run for this implementation. Model quality and account-specific authentication remain unverified.

## Run contract

Each run retains its UUID, local target date, trigger, command, status, start, deadline, finish, process group, exit status, stdout, stderr, error, draft plan ID, and notification claim. Attempt insertion order determines Last run, so clock rollback cannot hide a newer result. Run timestamps use numeric SQLite encoding so deadline comparisons retain their precision.

- Scheduled admission checks only the current local day. An app opened after planning time catches up once. It never replays a backlog of missed dates.
- Any prior attempt consumes automatic admission for that date. Failures are not retried each tick. Test is an explicit retry.
- One database transaction claims a run. A partial unique index permits only one `running` row across all dates and app instances.
- An active timer delays automatic admission. Test reports the conflict. A timer that starts after admission causes scheduled draft creation to fail atomically.
- Any existing plan prevents scheduled replacement. The Store checks again when the command tries to create its draft.
- A draft is created once, with `DayPlan.source=routine` and `Task.createdBy=routine`. The normal five-task cap and task validation still apply. It is never committed by this channel.
- Exit zero is successful only when the run's own draft still exists for review. Exit zero without a draft is a visible failure. A draft left by a failed command remains available for human review and is never silently removed.
- Each output stream retains its first 65,536 bytes. The runner continues draining both streams after the cap. Invalid UTF-8 displays replacement characters. Settings identifies truncated output.
- A continuous clock and the stored deadline bound execution to ten minutes. A local day change or backward clock jump before the run's start cancels the owned command. Work already saved remains for review.
- Native process spawning creates a new process group and suspends the child until SQLite records its ownership. Cleanup kills that owned group, including ordinary descendants. The unreaped leader prevents PID reuse until cleanup. The helper owns this loop and the final database result. The app keeps a control pipe open. Settings Cancel, normal app quit, or sudden GUI death closes the pipe, and the helper cancels its owned command group.

## Restart and uncertain state

The app never signals a PID recovered from SQLite. A live supervisor retains ownership even after its command group is gone, until it writes the final result. If the supervisor and recorded command group are both gone, the run becomes `interrupted`. It is not automatically retried. Existing drafts remain available, and Test still refuses to replace them.

If a recorded group still exists, or an app crash happened between claim and recording its group, the claim stays `running` and blocks every new planning command. Settings explains that process ownership is unresolved. A reused group ID may conservatively keep the claim blocked. An operator must establish that the old command and its descendants are gone before repairing such a row. There is no automatic unlock or unsafe force-retry button.

The bundled helper enforces the deadline independently of the GUI. GUI death also cancels the command through control-pipe EOF. Killing the helper itself or a machine failure can interrupt supervision. An uncertain outcome retains the durable claim and blocks further commands. No launchd watchdog is installed, and recovered PIDs are never signalled.

## Scheduled MCP policy

The protocol boundary recognizes scheduled mode only when both `THREE_PLANNING_RUN` and `THREE_PLANNING_DATE` are present. It requires a canonical UUID, a valid `yyyy-MM-dd` local date, and an absolute `THREE_DB`. Partial, malformed, unknown, expired, and completed claims fail closed.

The mode exposes only `get_today`, `get_day`, `plan_day`, `list_categories`, `get_status`, `get_carryover`, `get_history`, and `get_block_status`, plus the existing read resources. `plan_day` requires the exact target date and refuses `commit=true`. Hidden mutation tools are refused even if a client calls their names directly.

The Store validates the active claim, target local date, deadline, absent prior draft, absent existing plan, and absent running timer in the same write transaction. A second draft request is refused. The normal manual MCP channel remains available for a person's review and explicit commit.

This policy restricts the provided MCP channel. A trusted shell command can invoke another channel or manipulate files directly. The environment is not an operating-system security boundary.

## Notifications and visible results

A terminal attempt claims one notice per local day in SQLite before dispatch. A ready draft receives "Today's plan is ready". Otherwise the app sends one missing-plan nudge. Explicit retries do not repeat that day's notice. Committed or closed work and skipped runs receive no planning notice.

Planning notifications are immediate and use a `planning.<date>` identifier. Timer reconciliation removes only its own session identifiers. It cannot clear pending planning notifications. A denied notification permission or a dispatch failure does not erase Last run. Claim-before-dispatch favors no duplicate notice over guaranteed delivery after a crash.

## Verification

Run these commands from the prepared worktree:

```sh
./scripts/swift.sh test --filter 'ScheduledPlanningTests|ScheduledPlanningAppTests'
./scripts/bundle.sh
python3 scripts/test-mcp.py --binary build/Three.app/Contents/Helpers/three
python3 scripts/test-scheduled-planning.py --app build/Three.app
python3 scripts/test-planning-supervisor.py --binary build/Three.app/Contents/Helpers/three
make test
CONFIG=release ./scripts/bundle.sh
codesign --verify --deep --strict build/Three.app
```

The scheduled proof relocates the app to a path with spaces, invokes a local fixture through the native runner, and uses the packaged helper over real MCP stdio. It proves tool restrictions, per-run TOML, source, duplicate refusal, draft status, and normal-channel explicit commit. All writes use scratch databases. Python is a test fixture dependency only.

Native Settings Test, visible success and failure, and Today review require the assigned desktop owner. Evidence for this task is recorded separately after those checks. No fixture proves real authenticated model behavior.
