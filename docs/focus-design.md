# Now column and Today reordering

Checked against Apple's guidance on 2 November 2026. This supersedes the "fixed-size dial" note in [workspace-design.md](workspace-design.md): the dial now follows the Now pane.

## Guidance and decisions

| Source | Guidance | Decision for Three |
| --- | --- | --- |
| [Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen) | Use extra space by adjusting proportions, without changing which items appear. | One centred column at every size. The dial grows from 240 to 400pt; text keeps its roles. |
| [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | Group related items and give the most important content prominence. | Three groups: what (task, category, current step), how long (dial, time left, status), act (controls). The task uses Title, not Focus. |
| [Drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop) | Show where an item will land, give feedback when a drop is invalid, and offer an alternative to dragging. | A neutral line marks the landing gap. Drops elsewhere and Escape do nothing. The card menu, the Edit menu and VoiceOver offer the same moves. |
| [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) and [Keyboard](https://developer.apple.com/design/human-interface-guidelines/keyboards) | Every action needs a non-pointer path; shortcuts must not surprise people who are typing. | Move Up and Move Down are VoiceOver actions on each title. Edit → Move Task Up/Down (⌥⌘↑/↓) acts only on an explicitly selected or focused Today card and is disabled while quick add has focus. |

## Now column

- **Sizing.** `diameter = clamp(min(w − 48, (h − 48) × 0.48), 240, 400)` for a Now pane of w × h. Past 400pt the 48pt time and 22pt title start to read as captions under a graphic. Tick lengths, ring spacing and the hub scale with the diameter; strokes stay fixed.
- **Placement.** Spare height splits 2:3 above and below the column, so it sits a little above centre. A ScrollView absorbs overflow at the smallest window.
- **States.** Ready, focus, paused, overrun, break, empty day and all done share the skeleton and show or hide groups. Paused shows a pause symbol and the word Paused, and the time left turns secondary. A break names the task that comes next. An empty day offers one Add Task button. All done shows the day's summary and no button, so Three never pushes a fourth task.
- **Current step.** The first unchecked step of the Now task, with its position ("2 of 3"). One click marks it done and the next one fades in (150ms, none with Reduce Motion). When every step is done it says so. Breaks, empty days and tasks without steps show no row, and Now never asks you to break a task down. Showing the next step is a product judgement that it lowers the cost of resuming work. It is not a clinical efficacy claim.
- **Input.** The dial accepts drags, focus and arrow keys only when idle with a task to start. Otherwise it is an inert picture, hidden from VoiceOver.

## Today reordering

| Concern | Decision |
| --- | --- |
| Payload | `TodayTaskDrag`, a Codable task ID exported as `com.deyalla.three.today-task`. Other apps and the pane headers use different types, so neither can be mistaken for a card. |
| Handle | The title row. The completion button and the title button keep working; a drag never selects or completes a task. |
| Where it lands | The gap is the number of cards whose middle is above the pointer, using measured card frames keyed by task ID. The destination index is computed from the latest Today rows at drop time, so a reload during the drag can't shift it. |
| Writes | One `Store.moveTask` call on a successful drop. Nothing is written while dragging, on Escape, or on a drop outside the list. Order lives only in the database. |
| Drop target | Present only while a Today card is in flight. A native spike showed that any always-present inner drop target hides the Tasks pane's own drop target from pane-header drags. |
| Feedback | The drag image is the collapsed title row on glass. A 2pt neutral line marks the gap, and none shows at the card's own position. The card's contents drop to half opacity. Opacity is applied inside the glass because a `GlassEffectContainer` ignores opacity set on its children from outside. |
| Alternatives | Move Up and Move Down in the card menu, Edit → Move Task Up/Down, and VoiceOver actions. |
| Undo | Not added. Each move is one step and is reversed the same way. |

`reorderContainer` is unavailable in the macOS 26.5 SDK, so the list uses `draggable` and `dropDestination` with `DropSession` locations.

## Review

| Before | After | Why |
| --- | --- | --- |
| A fixed 240pt dial left about half of a tall Now pane empty. | The dial scales from 240 to 400pt with the pane. | Uses the space without changing what is shown. |
| Six equally spaced items with no grouping. | Three groups with 24pt between them, placed a little above centre. | You can see at a glance what the task is, how long is left and what to do. |
| The task title was 15pt, one line. | 22pt Title, up to two lines, with the full title in a tooltip and to VoiceOver. | The task is what the dial is about. |
| The meta line repeated the card's tags and step count. | Category only, plus the next step with a one-click check. | Shows what to do next instead of a count. |
| The time span sat in a glass capsule that looked like a button. | Plain secondary text: span, Paused, or Ended at a time. | Information, not a control. |
| Empty and all-done days showed the dial and a disabled Start. | Add Task on an empty day; the day's summary when all done. | Says why and what to do next, with no dead control. |
| Today's order could change only through the CLI. | Drag a card's title row, or use the menus or VoiceOver. | Order is priority: the top open task is what the dial offers next. |

## Verification

`make test` (design lint, ThreeCore tests, and ThreeApp tests including `TodayOrderTests`) and `make build`. Three ThreeCore tests used to fail in the first hours after local midnight because their sessions started a couple of hours before now; d5c8773 made them independent of the current day, and the full suite passed at 01:19 IST on 2026-11-03. Native QA used a relabelled copy (`com.deyalla.three.designqa`) on scratch databases: compact 1060×640 and full screen, idle, running, paused, overrun, break, empty day, all done, a long title, step completion, AX winding to the 4-hour cap and back, drags top to bottom and bottom to top, Escape, drops on Now and Timeline, a pane-header drop over the list, the card menu, the Edit menu, and VoiceOver actions. Screenshots and notes are in `build/verification/focus` (local only).

Not verified natively: dial winding by pointer drag and arrow keys. Synthetic events in the QA harness don't reach those on this build or on 888d3a2; AX increment and decrement were used instead. No independent review was run.
