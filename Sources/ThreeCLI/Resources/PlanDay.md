# Plan the day

Read this guide for every planning run. It is the canonical instruction for Claude, Codex, and other harnesses.

1. Read `get_today`, `get_day` for the requested date, `get_carryover`, and `list_categories`.
   If the target day is committed or closed, stop and report its state. Never replace an active plan with a draft.
   Edit committed tasks only when the person requests those edits. Do not replan with `commit=true` to bypass this guard.
2. Establish the person's available work time and priorities from their request or ask them.
   Before v0.5, Three has no meeting cache or free-time tools. Do not invent meetings, calendar access, free time, or scheduled start times.
   If work time is unknown, propose block lengths without claiming the day fits.
3. Review every unfinished task. Ask the person to accept it, dismiss it, or leave it for later.
   If no decision is available, leave that task unchanged and report it as deferred.
   Reading carry-over changes nothing. Never silently move, copy, drop, or recreate unfinished work in `plan_day`.
   Prefer acceptance or dismissal in Three before proposing the remaining work, then re-read the target day.
   `carry_task` copies to the day after the source day, not any requested date. Use it only with explicit approval for that destination.
   The app's Accept today supports older tasks. Both paths preserve steps, tags, strictness, Linear references, and notes, and refuse running tasks or closed days.
   After acceptance, use `add_task` or `update_task` for the remaining proposal. Do not replace accepted rows with `plan_day`.
4. Aim for three concrete tasks in total, including accepted carry-over. Five is the ceiling, not the target.
   Use sensible 15-minute block increments, usually 30, 45, 60, or 90 minutes.
   Leave about 25% of the stated work time as buffer. Reduce scope if the blocks exceed the remaining 75%.
   Use existing categories. Add tags and notes that make the next action clear.
   Put a verified Linear issue URL in `linear`, such as `https://linear.app/workspace/issue/ENG-123`.
   Your harness owns any Linear reads or updates through its own tools. Three makes no Linear API calls.
5. For a new proposal, call `plan_day` with `commit=false` explicitly.
   Replacing an existing draft removes untouched tasks, so review its contents first and preserve requested work through edits when appropriate.
   Re-read the saved day. Check its source, task count, total duration, carry-over disposition, and the buffer against stated work time.
   Report what needs human review in Three, plus any unresolved input or tool error. Stop after the draft.

The person reviews, edits, reorders, or drops tasks in Three and presses Commit.
Do not call `commit_day`, use `commit=true`, or start focus unless the person explicitly requests that action.
Starting focus commits a draft. A draft cannot replace a committed or closed day.
Calendar writes are unavailable before v0.5. Commit currently records the commitment locally.
Agents can add blocker rules and mark a task strict. They cannot remove rules, disable blocking, or grant exceptions.
