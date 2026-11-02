# Reorderable workspace

Research checked against Apple's documentation on 2 November 2026.

## Guidance and decisions

| Source | Apple guidance | Decision for Three |
| --- | --- | --- |
| [Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen) | Use additional space, preserve essential controls, and keep transitions between modes familiar. Use the system full-screen experience. | Remove the 1240pt workspace cap. Keep the same three panes and native full-screen controls at every size. |
| [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) and [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | Adapt fluidly to resizing. Preserve native window chrome and safe areas. Test the smallest and largest layouts. | Keep traffic lights, establish usable pane minimums, and verify a compact window and native full screen. |
| [Split views](https://developer.apple.com/design/human-interface-guidelines/split-views) | Mac split views can expose draggable dividers. Size limits should keep panes and dividers usable. | Use a native NSSplitViewController for resizing. Tasks, Now and Timeline are peer work areas, not a navigation hierarchy. |
| [Panels](https://developer.apple.com/design/human-interface-guidelines/panels) | A Mac panel is an auxiliary window for supplementary controls or information. | The supplied reference calls for movable panes within the main window. Separate NSPanel windows would add window-management work without helping this layout. |
| [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) | Liquid Glass separates controls from content. Standard materials give content structure. Avoid layering glass on glass. | Use translucent system material for pane bodies, with titles and header icons directly on that material. Preserve Three's existing glass controls, cards and dial as a deliberate product preference; do not claim every existing content surface follows Apple's stricter guidance. |
| [Drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop) | Show a valid destination, clear feedback on exit, and offer alternatives to dragging. Moves should be reversible. | Native drag sessions move a pane only on drop. A neutral highlight identifies the receiver. Header and View menus offer the same moves. Reset restores default order. |

The rounded pane appearance, exact insets, persisted order and fixed-size dial are Three-specific decisions, not Apple-prescribed dimensions.

Pane headers now show only the title, drag grip and menu icon, as requested after the initial workspace review. Native divider lines are not drawn. Their geometry, resize cursor and hit areas remain unchanged through AppKit's `drawDivider(in:)` customization point.

## Shape and ownership

The workspace contains exactly one Tasks, Now and Timeline pane. An app-owned layout preference validates stored order, performs moves, and restores defaults. Native NSSplitViewController owns divider interaction. Each pane keeps one NSHostingController for its lifetime. Existing views and AppModel continue to own task drafts, selection and timer state. Reordering changes presentation only.

| Candidate | Assessment |
| --- | --- |
| HSplitView with stable pane identities | Tried first. Native verification found a quick-add draft was cleared after reordering/reset despite stable ForEach IDs. Rejected after that failure. |
| NSSplitViewController with retained hosting controllers | Chosen. Native sizing and dividers, existing SwiftUI views, and pane view lifetimes independent of order. |
| Custom draggable and resizable canvas | Rejected. Requires collision rules, manual sizing, focus handling and extra accessibility work for three peer panes. |
| Three separate NSPanel windows | Rejected. Auxiliary windows do not match the supplied one-window reference and complicate full screen. |

## Review

| Before | After | Why |
| --- | --- | --- |
| Workspace stops growing at 1240pt. | Three pane surfaces fill the window with small consistent insets. | Full screen uses available space. |
| Fixed task and timeline widths. | Native adjustable dividers with readable minimum widths. | People choose how much room each task needs. |
| Pane boundaries are implied by empty space. | Rounded translucent bodies with plain headers. | Clear grouping matches the reference while retaining glass. |
| Tasks, Now and Timeline have fixed positions. | Drag headers or use menu commands, with saved order and reset. | Personalization remains discoverable and accessible. |
| Header backgrounds and persistent divider lines add extra boundaries. | Plain titles and icons above the content, with clean resizable gaps. | The rounded pane bodies already provide separation. |

Implementation and review run in-thread under the user's AGENTS instructions. No independent model review is claimed.

## Verification

`make test` passes design lint, 51 core tests, and 3 workspace tests. `make build` passes. Native QA covers compact and full-screen layouts, header dragging, all six pane orders, reset, persistence across relaunch, and opening Settings. Draft text, a non-default timeline scroll position, and the paused timer survive a move and reset. The user confirmed pointer divider resizing after automated pointer dragging was inconclusive.

Local screenshots and detailed evidence are in `build/verification/workspace/README.md`. Cancelled drops and a complete keyboard-only traversal were not exercised manually.
