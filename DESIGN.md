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
    width: "320px"
    padding: "16px"
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

- **Display** (Light 300, 48pt, tabular figures): the time left on the dial and in the menu bar. The one big number.
- **Title** (Bold 700, 22pt): page titles: Today, Inbox, Upcoming, a category.
- **Focus** (Semibold 600, 15pt): the task the dial is about, and the reflection panel's heading.
- **Heading** (Semibold 600, 13pt): section headings inside a page, such as a day in Upcoming.
- **Body** (Regular 400, 13pt): task titles, steps, notes, fields, menu rows, durations, the line under a page title.
- **Meta** (Regular 400, 11pt, secondary): the category and step count under a task, timeline hour labels and block labels.

### Named rules
**The Six Roles Rule.** A seventh size needs a new role in `Typo` and a line here first.
**The Steady Weight Rule.** Weight belongs to the role, not the state. Selecting or running a task changes its glass, never its font weight, so text doesn't shift.
**The Tabular Rule.** Any number that changes or lines up in a column (timers, durations, counts, times) uses tabular figures.

## Layout

One window, three panes, no sidebar and no toolbar:

- **Tasks** (left, 320pt): one row of choice capsules (Today, Inbox, Upcoming, then icons for Done and Tags), each sized to its label, then the list for that choice. The control sits below the window's traffic lights.
- **Now** (middle, fills the space, at least 380pt): the task the dial is about, the dial, the time left and the controls, centred vertically. Nothing else.
- **Timeline** (right, 340pt): the day on an hour grid.

Panes sit straight on the canvas, separated by space, not lines. Categories are managed in Settings, not in the window.

Spacing uses one scale: 2 (a title and its subtitle), 4, 8, 12, 16, 24, 32. Inside a group the gap is 4 to 8; between groups 16 to 24; between page sections 24 to 32. Page margins are 24pt.

## Elevation & Depth

Depth is Liquid Glass, never shadow. Cards, the quick-add field, controls, timeline blocks and the reflection panel are `glassEffect` surfaces over the canvas and its category-tinted wash. A running task's card tints its glass with the category colour at 30%; a selected card lightens by 8% white. The only drop shadow is the system's own, under the floating reflection panel.

### Named rules
**The One Material Rule.** Surfaces are glass or canvas. No borders on cards, no custom shadows, no solid fills standing in for glass.

## Shapes

Three radii: 8pt for timeline blocks, 12pt for cards and the quick-add field, 20pt for the reflection panel. Small controls, choice capsules and the time-span label are capsules. Corners are continuous (squircle), as the system draws them.

## Components

- **Task card**: completion circle (category colour), title in Body, a Meta line with the category dot and name, its tags, the step count, then steps and notes when open. Padding 8 by 12. Clicking the title row selects it on Today and opens it everywhere else.
- **Tag**: `@name` in Meta, secondary. Tags carry no colour (the Meaning Rule): the category already colours the task. A tag groups work that spans days or weeks, such as a product or a feature, and its time is the sum of every focus block on its tasks.
- **Dial**: one turn is an hour. The wedge is the time left in the current hour; each further hour is a 2pt ring in the accent around the face. Drag to set, winding past 12 o'clock to add an hour, up to 240 minutes.
- **Quick-add field**: a 36pt glass field in Body. The parsed preview sits on the right in Meta.
- **Controls**: system glass buttons at regular size. One prominent button at a time, tinted with the accent.
- **Timeline block**: glass tinted with the category, label and duration in Meta. A planned block is a dashed outline in the category colour.
- **Choice capsules**: a row of glass capsules for picking one answer. The chosen one lightens by 15% white and its text turns primary; the rest stay secondary. They are not prominent buttons, so a view keeps one primary action. They switch the tasks pane and answer the reflection panel's questions.
- **Reflection panel**: 420pt floating glass panel. A header with the task (Focus) and time focused (Body, secondary) and a close button. Each question is a left-aligned Body label over its choice capsules. The next task is a glass row. The note is a plain field on glass, like quick add, and never takes focus by itself. The footer has a quiet "15 more minutes" on the left and Skip break (glass) and Start break (the one prominent button) on the right. Esc closes it.
- **Saved reflection reminder**: after two minutes without an answer or edit, save Made progress and Okay, keep any typed note, end the block, and hide the panel. A neutral dot pulses in the menu bar until the saved reflection is reviewed or dismissed. Reduce Motion keeps the dot still. The popover names the oldest saved reflection and offers Review and Dismiss. If several are waiting, it shows their count and presents the next one after each review or dismissal. Go → Review Saved Reflection opens the same review from the main window. Reviewing opens the same glass panel with its saved answers, note, and a Save reflection button. It edits that session only and never changes a newer timer or the task's current status. It never opens automatically. Closing or pressing Esc dismisses the reminder and keeps the saved answers.

## Do's and Don'ts

- **Do** pick a role from `Typo` for every piece of text.
- **Do** let the dial and the time left be the largest things on Today.
- **Do** use system controls, menus and SF Symbols. Where a system segmented control would be too wide (it sizes every segment to the longest), use choice capsules.
- **Don't** write `.font(.system(size:))` or a text style outside `Theme.swift`. `scripts/lint-design.sh` fails the build on it.
- **Don't** change font weight to show state.
- **Don't** add a colour that isn't a category, now or overrun.
- **Don't** strip the glass for flat fills. The flat 0.1.1 look was rejected.
- **Don't** put an eyebrow label above a heading, or use all caps for labels.
