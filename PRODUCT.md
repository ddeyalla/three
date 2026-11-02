# Three — Product Spec

*Working name. A focus app for an ADHD brain: three things today, each in a time box, driven by your AI harness.*

Status: draft v1 · 2026-11-02

---

## 1. The problem

With ADHD, the hard part isn't the work. It's choosing what to work on, starting it, staying on it, and stopping when the time is up. Existing tools either:

- do too much. Session has blockers, Slack integration, AppleScript, window tracking, eight settings sections, and the noise turns into another thing to manage.
- do too little. A bare Pomodoro timer doesn't know what you're meant to be doing today or whether you did it.

Three answers one question at a glance: **what am I doing right now, for how long, and does it belong to today's plan?**

## 2. Principles

1. **Three is the default, five is the ceiling.** The app is built for 3 tasks a day. A 4th and 5th are allowed with a visible warning. A 6th is refused.
2. **Everything is time-boxed.** A task without a time block can't be started.
3. **The AI plans, you commit.** Claude, Codex or any harness writes the plan through MCP or the CLI. You approve it in one click. The app is the cockpit, not the planner.
4. **One thing on screen.** While a block runs, the current task and the time left are the biggest things you see. Everything else steps back.
5. **Honest record.** Every session is logged with its planned and actual time and whether it was finished. Trends come from that record, not from guilt.
6. **Walls, not willpower.** During focus, distracting sites and apps are blocked. Getting past a block takes deliberate effort, and every bypass is recorded.
7. **Calm, dark, native.** Dark mode first, macOS 27 Liquid Glass materials, one accent colour per category, no badges, no confetti.

## 3. Core concepts

| Concept | What it is |
|---|---|
| **Day Plan** | The commitment for one calendar date: an ordered list of 1–5 tasks. States: `draft` → `committed` → `closed`. |
| **Task** | Something to work on, with a time block. Belongs to a Day Plan and a Category. |
| **Time block** | The minutes allotted to a task (e.g. 90 min). Can be split into several focus sessions (e.g. 2 × 45). Optionally has a scheduled start time. |
| **Focus session** | One timer run against a task. Records actual start/end, pauses, and the reflection. |
| **Break** | A timer run between sessions. Logged, not judged. |
| **Category** | A label with a colour (Coding, Writing, Admin, Learning…). Colours the timer, timeline and calendar events. |
| **Reflection** | A 3-question check-in at the end of each session (see §5.3). |

### Data model (v1)

```
Category    id, name, colorHex, archived
DayPlan     id, date (unique), status [draft|committed|closed],
            plannedAt, committedAt, source [app|cli|mcp|routine], note
Task        id, dayPlanId, position, title, categoryId,
            blockMinutes, scheduledStart?, strict (bool),
            status [todo|active|done|partial|dropped|carried],
            linearRef? (e.g. "ENG-123" + url), notes, carriedFromTaskId?, createdBy,
            planEventId?           (calendar event in "Three · Plan")
Session     id, taskId, kind [focus|break], plannedMinutes,
            startedAt, endedAt, pausedSeconds, endReason [completed|stopped|extended|abandoned],
            outcome? [done|progress|stuck], focusRating? (1–3), note?,
            logEventId?            (calendar event in "Three · Log")
BlockRule   id, kind [domain|path|app], value (e.g. "reddit.com", "youtube.com/shorts", "com.tinyspeck.slackmacgap"), enabled
CategoryAllow  categoryId, blockRuleId
FocusHours  weekday, start, end
BlockEvent  id, at, blockRuleId, sessionId?, action [blocked|unblocked], reason?
MeetingCache  date, eventId, title, start, end   (written by the app, read by CLI/MCP)
Command       id, kind, payload, createdAt, handledAt?   (v0.5+: calendar intents from CLI/MCP, executed by the app)
```

The record is local-first. Every row carries `id` (UUID), `updatedAt` and `deletedAt` (soft delete), so CloudKit sync can be added later without a migration (§10).

## 4. The daily loop

```
 Plan  ─▶  Commit  ─▶  Focus block  ─▶  Reflect  ─▶  Break  ─▶  next block … ─▶  Close day
 (AI)      (you)       (timer)          (3 taps)     (timer)                       (summary)
```

1. **Plan.** It happens one of two ways (you get both):
   - **Scheduled draft.** At your planning time (default 09:30) the app runs a headless harness command **locally on your Mac**. It's local because a cloud routine can't reach the local database, which means the Mac must be awake at planning time; a missed run fires on the next wake. The default command is `claude -p "/plan-day" --allowedTools "mcp__three__*"`; the tools are pre-allowed so the run doesn't stall on permission prompts. Any harness command works, e.g. `codex exec "plan my day"`. The harness reads yesterday's unfinished tasks, today's meetings and your Linear issues through its own tools, then writes a **draft** plan through the MCP server.
   - **On demand.** At any time you tell Claude "plan tomorrow: X, Y, Z", or add tasks in the app or the CLI.
2. **Commit.** A notification says "Today's plan is ready". The Today screen shows the draft. You drag to reorder, change block lengths or drop a task, then press **Commit**. Committing writes the time blocks to the calendar (§9.2). If no plan exists by your planning time, you get a single nudge, not repeated ones.
3. **Focus.** Start the next task. The timer runs for the block length, or one session's worth of it.
4. **Reflect → Break.** See §5.3.
5. **Carry over.** At day close (default 22:00, or when every task is resolved) the app writes a short summary. Unfinished tasks are marked `carried` and offered to the next day's planner. They are never moved forward silently.

## 5. Screens

Two surfaces: a **menu-bar item** that is always there, and a **main window** for planning and history. Since 0.2.4 the main window has no sidebar. Its three panes are **Tasks** (Today, Inbox, Upcoming, Done, Tags), **Now** (the dial) and **Timeline** (the day). They initially appear in that order. The workspace fills the window, including full screen, with rounded translucent pane bodies and plain headers. Drag a header onto another pane to move it to that position, or use the header menu or View → Arrange Panes. Order survives relaunch; Reset Pane Order restores the default. Invisible native dividers adjust widths with minimums that keep controls usable. Reordering preserves draft input, selection, scroll positions and timers. Settings is a separate window (⌘,) and holds category editing.

Now is one centred column: the task (up to two lines), its category and next step; the dial, time left and a plain status line; then the controls. The dial grows from 240 to 400pt with the pane. Today's order is its priority: drag a card by its title row, or use Move Up and Move Down in the card menu, Edit (⌥⌘↑/↓) or VoiceOver. See [docs/focus-design.md](docs/focus-design.md).

**Tags (0.2.4).** A tag (`@onboarding`) marks a thread of work that runs for days or weeks, such as a product, project or feature. A task can carry several. A tag's time is every focus block on every task that carried it, including copies carried to later days. The Tags view shows the total, the past week, days worked and each task's share. This is the first piece of §5.4 and §5.5; per-tag trends belong in v0.6.

### 5.1 Today (main window, default)

Split view, as in Session's first screenshot, with less on it.

**Left — Now**
- Top: today's tasks as 1–5 glass cards, each showing category colour, title, block (e.g. `90m`), progress ring (minutes done / block), status, and a Linear chip if linked. The active task is enlarged.
- Centre: the **dial timer**. A Session-style radial clock face filled with the category colour. Drag the hand to set or adjust the length (snaps to 5 min). Below it: `45:00` and `3:34 PM → 4:19 PM`.
- Bottom: one primary button: **Start <task>** / **Pause** / **Resume**, plus `+5` and `Finish early`.
- If the plan is a draft: a banner reading "Draft from Claude · 3 tasks · 4h 15m" with **Commit** and **Edit** buttons.

**Right — Day timeline**
- A vertical hour grid for today, like Session's right pane.
- Meetings from your calendars appear as grey hatched blocks.
- Planned task blocks appear as outlined category-coloured blocks. Actual focus sessions appear as filled blocks, and breaks as thin neutral blocks.
- A red "now" line shows the current time.
- Header: the week strip (Mon–Sun) with focus hours per day, and a one-line summary: `2/3 done · 3h 10m focus · 1 break skipped`.
- Over-commitment warning: if the planned blocks exceed the free time left today (after meetings), the header turns amber and reads "Plan is 1h 20m over your free time".

### 5.2 Menu bar

- Title: a symbol and the time left, such as `23:41`, `Paused 23:41` or `Break 4:12`; the symbol alone when nothing runs. The symbol is a dot while a saved reflection waits, a raised hand while something is blocked, else a timer. The task and what's next are in the popover and in the item's VoiceOver label.
- Popover (glass): the current task, time left, Start/Pause, `+5`, the list of today's tasks with ticks, and "Open Three". While blocking is on, a row says until when and why, with Unblock for 5 Minutes and Blocking Settings in its menu (§7). Unblock for 5 Minutes is also in the Focus menu, because macOS can hide the menu-bar item.
- Global hotkey (default ⌥⌘Space) opens the popover from anywhere.

### 5.3 Reflection panel (end of every focus session)

A small glass panel slides in at the top centre of the active screen. It never goes full-screen.

1. **How did it go?** `Done` · `Made progress` · `Stuck`
2. **Focus?** three faces: focused · okay · scattered
3. **What's next?** The next task in the plan is preselected (e.g. `Write PRD · 60m`). One tap each lets you **switch** to another task, **shorten** its block, or **push** it to tomorrow. This is the re-think moment, and it takes seconds.
   - Optional one-line note under it. Example: "blocked on API key".

Then it offers **Start 5 min break** (the default; the length scales with how long you've been focusing, §6), **Skip break**, or **Extend +15**.
- `Done` marks the task `done` if it was the task's last session, and asks "mark task done?" if block time is left.
- `Stuck` offers to drop the task's remaining time or push it to tomorrow.
- Ignoring the panel: after 2 minutes without an answer or edit it ends the focus session and auto-records `Made progress / okay`, keeping any typed note. It starts neither a break nor the next task. The panel hides and a neutral dot pulses in the menu bar until you answer or dismiss the saved reflection. Reduce Motion keeps the dot still. The reminder survives relaunch and never re-opens on its own. Review edits only that session's answers, leaving its times, the task's current status, and any newer timer alone. Several saved reflections wait in order in the popover.

### 5.4 Timeline (history)

Modelled on Session's iPad "Session Log", the screenshot you liked most.
- **Column 1:** months, each with a summary (`55 sessions · 41h focus · 82% of plan done`).
- **Column 2:** days in the month. Each row shows a 24-hour bar strip in category colours, the stats line, and the day's task titles, truncated.
- **Column 3:** the selected day's tasks with planned vs actual time, status, reflection notes, and Linear links.

### 5.5 Trends

One screen, five charts, no tables:
1. **Focus minutes per day.** Bars for the last 4 weeks, with a 7-day average line.
2. **Plan completion rate.** Committed tasks that ended `done`, per week.
3. **Plan accuracy.** Actual focus minutes divided by planned block minutes. Shows whether you over- or under-plan.
4. **Focus quality.** Share of sessions rated "focused", per week, plus a category split.
5. **Distraction pull.** Block hits and unblocks per focus hour, per week, plus your top 3 most-blocked sites and apps.

Plus one streak number: days in a row on which you committed a plan and finished at least one task. "Improvement" means these lines going up over weeks; the app doesn't add scores of its own.

### 5.6 Settings (one page, deliberately short)

- Planning time · day-close time · scheduled-planning command (with a "Test" button)
- Default block length · session length (when splitting) · break lengths
- Calendars: which to read meetings from, and the write calendars (§9.2)
- Categories: name, colour, and allowed items (§7.2)
- Blocking: websites, apps, focus hours and the Chrome connection, with what isn't covered (§7)
- Sounds: on/off, plus one chime choice
- Menu-bar hotkey · launch at login
- CLI & MCP: shows install status and copy-paste config snippets for Claude Code, Claude Desktop and Codex

## 6. Timer and break rules

- **Length:** a session defaults to the smaller of (block time left, preferred session length, default 45 min). A 90-minute block runs as 2 × 45 by default. You can drag the dial to change it.
- **Pause:** allowed. Paused time is recorded and doesn't count as focus. A pause longer than 15 minutes ends the session as `stopped`.
- **Overrun:** at 0:00 the reflection panel appears. If you keep working without answering, the timer counts up in amber (`+04:12`), and the overrun is logged as focus.
- **Breaks:** 5 min after a session; 15 min after about 100 minutes of focus without a long break. Breaks are always optional. Skipped breaks are counted and shown in the day summary, not nagged about.
- **Break-end:** a soft chime and a notification: "Break's over. Next: <task> (45m)" with a **Start** action.
- **One timer at a time,** shared by the app, the menu bar, the CLI and MCP.
- **Sleep or lock:** a running session keeps wall-clock time. On wake after more than 10 minutes, the app asks "Were you working?" and lets you keep or trim the gap.

## 7. Distraction blocker

Blocking of websites in Chrome and of apps on the Mac, tied to focus sessions and weekly focus hours rather than to a separate schedule screen. It adds friction, not security: the person who set it up can always get round it, so Three says plainly what it covers and what it doesn't.

This section describes v0.3 as built (unreleased, after 0.2.4). Where the original plan differed, the difference is listed at the end of each part.

### 7.1 When it's on

- **During every focus session,** from Start until the session ends. A paused or overrunning session keeps blocking for at most 15 minutes, then lets go even if the timer is left alone.
- **During focus hours,** a weekly schedule set in Settings → Blocking or with `three block hours add` (e.g. Mon–Fri 10:00–13:00). Hours may run past midnight. Blocking stays on between sessions and during breaks inside them, which closes the gap where "quick break" turns into an hour of YouTube. A schedule that covers the whole week with no gap is refused, so blocking can't be on forever.
- Outside both, nothing is blocked. Times follow the Mac's time zone and are re-read after a time-zone change, a clock change or wake.
- While at least one blocked rule is really enforced, the menu-bar symbol becomes `hand.raised.fill` and Now's status line adds "· Blocking". It doesn't pulse. If blocking is on but nothing can be enforced (only websites, and no working Chrome connection), there's no glyph and the menu-bar popover says websites aren't blocked.

Changed from the original plan: a hand, not a shield, because this is friction rather than protection.

### 7.2 What it blocks

- **One list of websites and apps,** empty until you add something. X, Reddit and YouTube are one-click suggestions that add their domains as ordinary rows: x.com and twitter.com (not t.co, so shared links elsewhere keep working), reddit.com and redd.it, youtube.com and youtu.be.
- **Websites:** a domain covers its subdomains. Paths such as `youtube.com/shorts` aren't supported; Three offers to block the whole site instead. Up to 1,000 websites can be on. Lists saved before that limit, up to the extension's original 4,000, keep working, but new additions past 1,000 are refused.
- **Apps** are chosen from Applications and matched by bundle ID. Three never blocks itself, under any bundle ID, or apps macOS needs, such as Finder.
- **Not covered:** Safari, Firefox and other browsers; Chrome profiles without the extension; Chrome Guest and Incognito windows (the extension is not allowed in Incognito); videos embedded in other sites; apps that show web pages. Add a browser under Apps to hide it during focus. Three never hides a browser you haven't added.

Not built from the original plan: path rules, per-category allow lists, a starter list on first run, Safari and other Chromium browsers.

### 7.3 What you see when you hit a block

- **Website (Chrome):** the tab goes to the extension's block page. It names the site and why ("reddit.com is blocked during this focus session"), the task with its category colour or "Focus hours", the time until blocking ends and "Until 3:45 PM". **Back to work** goes back, closes a tab that was moved off a blocked site, or opens a new tab when it's the last one; Esc does the same. If the site stops being blocked while the page is open, it says so and offers the site's front page, because the address you opened is never kept.
- **App:** the app is hidden, never quit, so nothing in it is lost. A small glass panel says so, with the task and when blocking ends. **Back to work** returns to the app you were using. It appears each time the app comes forward. Hiding needs the Three app running; Chrome blocking doesn't.
- No counts, streaks, quotes or scores on either. The task you committed to is the message.

Changed from the original plan: no "Reddit blocked today: 7" counter, and no category icon.

### 7.4 Getting past it

- **Only in Three.** The app overlay's **Unblock for 5 minutes…**, or Unblock for 5 Minutes in the Focus menu or the menu-bar popover. The Chrome page tells you where to go; it has no link into Three.
- Write a reason of at least three words, start a 20-second wait, then click **Unblock for 5 minutes**. That last button has no keyboard shortcut, so holding Return can't open anything. The rule is open for five minutes; then blocking resumes and an open app is hidden again. The reason is saved with the session.
- A site that a broader rule also covers can't be opened on its own (opening old.reddit.com wouldn't help while reddit.com is blocked). Three says so before the wait.
- **Strict tasks** turn unblocking off for that task's sessions. Create one with `three add --strict`. Finish and Stop work as usual, focus hours are unaffected, and there's no Give up timer, no protection against quitting and no relaunch agent. The app can't yet mark an existing task strict: that needs a Store mutation that doesn't exist.
- **No loosening while blocking is on.** Removing a rule, changing focus hours and removing the Chrome connection wait until blocking is off. The Store refuses them even if a button was drawn before blocking started. Adding is always allowed.

Changed from the original plan: no Give up timer and no launch agent; strict only prevents new unblocks.

### 7.5 What it records

- Each block hit (which rule, when) and each unblock (rule, reason, when it ends), with the session when there is one. Never the address of the page.
- The app shows none of this as counts. `three block status` lists today's hits per rule.

Not built from the original plan: distractions in the Today summary, the Timeline and Trends, and in `get_stats`.

### 7.6 How it works

| Target | Mechanism |
|---|---|
| Chrome | An MV3 extension, loaded unpacked from a folder Three keeps, talks to `three-native-host` through Chrome native messaging. The host reads the database itself, so Chrome blocking works with the Three app closed. `declarativeNetRequest` sends blocked page loads to the block page, and open tabs on a newly blocked site are moved there. Each profile reports whether it can act on all sites. If Three stops answering, rules lapse within three minutes (fail open). |
| Apps | The Three app watches activations, launches and unhides (`NSWorkspace`) and hides blocked apps. It hides them again when blocking starts, a rule is added or an unblock ends. Only while Three is running. No special entitlements. |

**Chrome setup** is a step you take, in Settings → Blocking → Set Up Chrome…. It shows the two things it will write (the native-messaging connection file in Chrome's `NativeMessagingHosts` folder and a copy of the extension) and writes them only when you click Add Connection. Then you load the extension in each Chrome profile with Developer mode and Load unpacked. Three won't replace an extension folder it didn't create. `three block connect-chrome` does the same from the terminal.

**Verified so far:** the Chrome path ran end to end in an isolated Chrome for Testing profile with Three's real host (rules, sweeping, pause, expiry, Back to work, two profiles, permission changes, lease loss, legacy lists). The visible setup steps a person takes in their own Chrome, and Chrome's own permission prompt, haven't been tested by hand.

Not used, and why:
- **Screen Time APIs** (FamilyControls/ManagedSettings): they need a special entitlement from Apple and give little control over the block screen.
- **`/etc/hosts` edits:** crude, slow to take effect, and can't show a page.
- **Network content filter** (a system-wide network extension): stronger, since it also catches other apps' web views. Listed as a possible later backstop.

## 8. AI integration: MCP server + CLI

This is the core of the product. The CLI and the MCP server are the same binary, so they behave identically.

### 8.1 Shape

- A `three` command-line binary ships inside the app bundle. **Settings → Install CLI** symlinks it to `/usr/local/bin/three`, or to `~/.local/bin` if you choose.
- `three mcp` runs the MCP server over stdio. Client config:
  ```json
  { "mcpServers": { "three": { "command": "three", "args": ["mcp"] } } }
  ```
- **Division of work.** The app is the only process that touches EventKit, notifications and the timer. The `three` binary only reads the database and writes rows. Plan, task and timer edits go in directly: the timer is a `Session` row with timestamps, so the CLI can start or pause it and the app reacts by rescheduling notifications. Calendar actions (`commit_day` writing events, from v0.5) go in as `Command` rows, which the app executes.
- **If the app isn't running,** any command that needs it launches it in the background first (`open -g -b <bundle id>`). Launch at login is on by default.
- **Reads come from the database only.** Meetings come from the `MeetingCache` the app refreshes, so the CLI never needs calendar permission.

### 8.2 MCP tools

| Tool | Purpose |
|---|---|
| `get_today` / `get_day(date)` | The plan, tasks, sessions, and free time left after meetings |
| `plan_day(date, tasks[], commit=false)` | Create or replace a draft plan. Each task has `{title, category, block_minutes, scheduled_start?, linear?, notes?}`. Enforces the 5-task limit and warns above 3. |
| `add_task(date, …)` / `update_task(id, …)` / `remove_task(id)` | Edit a plan |
| `commit_day(date)` | Commit a draft. Writes the plan blocks to the calendar. |
| `set_task_status(id, status, note?)` | Mark done, dropped or carried |
| `start_focus(task_id?, minutes?)` / `pause` / `resume` / `stop` | Control the timer. Without a `task_id`, starts the next task. |
| `get_status` | What's running right now, and the time left |
| `get_carryover(date)` | Unfinished tasks from earlier days |
| `get_meetings(date)` | Calendar events from the selected read calendars |
| `get_history(from, to)` / `get_stats(range)` | Sessions, reflections and trend numbers, so Claude can coach ("you overplan Mondays by 40%") |
| `list_categories` / `upsert_category` | Category management |
| `get_block_status` | Whether blocking is on, why (session or focus hours), the active rules, and today's hits |
| `add_block_rule(kind, value)` / `set_task_strict(id)` / `block_now(minutes)` | **Tighten only.** Agents can add rules, mark tasks strict, or start blocking. No tool removes a rule, disables blocking, or loosens an allow. The server has no such tools, so a prompt can't talk its way around it. |

Resources: `three://today`, `three://plan-day-guide`. The guide is a short markdown brief that tells any agent how to plan well: three tasks; block sizes in 15-minute steps; leave about 25% buffer; respect meetings; put carried-over tasks first or drop them deliberately.

### 8.3 CLI (mirrors the tools)

```
three today                         # print today's plan + status
three plan --date tomorrow \
  "Ship onboarding:Coding:90" "Write PRD:Writing:60" "Inbox zero:Admin:30"
three add "Fix login bug" --cat Coding --block 45m --linear ENG-123
three commit
three start [task#] [--min 25]   |  three pause | resume | stop
three done 2 --note "merged"
three stats --range 30d --json
```

Every command supports `--json` for scripts.

### 8.4 Bundled agent skill

The app also ships a `plan-day` skill/prompt file (for Claude Code at `~/.claude/skills/plan-day/SKILL.md`, and the equivalent prompt for Codex). It tells the agent what to do: pull carry-over, meetings, and optionally your Linear "In Progress / Todo" issues through Linear's MCP; propose 3 tasks with blocks; call `plan_day` with `commit=false`. That skill is what the scheduled draft (§4) runs.

## 9. Integrations

### 9.1 Linear — link only (v1)
- A task can carry a Linear issue (`ENG-123` plus its URL). It shows as a chip that opens the issue.
- The app never calls Linear itself. Your harness reads and updates Linear through Linear's own MCP, e.g. moving an issue to Done after `set_task_status(done)`.

### 9.2 Calendar (EventKit — covers iCloud, Google and Exchange accounts added to macOS)
- **Read meetings** from the calendars you select. They appear on the timeline and count against free time.
- **Write plan blocks:** on commit, each task with a `scheduled_start` becomes an event in a **"Three · Plan"** calendar, created automatically. Editing or moving a task updates its event.
- **Log actual sessions:** each finished focus session becomes an event in a **"Three · Log"** calendar with real start and end times and the outcome in the notes.
- Plan and Log are separate calendars so you can hide either one in Calendar.app. Events carry the category colour where the calendar account supports it.
- The app writes to its own two calendars and nowhere else.

## 10. Technical approach

| Area | Choice | Why |
|---|---|---|
| UI | SwiftUI on macOS 27, Liquid Glass (`glassEffect`, `GlassEffectContainer`), `MenuBarExtra` | Native look and the "current macOS glass" you asked for; the menu bar comes for free |
| Storage | SQLite via **GRDB** at `~/Library/Application Support/Three/three.sqlite` | One database shared by the app and the `three` CLI/MCP binary (the app itself isn't sandboxed; only the Safari extension uses an App Group, for its small block-state file); WAL mode handles concurrent writes; the app observes changes live |
| Sync (later) | **CKSyncEngine** to a private CloudKit database | Mac now, iPhone later. Rows already have UUIDs and `updatedAt`. |
| Calendar | EventKit | One permission covers every calendar account on the Mac |
| Notifications | UserNotifications with actions (Start, +5, Skip break) | Notifications become actionable from the lock screen and banners |
| Process roles | The **app** owns the timer, notifications, EventKit, the meeting cache and blocker enforcement, and executes `Command` rows. The **CLI/MCP** reads the database and writes plan rows and commands only. | One owner per side effect; a CLI launched by Claude never needs calendar or notification permission |
| Scheduled planning | The app runs the configured harness command at planning time (via `Process`, with a login-shell `PATH`) | No cloud required. Output and errors appear under Settings → Last run. |
| MCP | The Swift MCP SDK (stdio transport) inside the `three` binary | One binary, no Node or Python runtime |
| Blocker | Safari Web Extension (in the app bundle) + Chromium MV3 extension + `NSWorkspace` app watcher + a launch agent for strict mode (§7.6) | Shows a real block page in browsers; blocks apps with no special entitlement |
| Distribution | Developer ID-signed, notarized DMG | Personal use; the Mac App Store sandbox would make the CLI and shared database harder |

Why a native app, not Electron/Tauri: Liquid Glass, the menu bar, EventKit and notifications are all first-class in SwiftUI, and a Swift app is the shortest path to an iPhone version later.

## 11. Out of scope (on purpose)

Background sounds, Slack status, window tracking, AppleScript, social or leaderboards, points and badges, pro plans, team features, in-app AI chat (the AI lives in your harness), two-way Linear sync (v1).

## 12. Release plan

**v0.1 — Core loop (use it daily)**
Categories, Day Plan with up to 5 tasks, dial timer, menu bar, reflection → break, Today screen with timeline (plan and actual only), local SQLite, `three` CLI.

**v0.2 — Plan and capture**
Three panes (tasks, dial, timeline; 0.2.4 replaced the sidebar), inbox for unplanned tasks, tags with time per tag, a 30-day Done list, Todoist-style quick add (`#category 45m tomorrow`), steps and notes shown in place on each task, Settings (timer defaults shared with the CLI through the database, category editing, CLI install and agent instructions), quick capture from the menu bar.

**v0.3 — Blocker**
Blocklist, focus hours, the Chrome extension with its block page, app hiding with an overlay, unblock friction, strict tasks, block logging. Built and unreleased; Safari, other Chromium browsers, path rules and per-category allow come later (§7).

**v0.4 — AI-driven**
MCP server, `plan-day` skill, draft → commit flow, scheduled planning command, carry-over.

**v0.5 — Calendar**
Read meetings, free-time warning, Plan and Log calendars.

**v0.6 — Record**
Timeline history (month/day/detail), Trends charts, day-close summary.

**v1.0 — Polish**
Sleep/wake handling, global hotkey, onboarding (permissions, CLI install, MCP config copy), app icon.

**Later**
CloudKit sync. It's deferred so v0.1 can ship sooner; the data model is ready for it, and it can move earlier if you want it. Then an iPhone/Watch companion (timer plus today view); optional two-way Linear sync; a network content filter as a system-wide blocking backstop; phone blocking through iOS Screen Time, driven by the same focus state.

## 13. Success measures (for you)

After 4 weeks of use:
- A plan committed on at least 80% of weekdays.
- Plan completion rate trending up week over week.
- Plan accuracy settling between 0.8 and 1.2 (you're learning to size blocks).
- Daily active use without opening Settings more than once a week (the app stays out of the way).

## 14. Open questions

Resolved 2026-11-02, defaults accepted: the name is **Three**; weekends plan as normal; the day closes quietly; categories start as Coding, Writing, Admin, Learning, Meeting prep.
