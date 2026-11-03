# Review a proposed day

Three stores an agent proposal as an ordinary `DayPlan` with `draft` status.
The app and MCP server share the same Store operations and database.

## Connect your agent

1. Build the app with `./scripts/bundle.sh`.
2. Open Settings, then Connect.
3. Copy the Claude JSON or Codex TOML entry into your client's MCP configuration.
   The entry uses the app's bundled helper, so the optional CLI symlink is not required.
4. Copy the Codex prompt or the Claude plan-day skill from Connect.
   If you choose to install the skill, save it as `plan-day/SKILL.md` in your client's skill directory.
5. Ask your agent to plan the requested day with your priorities and available work time.

Three writes no agent configuration automatically. Moving the app changes its helper path, so copy the connection entry again after moving it.

## Review and commit

1. Open Today. The draft line shows the saved source, task count, and total block duration.
   MCP is the recorded source for any MCP client. Three does not infer a model or harness name.
2. Click the pencil beside a task to edit its title and block duration.
   Click its title to open steps, tags, and notes. Notes save after you stop typing.
3. Drag task title rows to reorder them, or use Move Up and Move Down in the card menu or Edit menu.
4. Open the ellipsis menu and choose Drop task to leave that task out of the commitment.
5. Press Commit when the plan is ready.

Starting focus is also an explicit commitment and commits a draft.
Edits and commit failures appear in the app's error note. A failed save leaves the task editor open.
An MCP draft cannot replace a committed or closed day. Commit never reopens a closed day.

## Decide what to do with unfinished work

Today offers unfinished tasks from earlier dates. Reading the offer changes nothing.

- Choose Accept today to copy the work into today's plan and mark its earlier record carried.
- Choose Dismiss to mark the earlier task dropped without adding work today.
- Leave the offer alone to decide later.

Acceptance keeps steps and their checked state, tags, strictness, the Linear reference, and notes.
Prior focus time stays on the original task. The copy starts with no focus time or scheduled start.
The Store refuses acceptance when the task is running, either day is closed, the destination is not later, or today's five-task cap is full.
Repeated acceptance is refused. Failures change neither day.
Closed source days remain immutable and can produce an error when an old offer is selected.

The MCP `carry_task` operation targets the day after the source date. It does not accept a destination date.
Use the app's Accept today for older tasks. The app and MCP carry paths use the same transaction and copy logic.

## Use the canonical planning guide

[`Sources/ThreeCLI/Resources/PlanDay.md`](../Sources/ThreeCLI/Resources/PlanDay.md) owns the planning rules.
The MCP server publishes that file at `three://plan-day-guide`.
The bundled Claude skill and Codex prompt read that resource on every run.

The guide requires three tasks, sensible 15-minute increments, about 25% buffer against stated work time, explicit carry-over disposition, and `plan_day` with `commit=false`.
Accepted work is edited in place instead of replaced with a new proposal.
Before v0.5, there is no meeting cache, free-time calculation, or calendar write.
The agent asks for missing availability and does not invent meetings or a schedule.
Scheduled harness execution belongs to BPRO-399.

The harness owns Linear reads and updates through its own tools.
Three displays an HTTPS `linear.app` issue URL as a clickable issue reference.
A bare identifier or an unsupported URL remains selectable text. The app makes no Linear API calls.

## Verify the implementation

Run the following commands from the prepared worktree.

```sh
./scripts/lint-design.sh
./scripts/swift.sh test --filter 'DraftReviewTests|Carry|carry|pushToTomorrow|TodayOrderTests'
./scripts/bundle.sh
python3 scripts/test-mcp.py --binary build/Three.app/Contents/Helpers/three
python3 scripts/test-draft-review.py --app build/Three.app
```

The draft-review script copies the built app to a temporary location with a space in its path.
Its bundled helper reads the guide from the copied `Three_ThreeCLI.bundle` in `Contents/Resources`.
The script creates a draft over real MCP stdio, runs edits, reorder, drop, and explicit commit through the app's Store API, then reads the result through MCP.
All database writes use temporary scratch paths. The script runs no focus timer or desktop automation.
This proves the shared data path and resource packaging. It does not prove native human acceptance.

Native QA must still check the ordinary Today flow, narrow panes, keyboard and VoiceOver controls, drag ordering, visible errors, Linear link opening, and Connect copy actions.
Only the parent or assigned desktop owner can grant and record that native acceptance.
