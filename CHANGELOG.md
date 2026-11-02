# Changelog

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
