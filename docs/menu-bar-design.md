# Menu bar, Focus menu Unblock and prominent buttons

Checked against Apple's documentation on 3 November 2026, then measured in native probes on macOS 27 built with the pinned 26.5 SDK. The probes and their raw output are in `build/verification/final-ui/` when a checkout has run them.

## Guidance and decisions

| Source | Guidance | Decision for Three |
| --- | --- | --- |
| [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) | Always show the same menu items, and disable an item that isn't actionable rather than hiding it. The system hides menu bar extras when space runs out. Avoid relying on a menu bar extra, and expose its functions in other ways too. | Unblock for 5 Minutes is also in the Focus menu, always listed and disabled when nothing can be opened. The menu-bar item shows a symbol and the time, not the task, so it takes as little room as possible. |
| [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) | With a system image, the title "will be used by the accessibility system". | A `Label` shows only its icon, so the old timer label never showed its text. The label is an image and a `Text`, with an explicit accessibility label. |
| [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Text up to 17pt needs 4.5:1 contrast. Check contrast with standard calculators. | Prominent button labels are measured on the rendered glass, not on the palette. |

## What the menu bar draws

A probe app inserted label variants and read each one back three ways: the accessibility tree, the `NSStatusBarButton` AppKit holds, and an offscreen render of that button.

- `Label(title, systemImage:)` becomes an image with no title. Its accessibility title is the symbol's name ("Timer"), not the label text.
- `Text`, an `HStack` of an `Image` and a `Text`, and a `Label` with `.labelStyle(.titleAndIcon)` all become the button's title, in the 13pt system font.
- `.monospacedDigit()` is dropped. "11:11" is 48pt wide and "00:00" is 57pt, with or without it, and a running clock changed the item's width between consecutive seconds.
- `.resizable().frame(width: 6, height: 6)` and `.opacity` on the image are dropped. The reminder dot drew as a full 15pt circle at full opacity, so it never pulsed. Swapping the symbol (`circlebadge.fill` and `circlebadge`) does change the item every second. `circlebadge` draws at 12pt.
- A second `Image` is dropped.
- `.accessibilityLabel` on the label becomes the item's accessibility title.
- On this MacBook's notched menu bar only part of the probe's items got a place; the rest were parked off screen at `(0, -39)`.

On macOS 27 the window list shows no status-item window for the app, and a capture of the system's menu bar window shows no items, so no window-only capture can show them. The evidence is the accessibility tree, AppKit's button state and the offscreen render.

## Prominent button contrast

`.glassProminent` buttons tinted with every category colour, idle grey and a dark custom colour were captured in a key window, converted from Display P3 to sRGB, and measured as the fill's most common colour against the label's core.

| Tint | Rendered fill | White label | Dark label |
| --- | --- | --- | --- |
| coral #F2766B | #FC6C64 | 2.81 | 6.86 |
| cornflower #6E9BF2 | #609CF8 | 2.76 | 6.99 |
| ochre #E5A84B | #F0A434 | 2.09 | 9.24 |
| jade #4FBF8B | #00C088 | 2.36 | 8.17 |
| lavender #A58AF0 | #AC88F4 | 2.77 | 6.96 |
| teal #5CC6D0 | #18C8D0 | 2.06 | 9.38 |
| rose #E57BB5 | #F474B8 | 2.61 | 7.38 |
| sand #B8A27A | #BCA074 | 2.49 | 7.73 |
| idle #8C8C8C | #747474 | 4.67 | 4.13 |
| navy #23305E (custom) | #1C3060 | 12.58 | not measured |

- The glass renders categories brighter and more saturated than the palette, and idle grey darker. Arithmetic on the palette would have put a dark label on idle, where it fails.
- `.foregroundStyle` on the button is ignored while the tint shows. It has to be on the label content. A wrapping `PrimitiveButtonStyle` does that, keeps one accessibility button, and fires a `.defaultAction` shortcut exactly once.
- In an inactive window the system draws every prominent button as grey glass with a grey label (2.22:1 measured), the same with or without the style. Disabled buttons look the same. The style leaves both alone.
- The glass is tinted only in the key window, and `controlActiveState` doesn't say which that is. The reflection panel is a non-activating floating panel. Before it's clicked, with Three active and its main window key, its Start break drew grey glass but still got the dark label, 1.86:1, whether the style checked `controlActiveState != .inactive` or `== .key`: SwiftUI reported that unfocused panel as key. Once the panel was key the same button measured 7.03:1. So the style reads its window's own key status (`NSWindow.isKeyWindow`, updated on become and resign key) and otherwise leaves the system's label.
- Increase Contrast was not tested; changing it is a global setting.
