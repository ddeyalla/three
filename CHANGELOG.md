# Changelog

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
