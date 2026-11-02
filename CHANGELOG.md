# Changelog

## 0.1.0 — 2026-11-02

The core loop, usable daily.

- **Today screen.** Up to five task cards with category colour, block length, progress ring and status, plus an inline composer. It warns above three tasks and refuses a sixth.
- **Dial timer.** One turn is an hour. Drag to set the length in 5-minute steps while idle. Shows start → end time, and counts up in orange past zero.
- **Reflection panel** at the end of each block. It asks how it went (done, made progress, stuck), how focused you were, and what's next. "What's next" can switch tasks, shorten a block or push a task to tomorrow. Then start a break, skip it, or add 15 minutes.
- **Breaks.** 5 minutes, or 15 after about 100 minutes of focus. A break closes itself at its planned end.
- **Day timeline.** An hour grid with finished sessions, breaks, the running block's planned box and a "now" line.
- **Menu bar** with the current task and time left, plus a popover with controls and today's list.
- **Notifications** at block end and break end.
- **`three` CLI** for plan, add, start, pause, resume, extend, stop, done, drop, tomorrow, status and categories, with `--json`.
- **Local SQLite store** shared by the app and the CLI. Changes reach the app live through a Darwin notification.
- **Seeded categories:** Coding, Writing, Admin, Learning, Meeting prep.
