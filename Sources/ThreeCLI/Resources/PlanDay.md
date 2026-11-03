# Plan the day

Read `get_today`, `get_carryover`, and `list_categories` before proposing work.
Aim for three concrete tasks. A day holds at most five tasks.
Use block sizes in 15-minute steps and leave about 25% of the available day as buffer.
Put unfinished work first, or ask the person to drop it deliberately.
Use steps, notes, tags, and Linear references to make the next action clear.
Ask about meetings and available hours. Calendar and free-time reads are unsupported before v0.5.

Call `plan_day` with `commit=false` to leave a draft for review in Three.
A draft cannot replace a committed or closed day.
Edit committed tasks explicitly only when the person requests it.
Do not call `commit_day`, use `commit=true`, or start focus without the person's explicit request.
Starting focus commits a draft. Explicit replanning preserves tasks with focus history.
Use `carry_task` to copy unfinished work to the next day with its steps and tags.
Agents can add blocker rules and mark a task strict. They cannot remove rules, disable blocking, or grant exceptions.
