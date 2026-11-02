# Changelog

## Unreleased

- After two minutes without an answer or edit, the reflection panel saves Made progress and Okay, keeps any note, ends the block, and hides. A pulsing menu-bar dot reminds you to review or dismiss it. Saved reflections survive relaunch, and editing one leaves newer timers alone. Reduce Motion keeps the dot still.

## 0.2.4 — 2026-11-02

Three panes instead of a sidebar, tags that add up time across weeks, and a calmer end-of-block panel.

**What looks or works differently**

- **Three panes.** Tasks on the left, the dial in the middle, the day's timeline on the right. The sidebar is gone. A row of glass capsules at the top of the left pane switches between Today, Inbox, Upcoming, Done (✓) and Tags (#). ⌘1 to ⌘5 do the same.
- **Categories live in Settings → Categories.** They no longer take up the window. Their colours still mark every task.
- **The dial goes past an hour.** It used to stop at 60 minutes because one turn is an hour. Keep dragging past 12 o'clock to add an hour, up to 4 hours. Each extra hour shows as a ring around the face, and the wedge shows the current hour. The Block menu now offers 3h and 4h.
- **Tags.** Type `@name` in quick add (`Fix signup bug @onboarding 30m`) or use "Add a tag" on an open card. A tag is a thread of work that runs for days or weeks, such as a product, project or feature. Tags is the place to see how much time each one has taken: the total, the past week, how many days, and each task's share. A task carried to tomorrow keeps its tags, so its time keeps counting. Right-click a tag to archive it when the work is finished.
- **Done.** Everything you finished in the last 30 days, by day, with the time each task took.
- **The reflection panel is rebuilt.** Each question sits above its answers as glass capsules instead of beside a cramped segmented control. The note field no longer lights up with a focus ring. There is one prominent action, which names the break length ("Start 5m break"). "15 more minutes" keeps the block going, and Esc or the × closes the panel.
- The task the dial is about now shows its category, tags and steps under its title.

**For the command line**

- `three tags` lists every tag with its time (`--json`, `--all`). `three tags add 2 onboarding`, `three tags remove 2 onboarding`, `three tags rename`, `three tags archive`.
- `three capture` reads `@tags`, and `three add` takes `--tag`.
- `three logbook [--days 30]` lists finished tasks.
- Task JSON now includes `tags`.

## 0.2.3 — 2026-11-02

A design guideline, and a type and spacing pass to match it.

- **[DESIGN.md](DESIGN.md)** sets the rules: SF Pro only, compact density, Liquid Glass for every surface, and colour only for a category, the current time or an overrun.
- **Six type roles replace nine sizes.** The time left (48pt light) is now the largest thing on Today, ahead of the page title (22pt bold). Below those come the task the dial is about (15pt semibold), section headings and body (13pt), and detail lines (11pt). Selecting or running a task no longer changes its font weight, so its title stops shifting.
- **One spacing scale** (2, 4, 8, 12, 16, 24, 32) replaces thirteen ad hoc values. Cards, the quick-add field and controls are a little more compact.
- The menu bar uses the same roles as the window, including the same timer readout.
- Short blocks on the timeline now show their task and duration.
- `make test` fails if a view sets a font size or text style directly instead of using a role.

## 0.2.2 — 2026-11-02

A cleanup after a full review of the app. The window loses its chrome, and a long list of rough edges is fixed.

**What looks or works differently**

- **No top bar.** The title bar, toolbar band and the two side-by-side sidebar toggles are gone. The window opens without a cursor blinking in a text field.
- **No inspector.** The right-hand column and ⌘I are gone. The running or selected task shows its steps and notes in place. In Inbox, Upcoming and categories, click a task's title row to open it.
- **Double-click no longer starts a task.** Click to select, then press Start (⌘↩), or use Start now in the task's menu. Clicks select straight away, with no double-click delay.
- **Unfinished tasks from earlier days wait in the Inbox**, oldest first, instead of disappearing from the app.
- **Quick add reads the day and length only at the end.** "Email Tom about invoice" stays as typed. `tom`, `sun`, `sat` and `later` no longer count as days; use `tomorrow`, `sunday`, `saturday` or `someday`. The preview shows the title it will save.
- **Errors show wherever you are**, as a banner at the bottom of the window, in the menu bar and in the reflection panel.

**Fixes**

- Starting a task other than the selected one runs for its own length, not the length on the dial.
- Deleting the running task stops its block. Before, the timer kept going and the task came back when it ended.
- The reflection panel has Cancel, and Escape closes it. It also closes itself if you add time from the window, the menu bar or the CLI.
- Quick add never clears text it couldn't use, and asks for a title when there isn't one.
- Move up and Move down work when a dropped task sits between others.
- Pushing a task to tomorrow keeps its steps. A task already moved to tomorrow can't be scheduled a second time, and a done task stays done when moved.
- Clicking a step or the notes no longer collapses the card you're working in.
- A length you dragged on the dial resets when the selected task changes.
- The running task's progress (`22 / 60m`) counts up live.
- ⌘N focuses the quick-add field even when it switches views. "Break it down" puts the cursor in the new step's field.
- The timeline draws planned blocks only for open tasks on that day.
- A "Time's up" notification left over from before a relaunch is cleared.

## 0.2.1 — 2026-11-02

- Marking a running task done now ends its block, recorded as done; other ways of closing a task end it as stopped. Before, the task could close while its timer kept running. Existing blocks stuck that way are closed at the moment they were paused.
- The timeline draws a paused block only up to where it paused, instead of stretching it to now.

## 0.2.0 — 2026-11-02

Plan and capture. Three becomes a place for everything you mean to do, while each day stays at three.

- **Sidebar** with Today, Inbox, Upcoming and your categories. It uses native Liquid Glass. ⌘1, ⌘2 and ⌘3 switch views.
- **Inbox.** Capture anything without giving it a day. Inbox tasks don't count toward the five-task cap. Hover a task to send it to today or tomorrow, or use Schedule in its menu for any day this week.
- **Quick add**, Todoist style: `Renew passport #admin 30m fri`. `#category` matches by prefix, a duration sets the block, and today, tomorrow, a weekday or `inbox` picks the day. A preview shows what it understood as you type. Press ⌘N anywhere. There's also a capture field in the menu bar.
- **Upcoming** shows the next seven days, each with a count against three.
- **Steps.** Break a task into small checkboxes. They show inline under the running or selected task, so the next step is always in view.
- **Task inspector** (⌘I) for title, category, block, day, steps and notes.
- **Settings** (⌘,):
  - Timer defaults, stored in the database so the CLI uses them too.
  - Category add, rename, recolour and archive.
  - Connect: install the CLI, plus instructions to paste into CLAUDE.md or AGENTS.md.
  - The chime can be turned off.
- **Glass is back** on task cards, the dial face and knob, the controls and timeline blocks, over a backdrop tinted by the current task's colour.
- **Today layout.** The timer and tasks sit centred under the header instead of stacking at the top. The timeline opens scrolled to now.
- **Reflection panel** appears centred over the window rather than at the top of the screen. The overrun line reads "Ended 5:00 PM" instead of "Over by 0m".
- **CLI:** `capture`, `inbox`, `schedule`, `upcoming`, `step add|done|remove`, `categories add|rename|color|archive` and `settings`.
- **Roadmap renumbered.** The blocker moves to v0.3, AI/MCP to v0.4, calendar to v0.5 and record to v0.6.
- Recurring tasks and priorities are left out on purpose for now. Today's three already are the priority list.

## 0.1.1 — 2026-11-02

A design pass toward a quiet, native Mac app: solid surfaces, colour only where it means something, one deliberate motion.

- **Tasks are a calm list, not glass cards.** Each row has a completion circle in its category colour (the one way to mark a task done), the title, and `18 / 60m` progress. The selected row gets a quiet fill, and the running row a tint of its colour. Progress rings, coloured side bars and the "NOW" badge are gone.
- **The timer comes first.** The current task, dial and time left sit above the plan. The readout counts down in SF Pro with tabular digits, with start → end as plain text and "Over by 4m" past zero.
- **Dial.** Faint minute ticks, quiet five-minute marks, a flat wedge and a small centre dot. When a block starts, the wedge sweeps open over 0.7s (skipped with Reduce Motion). That sweep is the app's one authored animation.
- **Type.** System text styles in sentence case replace the monospace caps labels. No eyebrow headings, and no text below secondary contrast.
- **Timeline.** It scrolls to now when it opens, as Calendar does. Blocks use a tinted fill with text in the same hue. The now marker is a red dot, line and time in the gutter, and the hour label beside it hides.
- **Reflection panel.** Native segmented controls replace the emoji chips. "Shorten" and "Tomorrow" move into a menu, and Return starts the break. The panel no longer takes keyboard focus when it appears, so it can't swallow what you're typing in another app.
- **Calmer category colours** at matched lightness. Existing installs migrate only colours that are still at their defaults.
- Removed the decorative accent wash behind the window and the staggered list entrance.

## 0.1.0 — 2026-11-02

The core loop, usable daily.

- **Today screen.** Up to five tasks with category colour, block length and status, plus an inline composer. It warns above three tasks and refuses a sixth.
- **Dial timer.** One turn is an hour. Drag to set the length in 5-minute steps while idle. Shows start → end time, and counts up in orange past zero.
- **Reflection panel** at the end of each block. It asks how it went (done, made progress, stuck), how focused you were, and what's next. "What's next" can switch tasks, shorten a block or push a task to tomorrow. Then start a break, skip it, or add 15 minutes.
- **Breaks.** 5 minutes, or 15 after about 100 minutes of focus. A break closes itself at its planned end.
- **Day timeline.** An hour grid with finished sessions, breaks, the running block's planned box and a "now" line.
- **Menu bar** with the current task and time left, plus a popover with controls and today's list.
- **Notifications** at block end and break end.
- **`three` CLI** for plan, add, start, pause, resume, extend, stop, done, drop, tomorrow, status and categories, with `--json`.
- **Local SQLite store** shared by the app and the CLI. Changes reach the app live through a Darwin notification.
- **Seeded categories:** Coding, Writing, Admin, Learning, Meeting prep.
