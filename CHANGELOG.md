# Changelog

## Unreleased

- Unfinished tasks from earlier days appear only under "Unfinished from earlier days", never also in the Inbox, and can be accepted onto today or any of the next six days.
- `three done`, `drop`, `push`, `start` and `tomorrow` accept a task id from any open day. A prefix shared across days is refused, closed days explain how to carry the task, and `tomorrow` always lands on tomorrow.
- `three block add com.apple.Music` makes an app rule. One classifier serves the CLI, MCP and Settings, leans towards website when unsure, and reports the kind it chose; `--app` and `--site` override it.
- The notch surface stays within 50pt of the camera, grows downward, opens after a short rest or on click, closes 0.4s after the pointer leaves, and only takes clicks over itself.
- History rows use a trailing disclosure chevron, the task editor is titled "Task details", and Day Review steps through every closed day.

- `three mcp` exposes shared planning, task, timer, category, history, and tightening-only blocker operations over stdio. Calendar and free-time tools remain unavailable before v0.5.
- Agent drafts show their source, count, and duration. Review, edit, reorder, drop, and commit in Today. Earlier unfinished tasks can be accepted or dismissed deliberately while retaining steps, tags, and history.
- Settings includes copyable MCP connection entries, canonical planning guidance, and opt-in scheduled local planning with Test, output, errors, one daily catch-up, and draft-only agent access. The bundled helper bounds and cancels commands independently of the app.
- Shared lifecycle guards protect closed and carried work. Legacy date spellings upgrade without losing task or session links.

- Three has a retriever app icon with a transparent outer border and native macOS icon sizes.
- Blocker race fixes: connection removal holds the Store's writer lock, delayed panels cancel when protection ends, and the unblock wait uses elapsed time rather than the Mac's clock. Failed app hides now appear in coverage, Back to work rechecks its destination, and midnight-to-midnight focus hours stay editable as full days.
- **Blocking during focus.** Settings has a Blocking tab for websites, apps, weekly focus hours and the Chrome connection. It starts empty; X, Reddit and YouTube are one-click suggestions that add their domains as ordinary rows (X adds x.com and twitter.com, not t.co). Blocking is on during every focus session, for at most 15 minutes of a paused or overrunning one, and during focus hours, which may run past midnight but can't cover the whole week.
- **Chrome** shows a calm block page instead of a blocked site: the site, the task, the time until blocking ends and Back to work. It keeps working with Three closed. Setup is a step you take: Three shows what it will write and writes it only when you click Add Connection, then you load the extension in each profile. Guest and Incognito windows, other profiles and other browsers aren't covered, and Settings says so.
- **Apps** you block are hidden, never quit, whenever they come forward while blocking is on, and again when an unblock ends. A small glass panel says so and offers Back to work. Hiding needs Three running. Three never hides itself, apps macOS needs, or a browser you didn't add.
- **Unblocking** happens only in Three: write a reason of at least three words, wait 20 seconds, then click Unblock for 5 minutes, which has no keyboard shortcut. A site a broader rule also covers can't be opened on its own. A strict task (`three add --strict`) turns unblocking off; Finish and Stop work as usual.
- While something is really blocked, the menu bar shows a raised hand and Now adds "· Blocking". Blocking that can't enforce anything shows no hand and says what's missing. The menu-bar popover says until when and why, and holds Unblock and Blocking Settings.
- **Focus → Unblock for 5 Minutes** lists each blocked site and app, so a website can be unblocked from the main window without the menu-bar popover. A site a broader rule covers, or one already open, is listed but can't be chosen. The item is disabled when blocking is off, nothing is blocked or the task is strict, and choosing a rule checks it again first. Back to work stays in Three when unblocking starts from its main window. Switching an existing blocked-app overlay to Unblock preserves its return destination.
- The menu bar shows the time beside one symbol, where it had shown only an icon: `24:13`, `Paused 24:13`, `+03:12` or `Break 04:12`, and the symbol alone when nothing runs. A saved reflection's dot takes the symbol's place before the blocking hand; VoiceOver hears the task, the time, the reflection and blocking.
- Prominent buttons have a dark label on light category glass (6.9 to 9.4:1 measured, from 2.1 to 2.8:1 with white). Idle grey and dark custom colours keep white, and a window that isn't key keeps the system's own label.
- Removing rules, changing focus hours and removing the Chrome connection wait until blocking is off; adding is always allowed. The Store refuses a removal that races the start.
- New website rules are capped at 1,000 enabled sites; existing lists up to 4,000 keep working. `three block status` shows coverage, gaps and today's hits.
- Typing straight after Break it down or Add a tag now lands in the new field instead of Notes.
- Closed tasks on Today are dimmed again; the dimming was applied outside the glass, where it was ignored.

- Now is one centred column: the task, its category and its next step; the dial, time left and status; then the controls. The dial grows from 240 to 400pt with the pane. The title is larger and wraps to two lines. Click the next step to tick it off. The status is plain text and says Paused while paused. A break names the task up next, an empty day offers Add Task, and an all-done day shows its summary. The dial takes input only when there is a task to start.
- Drag a Today card by its title row to change the order. A line marks where it will land; Escape or a drop anywhere else changes nothing. Move Up and Move Down are also in the card's menu, in Edit (⌥⌘↑ and ⌥⌘↓, for the task you selected) and in VoiceOver's actions.
- Add Task and ⌘N put the cursor in quick add even when they switch lists. Previously the list being replaced kept the request.
- After two minutes without an answer or edit, the reflection panel saves Made progress and Okay, keeps any note, ends the block, and hides. A pulsing menu-bar dot reminds you to review or dismiss it. Saved reflections survive relaunch, and editing one leaves newer timers alone. Reduce Motion keeps the dot still.
- The workspace fills the window, including full screen, with three rounded translucent panes and plain headers. Drag a header onto another pane to reorder, or use the header menu or View → Arrange Panes. Order is remembered, Reset Pane Order restores the default, and invisible native dividers adjust widths. Draft input and scroll state stay with each pane when it moves.
- Invalid or overflowing durations no longer crash the app or CLI. Extensions and breaks reject invalid lengths before changing a timer.
- A running task must finish before it can move to tomorrow. Closed or already-carried tasks cannot create more copies or restart silently.
- Saving a reflection and starting the next task or break now happen together. If the next task cannot start, the original session stays intact. Choosing Finish makes the panel ready for Escape and Return without focusing its note. Choosing Finish again preserves the draft.
- The dial no longer jumps from five to 55 minutes when unwound past twelve. Dragging starts from its current length, respects both limits, and responds immediately when reversed. Arrow keys adjust an idle dial by five minutes.
- Task titles and tag headers are native buttons. Checklist labels toggle their steps, completion controls have larger targets, and controls have descriptive accessibility labels. Inbox counts stay in the summary, so navigation keeps its width. Scrollbars follow macOS preferences, and authored motion respects Reduce Motion.
- The Focus menu exposes Start, Pause/Resume, Add 5 Minutes, and Finish Block with shortcuts. Quick Add opens the main window and falls back to Inbox when today is full.
- Design lint now catches type-weight overrides as well as raw fonts. Timeline labels use the existing Meta role.

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
