---
name: Three
description: A calm, native focus planner. Three tasks today, one on the dial.
colors:
  canvas: "#0E0E11"
  now-red: "#FF4D45"
  overrun-amber: "#FF9E33"
  idle-grey: "#8C8C8C"
  category-coral: "#F2766B"
  category-cornflower: "#6E9BF2"
  category-ochre: "#E5A84B"
  category-jade: "#4FBF8B"
  category-lavender: "#A58AF0"
  category-teal: "#5CC6D0"
  category-rose: "#E57BB5"
  category-sand: "#B8A27A"
typography:
  display:
    fontFamily: "SF Pro"
    fontSize: "48px"
    fontWeight: 300
    lineHeight: 1
    fontFeature: "tnum"
  title:
    fontFamily: "SF Pro"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.2
  focus:
    fontFamily: "SF Pro"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: 1.3
  heading:
    fontFamily: "SF Pro"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.35
  body:
    fontFamily: "SF Pro"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.35
  meta:
    fontFamily: "SF Pro"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.3
rounded:
  block: "8px"
  card: "12px"
  panel: "20px"
spacing:
  hairline: "2px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
components:
  task-card:
    rounded: "{rounded.card}"
    padding: "8px 12px"
    typography: "{typography.body}"
  quick-add-field:
    rounded: "{rounded.card}"
    height: "36px"
    padding: "0 12px"
    typography: "{typography.body}"
  timeline-block:
    rounded: "{rounded.block}"
    typography: "{typography.meta}"
  tasks-pane:
    minWidth: "320px"
    padding: "16px"
  workspace-pane:
    rounded: "{rounded.panel}"
    headerHeight: "36px"
    typography: "{typography.heading}"
  choice-capsule:
    rounded: "capsule"
    height: "28px"
    padding: "0 12px"
    typography: "{typography.body}"
  tag:
    typography: "{typography.meta}"
  reflection-panel:
    rounded: "{rounded.panel}"
    padding: "24px"
    width: "420px"
---

# Design System: Three

## Overview

**Creative North Star: "The Quiet Instrument"**

Three is a tool you glance at, not a place you browse. It should feel like a well-made instrument on a desk: one dial, one number, a short list, and nothing that asks for attention it hasn't earned. The interface is native macOS through and through. San Francisco carries every word, Liquid Glass carries every surface, and the only colour is the colour of the category you're working on.

Hierarchy comes from size and weight inside a single family, never from a second face or decoration. There are six type roles and every piece of text uses one of them. The time left is the largest thing on screen while a block runs (PRODUCT.md, principle 4); nothing else competes with it.

Density is compact, Mac-standard: 13pt body, 40pt rows, tight groups with clear gaps between them. Calm comes from restraint and alignment, not from empty space.

**Key characteristics:**
- One family (SF Pro), six roles, four weights.
- Liquid Glass on cards, controls, the dial and timeline blocks; a dark canvas lit by the current category colour underneath.
- Colour means something: a category, the current time, or an overrun. Never decoration.
- Respect the platform: system controls, SF Symbols, the user's sidebar size and accessibility settings.

## Colors

A near-black canvas, white text at system opacities, and category colours at matched lightness so no category shouts louder than another.

### Primary
- **Category colours** (coral #F2766B, cornflower #6E9BF2, ochre #E5A84B, jade #4FBF8B, lavender #A58AF0, teal #5CC6D0, rose #E57BB5, sand #B8A27A): the accent is always the current task's category. It tints the dial, the running card's glass, the primary button and the backdrop wash. There is no app-wide brand colour.

### Neutral
- **Canvas** (#0E0E11): the window background under the glass.
- **Text**: system `.primary`, `.secondary` and `.tertiary` only. Never a hand-picked grey.
- **Idle grey** (#8C8C8C): the accent when nothing is selected, and break blocks.

### Signal
- **Now red** (#FF4D45): the current-time line on the timeline. Nothing else.
- **Overrun amber** (#FF9E33): time past a block's end, and the warning icon on errors.

### Named rules
**The Meaning Rule.** Colour marks a category, the present moment or a problem. If it does none of those, it is grey.

## Typography

**Family:** SF Pro (the system font) for everything. No second family. Monospace only for literal code, such as the agent instructions in Settings.

**Character:** Apple's own voice, used with discipline. Personality comes from the timer and the glass, not from the letterforms.

### Hierarchy
Defined once in `Typo` (Sources/ThreeApp/Theme.swift). Views use these roles and never set a size or weight themselves.

- **Display** (Light 300, 48pt, tabular figures): the time left on the dial and in the menu bar, and on Chrome's block page. The one big number.
- **Title** (Bold 700, 22pt): page titles (Today, Inbox, Upcoming, a category) and the task the dial is about in Now.
- **Focus** (Semibold 600, 15pt): the task in the menu-bar popover, and the heading of the reflection panel and the block overlay.
- **Heading** (Semibold 600, 13pt): section headings inside a page, such as a day in Upcoming.
- **Body** (Regular 400, 13pt): task titles, steps, notes, fields, menu rows, durations, the line under a page title.
- **Meta** (Regular 400, 11pt, secondary): the category and step count under a task, timeline hour labels and block labels.

### Named rules
**The Six Roles Rule.** A seventh size needs a new role in `Typo` and a line here first.
**The Steady Weight Rule.** Weight belongs to the role, not the state. Selecting or running a task changes its glass, never its font weight, so text doesn't shift.
**The Tabular Rule.** Any number that changes or lines up in a column (timers, durations, counts, times) uses tabular figures.

## Layout

One window, three movable panes, no sidebar and no window toolbar:

- **Tasks** (initially left, at least 320pt): one row of choice capsules (Today, Inbox, Upcoming, then icons for Done and Tags), each sized to its label, then the list for that choice. Labels stay on one line. Counts belong in the list summary so navigation never shifts as tasks arrive.
- **Now** (initially middle, at least 360pt): one centred column in three groups. *What*: the task, its category and its current step. *How long*: the dial, the time left and a status line. *Act*: the controls. Groups sit 24pt apart, with 2 to 12pt inside a group. The dial scales with the pane from 240 to 400pt; text keeps its role sizes, so a larger pane changes proportions, never which items appear. The column sits slightly above centre (two parts of the spare height above, three below).
- **Timeline** (initially right, at least 300pt): the day on an hour grid, with blocks expanding to the available width.

The workspace fills the available window width and height, including full screen. Each pane has a rounded translucent content background and a compact header with only its title, drag grip and menu icon. The header has no separate background. Small, consistent outer insets and gaps give the panes separation. Native split-view dividers let people adjust widths without drawing persistent lines. Minimum widths keep the capsules, timer controls and timeline usable. Categories remain in Settings.

There is no maximum workspace width and no growing side gutters. Respect the window's safe area and traffic lights. Use 12pt outer side and bottom insets, 8pt above the workspace, and native dividers with 4pt padding on either side. The divider's resize target and native resize cursor remain active across this gap even though the line is not drawn.

Pane order is a local display preference. Drag a pane's named header onto another pane to move it to that position. Highlight only the receiving pane during the drag; cancellation changes nothing. The header menu and View → Arrange Panes provide the same moves without dragging. Order survives relaunch. Reset Pane Order restores Tasks, Now, Timeline. Moving a pane preserves its task selection, draft input, scroll position and running timer.

Spacing uses one scale: 2 (a title and its subtitle), 4, 8, 12, 16, 24, 32. Inside a group the gap is 4 to 8; between groups 16 to 24; between page sections 24 to 32. Page margins are 24pt.

## Elevation & Depth

Liquid Glass remains on cards, quick-add field, controls, dial, timeline blocks and reflection panel. Workspace pane backgrounds use a standard translucent system material beneath these surfaces. Pane titles and icons sit directly on that material. Do not wrap existing glass controls inside another full-pane Liquid Glass effect. A running task's card tints its glass with the category colour at 30%; a selected card lightens by 8% white. The only drop shadow is the system's own, under the floating reflection panel and block overlay.

### Named rules
**The Material Hierarchy Rule.** Liquid Glass carries controls. Standard translucent material separates workspace content underneath. Canvas is the base. No custom shadows or solid fills standing in for glass. Retain the existing glass cards and dial; do not stack a new glass container behind them. See [Apple research and layout decisions](docs/workspace-design.md).

## Shapes

Three radii: 8pt for timeline blocks, 12pt for cards and the quick-add field, 20pt for workspace panes, the reflection panel and the block overlay. Small controls and choice capsules are capsules. Corners are continuous (squircle), as the system draws them.

## Components

- **Workspace pane**: full-height rounded translucent content surface. A 36pt header without a background uses Heading for its name, a neutral grip, and a native menu with Move Left, Move Right and Reset Pane Order. The title/grip is the drag source; controls and content keep their own interactions. The same commands live in the View menu. Use stable pane identities and save only order, never task data. Moves are immediate, with no authored motion. The native divider provides width adjustment without a visible line.
- **Task card**: completion circle (category colour), title in Body, a Meta line with the category dot and name, its tags, the step count, then steps and notes when open. Padding 8 by 12. The completion button has a 24pt target. The title is a native plain button, separate from completion and scheduling controls. It selects an open task on Today and opens details elsewhere. A closed task on Today can also open its details. Full titles are available in a tooltip and to VoiceOver. On Today, the title row also drags the card up or down; order is priority, so the top open task is the one the dial offers next. The drag image is a collapsed glass title row. While a card is over a gap where it would land somewhere new, a neutral 2pt line marks that gap; no line shows at the card's own position. The card's contents go to half opacity while it travels. Releasing anywhere else or pressing Escape changes nothing. The same moves are Move Up and Move Down in the card's menu, Edit → Move Task Up and Move Task Down (⌥⌘↑ and ⌥⌘↓), and VoiceOver actions on the title.
- **Tag**: `@name` in Meta, secondary. Tags carry no colour (the Meaning Rule): the category already colours the task. A tag groups work that spans days or weeks, such as a product or a feature, and its time is the sum of every focus block on its tasks.
- **Dial**: one turn is an hour. The wedge is the time left in the current hour; each further hour is a 2pt ring in the accent around the face. Drag to set, winding past 12 o'clock to add an hour, from 5 to 240 minutes. A drag starts from the current length without jumping to the pointer. At either limit, reversing responds immediately. When idle, Tab can focus the dial and arrow keys adjust by five minutes. Its tooltip explains dragging and keys. Its size follows the Now pane: tick lengths, hour-ring spacing and the hub scale with it, while strokes stay 2pt for rings and 1 to 1.5pt for ticks. It accepts input only when idle with a task to start; with nothing to time it is an inert, unfocusable picture.
- **Now status line**: one Body line in secondary under the time left. It shows the span (`7:14 → 7:59 PM`), a pause symbol with Paused, or Ended at a time once a block overruns. Plain text on the pane, no glass, because it is information rather than a control. While paused the time left also turns secondary.
- **Current step**: under the task in Now, the first unchecked step of the running or selected task: an empty checkbox, the step title in Body (one line) and its position, such as "2 of 3", in Meta. The position is the step's place in the list, so steps ticked out of order still read correctly. Clicking marks that step done and the next one takes its place with a 150ms opacity cross-fade (none with Reduce Motion). When every step is done it reads "All 3 steps done" beside a filled checkbox in the category colour, with no action. Tasks without steps, breaks and empty days show no step row, and Now never asks you to break a task down.
- **Now with nothing to time**: a break shows "Break" and, when there is one, "Up next · task" in Meta. An empty day shows "What are your three today?", the line "Add a task, then start a block." and one prominent Add Task button (⌘N), which opens quick add on Today. When nothing is open and at least one task is done, it shows "All done for today" with the day's summary and no button. In the empty and all-done states the dial stays as an inert grey picture and the time left and status line are hidden.
- **Quick-add field**: a 36pt glass field in Body. The parsed preview sits on its own line below the input in Meta.
- **Controls**: system glass buttons at regular size. One prominent button at a time, tinted with the accent.
- **Timeline block**: glass tinted with the category, label and duration in Meta. A planned block is a dashed outline in the category colour.
- **Choice capsules**: a row of glass capsules for picking one answer. The chosen one lightens by 15% white and its text turns primary; the rest stay secondary. They are not prominent buttons, so a view keeps one primary action. They switch the tasks pane and answer the reflection panel's questions.
- **Reflection panel**: 420pt floating glass panel. A header with the task (Focus) and time focused (Body, secondary) and a close button. Each question is a left-aligned Body label over its choice capsules. The next task is a glass row. The note is a plain field on glass, like quick add, and never takes focus by itself. The footer has a quiet "15 more minutes" on the left and Skip break (glass) and Start break (the one prominent button) on the right. Esc closes it.
- **Saved reflection reminder**: after two minutes without an answer or edit, save Made progress and Okay, keep any typed note, end the block, and hide the panel. A neutral dot pulses in the menu bar until the saved reflection is reviewed or dismissed. Reduce Motion keeps the dot still. The popover names the oldest saved reflection and offers Review and Dismiss. If several are waiting, it shows their count and presents the next one after each review or dismissal. Go → Review Saved Reflection opens the same review from the main window. Reviewing opens the same glass panel with its saved answers, note, and a Save reflection button. It edits that session only and never changes a newer timer or the task's current status. It never opens automatically. Closing or pressing Esc dismisses the reminder and keeps the saved answers.
- **Blocking indicator**: `hand.raised.fill` before the menu-bar title, and " · Blocking" with the same glyph after the Now status line, only while at least one blocked rule is actually enforced: an app rule (Three hides apps while it runs) or a site rule with a working Chrome profile. Blocking that is on but enforces nothing shows no glyph. It never pulses, so it can't compete with the saved-reflection dot. Not a shield, because blocking is friction, not security.
- **Blocking row**: in the menu-bar popover while blocking is on. A secondary `hand.raised.fill` (an amber `exclamationmark.circle.fill` when nothing can be enforced), "Blocking until 3:45 PM" in Body and one Meta line naming why (this focus session, a paused or overrunning session, or focus hours), what covers it (Chrome profiles, apps) and any rule already open. A borderless ellipsis menu holds Set Up Chrome… when websites aren't blocked, Unblock for 5 Minutes with one item per blocked rule, and Blocking Settings…. A rule a broader rule also blocks, and a rule already open, show as disabled items that say why. Strict tasks have no Unblock submenu.
- **Block overlay**: a 420pt floating glass panel built like the reflection panel. It appears after a blocked app is hidden (never quit) and is the one place to open a rule for five minutes. Blocked mode: a Meta line ("Slack is hidden during this focus session", or that macOS wouldn't hide it), the task in Focus with its 6pt category dot ("Focus hours" without one) and one Body line in secondary ("23 min left · until 3:45 PM", "Paused · until 3:12 PM", "Until 6:00 PM"). The footer has a quiet plain Unblock for 5 minutes… on the left, or "Unblocking is off for this task." in Meta when the task is strict, and Back to work on the right, the one prominent button, tinted with the category. Unblock mode: "Open Slack for 5 minutes" in Focus, a plain glass reason field like quick add, a Meta hint, then Start 20-second wait. That becomes a disabled countdown ("Unblock in 0:14"), then the plain glass Unblock for 5 minutes. The reason is kept with the session. When a broader rule also blocks the site, the hint says so and the wait can't start. Enter fades and rises 10pt over 240ms; Reduce Motion fades only; dismissal is immediate. It closes by itself when its rule stops being blocked.
- **Blocking settings**: a Settings tab in grouped form. A status row (Off, "On until 3:45 PM" or "On, websites not blocked") with one Meta line. Websites: one row per domain with a globe, its preset name in Meta ("YouTube" under youtu.be), and a borderless remove button; Suggested buttons for X, Reddit and YouTube add their domains as ordinary rows; then an Add a website field. Apps: rows with the app's own icon ("Not installed" with `app.dashed`) and Choose App…. Focus hours: one row per group of days with the same hours, opening a sheet with day toggles, From and To and "Ends the next day at…" for overnight hours. Chrome: the connection state in words, Set Up Chrome… or Remove Connection…. Not covered: the browsers and windows the blocker can't reach. Adding is always allowed. While blocking is on, remove controls are disabled with "You can remove this after 3:45 PM." as help, and the Store refuses a removal that races the start anyway. Problems sit under the row that caused them, with the amber icon.
- **Chrome setup sheet**: three numbered steps the person takes. Nothing is written until they click Add Connection; the paths it writes and the connection file are shown first. Then loading the extension in each profile, then a live check that names what's wrong.
- **Block page (Chrome)**: the one web surface. A centred 420px card on the canvas with the category wash, at the six role sizes in the system font. Meta "reddit.com is blocked during this focus session", the task in Focus with its category dot, the time left in Display ("Paused" in secondary while paused), "Until 3:45 PM" in Body, and Back to work: the category fill with a dark label, because white fails contrast on every category colour. Below it, in Meta: how to unblock ("use Unblock in Three's menu bar") or that unblocking is off for this task, then "Three isn't connected right now." when it isn't, then the privacy line. When the site stops being blocked the page says so and offers Open reddit.com, which goes to the site's front page because the address was never kept. The card is a CSS approximation of glass, not Liquid Glass; Reduce Motion, Reduce Transparency and Increase Contrast each have a plain fallback. No quote, count, score or streak.

## macOS interaction details

- Native buttons own task selection, tag disclosure and checklist actions. Tab and Shift-Tab follow the system keyboard-navigation setting, Space activates a focused button, and labels describe the task or step they affect. Checklist labels toggle their checkbox.
- Keep the system focus indicator. Plain text fields show a quiet change in their glass while focused. Automatic reflection prompts never take the keyboard from another app. Choosing Finish or Review makes the panel key so Escape works immediately, with no automatic cursor in the note. Choosing Finish again brings the existing panel forward without clearing its draft.
- Scrollbars follow the user's macOS preference. Do not hide them unconditionally.
- Reduce Motion disables authored movement, symbol replacements and repeating pulses. Keep state changes immediate and use opacity only where feedback needs it. Native glass remains responsible for the system's transparency and contrast preferences.
- Reordering tasks on Today follows the pane rules: immediate, no authored motion, a neutral cue only while over a gap that would change the order, nothing written until the drop, and a menu alternative. Edit → Move Task Up and Down act on the Today card that holds keyboard focus, else on the task you explicitly selected on Today. They do nothing while you type in quick add, and never act on the task the dial picks by default.
- Timer actions are discoverable in the menu bar, with shortcuts shown beside the commands and in control tooltips. Commands disable when they do not apply.
- The block overlay takes the keyboard when it appears, because the person just tried to use the blocked app. It never activates Three. Return and Esc mean Back to work. In Unblock, Return in the reason field only starts the wait, Esc is still Back to work, and the final Unblock button has no shortcut, so holding Return can't open anything. Clicking into another app dismisses the overlay and drops a wait in progress. Back to work returns to the app used before, when macOS allows it.
- Saving a live reflection and starting its break or next task is one operation. If the next step cannot start, the original block and answers stay available for retry.

## Do's and Don'ts

- **Do** pick a role from `Typo` for every piece of text.
- **Do** let the dial and the time left be the largest things on Today.
- **Do** use system controls, menus and SF Symbols. Where a system segmented control would be too wide (it sizes every segment to the longest), use choice capsules.
- **Don't** write `.font(.system(size:))` or a text style outside `Theme.swift`. `scripts/lint-design.sh` fails the build on it.
- **Don't** change font weight to show state.
- **Don't** add a colour that isn't a category, now or overrun.
- **Don't** strip the glass for flat fills. The flat 0.1.1 look was rejected.
- **Don't** put an eyebrow label above a heading, or use all caps for labels.
- **Don't** claim protection the blocker can't give. Show the blocking glyph only while something is really enforced, and name what isn't covered.
