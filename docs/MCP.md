# Three MCP reference

`three mcp` serves local MCP over newline-delimited JSON-RPC on stdin and stdout. It uses the official [Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk) pinned to `0.12.1`. The MCP API version is `1.0.0`, independent of the app release version. The server has no network listener, subprocess CLI adapter, model calls, or calendar permissions.

The app, CLI, and MCP share the same SQLite Store. `THREE_DB` selects another database. Each successful Store write posts the existing Darwin change signal that the app observes. Timer tools launch Three in the background when necessary, except when `THREE_DB` is set. Sounds, notifications, and app blocking still need the native app.

## Client configuration

Replace `/Users/YOUR_NAME/.local/bin/three` with the absolute path to the installed binary. A client does not expand `~` in a command path.

Claude Desktop, Claude Code, and clients with `mcpServers` use this JSON.

```json
{
  "mcpServers": {
    "three": {
      "command": "/Users/YOUR_NAME/.local/bin/three",
      "args": ["mcp"]
    }
  }
}
```

Codex uses this entry in `~/.codex/config.toml`.

```toml
[mcp_servers.three]
command = "/Users/YOUR_NAME/.local/bin/three"
args = ["mcp"]
```

For an isolated client, add `"env": {"THREE_DB": "/absolute/scratch/three.sqlite"}` to the JSON server entry. The equivalent Codex setting is `env = { THREE_DB = "/absolute/scratch/three.sqlite" }`. These configurations change which database the tools edit.

## Input conventions

`tools/list` publishes the complete JSON Schema for every tool. Every tool argument object rejects unknown fields. Optional fields must be omitted rather than set to `null`. Values are type checked without coercion. Task IDs are exact Store UUIDs. Positions and ID prefixes accepted by the human CLI are unsupported in MCP.

Dates accept `today`, `tomorrow`, `yesterday`, or a real local date in `yyyy-MM-dd` format. Session timestamps and output dates use ISO 8601. `scheduled_start` requires a real calendar date, seconds, optional fractional seconds, and either `Z` or a `±HH:mm` timezone offset. It does not accept `24:00` or leap seconds. Categories accept an existing category's ID or case-insensitive name.

A new task has these fields.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `title` | string | yes | Nonempty after trimming whitespace. |
| `category` | string | yes | Existing category name or ID. |
| `block_minutes` | integer | yes | 5 through 480 minutes. |
| `scheduled_start` | string | no | ISO 8601 timestamp. |
| `strict` | boolean | no | Defaults to false. |
| `linear` | string | no | Optional issue reference. No remote lookup occurs. |
| `notes` | string | no | Defaults to empty. |
| `tags` | string array | no | Names. Store creates missing tags. |

## Tools

A `?` marks an optional field. All other fields are required unless a row says otherwise.

| Tool | Fields | Result and behavior |
|---|---|---|
| `get_today` | none | Today's day object. |
| `get_day` | `date` | A day object, including an empty day without a plan. |
| `plan_day` | `date`, `tasks`, `commit?` | `{day, warnings}`. `tasks` is an array of zero through five new tasks. `commit` defaults to false. More than three counted tasks produces a warning. |
| `commit_day` | `date` | `{ok:true}`. Commits an existing draft. It does not write calendar events. |
| `add_task` | `date`, new task fields | The created task record with `createdBy=mcp`. |
| `update_task` | `id`, `title?`, `category?`, `block_minutes?`, `notes?` | `{ok:true}`. Other create fields are unsupported for updates. |
| `remove_task` | `id` | `{ok:true}`. Deletes an untouched task or drops a worked task. Stops its running session. |
| `move_task` | `id`, `index` | `{ok:true}`. Zero-based integer index at least zero. Larger indices append. |
| `set_task_status` | `id`, `status`, `note?` | `{ok:true}`. Status is `todo`, `done`, `partial`, `dropped`, or `carried`. `note` replaces task notes. Active status requires `start_focus`. |
| `carry_task` | `id` | The new task record on the original plan's next day. Copies steps and tags. Marks the original `carried`. Refuses running tasks. |
| `schedule_task` | `id`, `date` | `{ok:true}`. Moves a task. Also accepts `date=inbox`. Does not copy it. |
| `list_categories` | none | Category records, including archived categories. |
| `upsert_category` | `id?`, `name?`, `color_hex?`, `archived?` | Without `id`, requires `name` and `color_hex` and returns a new active category. With `id`, edits the existing category and returns `{ok:true}`. Colors use `#RRGGBB`. Cannot archive the last active category. |
| `start_focus` | `task_id?`, `minutes?` | The new session record. Without ID, uses the next open task today. Minutes range from 1 through 480. Store defaults apply when omitted. |
| `pause` | none | `{ok:true}`. Repeating pause on a paused timer is harmless. |
| `resume` | none | `{ok:true}`. Repeating resume on an unpaused timer is harmless. |
| `stop` | none | `{ok:true}`. Ends a timer without reflection. A focused task becomes partial. |
| `extend` | `minutes` | `{ok:true}`. Adds 1 through 480 minutes. An overrun extends from now. |
| `start_break` | `minutes?` | The new break session. Explicit minutes range from 1 through 120. |
| `finish_focus` | `outcome`, `rating`, `mark_task_done`, `note?` | `{ok:true}`. Outcome is `done`, `progress`, or `stuck`. Rating is 1, 2, or 3. `mark_task_done` is a boolean. Records reflection and ends focus without continuation. |
| `get_status` | none | The running timer summary or `null`. Includes `remainingSeconds`, which is negative during overrun. |
| `get_carryover` | `date` | Task rows for unfinished planned tasks before the given date, oldest day first. Undated inbox tasks are excluded. Reads do not move tasks. Closed-day work remains read-only. |
| `get_history` | `from`, `to` | Session records, including reflections. Inclusive local start dates. The range must be ordered and span at most 366 days. |
| `get_block_status` | none | The existing CLI blocker status object, including reason, rules, focus hours, hits, exceptions, browser connections, and coverage limits. |
| `add_block_rule` | `kind`, `value` | Blocker status after adding or re-enabling a rule. Kind is `domain` or `app`. A repeated domain may return its covering parent rule without adding a duplicate. |
| `set_task_strict` | `id` | `{ok:true}`. One-way change to strict. Repeats are harmless. No false parameter exists. |

The five-task ceiling counts every live task except dropped and carried tasks. The Store checks additions, moves between days, carry-over, replanning, and status changes inside write transactions. Dropping a task frees a slot. Reopening it requires another free slot. A carried task cannot reopen because its copy already exists.

A draft `plan_day` refuses committed and closed plans before changing rows. Explicit `commit=true` replanning can replace untouched tasks on a committed day, while tasks with session history remain. Those retained tasks count toward five. A closed day cannot be edited or reopened. Starting focus commits a draft. Only one timer runs at a time. A focus start can end an existing break, but cannot replace another focus session.

An upgrade normalizes date spellings accepted by older CLI versions. If two stored spellings identify one day, it retains the canonical plan ID when possible and merges tasks without losing sessions, steps, or tags. The more restrictive live plan status wins. A historical collision can expose more than five existing tasks. No task is discarded or moved automatically, and new admissions remain blocked until there is room. Removing a carried original is refused so its copied work cannot be duplicated by reopening it. Checklist and tag edits also respect closed and deleted tasks.

Mutations are not globally replay-safe. Repeating `add_task` creates another task. Repeating a draft `plan_day` replaces untouched rows with new IDs. Read the result after an uncertain write before retrying. The Store makes each write atomic and preserves session history. It does not provide a client idempotency key.

## Results and resources

Successful tool results contain one text content item with JSON and `isError=false`. Output object keys use the Store's existing camelCase names. Input tool fields use snake_case as listed above.

A day object contains `date`, `plan`, `tasks`, `sessions`, `running`, `runningTask`, `takenAt`, and `plannedMinutes`. Optional nil properties are omitted. Each task row contains its complete `task` and `category` records, `focusedSeconds`, `steps`, and `tags`. `plan.source` and `task.createdBy` preserve provenance. Dropped and carried rows remain available in these reads.

`get_status` returns `id`, `kind`, optional `taskId`, `startedAt`, `plannedEnd`, `paused`, and `remainingSeconds`. A session returned by history or a timer mutation contains the Store session fields, including optional `outcome`, `focusRating`, `note`, and the `reflectionPending` flag.

`resources/list` publishes two resources. `three://today` returns the same JSON day object as `get_today`. `three://plan-day-guide` returns the bundled `Resources/PlanDay.md` as markdown. Resources have no subscriptions or change notifications. Read them again after edits.

## Errors and unsupported operations

Tool failures return `isError=true` with one text item containing `{code,message}`. Domain error messages are at most 512 characters. Unexpected failures return a generic message and write a fixed diagnostic to stderr. Request contents and database errors are not logged. Stdout contains protocol messages only. SDK transport logging stays disabled.

| Code | Meaning |
|---|---|
| `invalid_input` | A field has the wrong type or value, a required field is missing, an unknown field is present, or a lifecycle guard refuses the change. |
| `too_many_tasks` | The write would exceed five counted tasks. |
| `no_such_task` | The exact task ID is missing or deleted. |
| `no_such_category` | The category does not exist. |
| `no_running_session` | The timer operation has no applicable running session. |
| `already_running` | A focus timer already runs. |
| `nothing_to_start` | No open task exists today. |
| `block_rule_error` | A domain or bundle ID is invalid, unsupported, or exceeds the existing rule limit. |
| `unknown_tool` | The tool does not exist or is unsupported. |
| `internal_error` | An unexpected Store or encoding failure occurred. |

Invalid `tools/call` or `resources/read` parameter envelopes return JSON-RPC `-32602`. An unknown resource also returns `-32602`. The SDK handles malformed JSON with `-32700` and unknown methods with `-32601`. SDK `0.12.1` uses a generated response ID when malformed input has no recoverable request ID. Resource read failures return `-32603` without database details.

`get_meetings`, free-time calculations, calendar writes, `get_stats`, and `block_now` are unsupported. `get_history` provides existing session and reflection data. It does not invent a trend model. Manual timed blocking has no Store lifecycle, so no tool exposes it. There are no blocker removal, disable, exception, rule replacement, focus-hours reduction, or strictness-loosening tools. Human blocker controls remain in the app.

## Verification

The standalone protocol check builds no app window, launches no installed app, and uses a disposable `THREE_DB` under this checkout's `build` directory.

```sh
./scripts/swift.sh build --product three
python3 scripts/test-mcp.py --binary "$(./scripts/swift.sh build --show-bin-path)/three"
./scripts/swift.sh test --filter ThreeCoreTests
```

The script verifies real initialize, list, call and resource messages; malformed and unknown input; repeated reads; persistence across restart; cross-process CLI reads and writes; the Darwin signal used by the app; transaction rollback; two-server five-task and timer admission; focus controls; category edits; carry-over with steps and tags; and tightening-only blocker operations. It does not prove a native window refresh, physical menu bar, notification delivery, Chrome redirects, or app hiding.

SwiftPM builds `Three_ThreeCLI.bundle` beside `three`. Distribution must preserve that resource bundle beside the CLI or in the bundle resource location. BPRO-398 owns app packaging and installation of the canonical planning guide.
