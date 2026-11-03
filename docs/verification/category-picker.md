# Category picker redesign

The category control now sits below the task title as a small color chip. Task cards use the same control. An anchored native popover shows color dots, names and the current selection. The title retains the full entry width.

Emil's design engineering skill informed the hierarchy, quiet controls, immediate keyboard response and native verification. Experience First put the title before metadata. Model the Domain retained the existing Category model and capture precedence. Prove It Works required native interaction and persisted SQLite values.

| Before | After | Reason |
| --- | --- | --- |
| Fixed dropdown inside the title row | Category chip in a metadata row | Keep the title readable in a narrow pane. |
| Plain category names | Color dots and a selected checkmark | Match the category identity used on cards and the dial. |
| Category changes through a nested task menu | Click the category on the card | Use one interaction before and after task creation. |

A permanent strip of all categories was rejected because it would consume the task pane and grow with user-defined categories. The popover uses native buttons and focus, with explicit arrow-key navigation. The existing Store remains the write owner. No database or protocol contract changed.

## Verification

The previous menu-stability and Planning fixes were integrated as `bafdd6d`, `0760ed2`, `b5d7834`, `fa8b321`, and `bf002e7` before this change. The baseline and final `make test` runs passed 134 Core, 29 App and 22 extension tests. Design lint passed. `./scripts/bundle.sh` and `codesign --verify --deep --strict build/Three.app` passed.

Native verification used `com.deyalla.three.categoryqa` with its own database under `build/category-picker/`. Open-file inspection confirmed the isolated database path.

| Native check | Result |
| --- | --- |
| Choose Writing with Down and Return | PASS. The chip updated and title input regained focus. No task was created by selecting a category. |
| Create `Write launch brief 25m` | PASS. SQLite stored Writing and 25 minutes. |
| Change the existing task through its category chip | PASS. Learning appeared on the card and dial and persisted in SQLite. |
| Type `Prepare outline #admin 15m` in Inbox | PASS. The chip showed Admin and the metadata showed 15m and Inbox. |
| Open the picker and press Escape | PASS. The title and Admin selection remained unchanged. |
| Choose Writing after typing `#admin`, then click Add | PASS. The Inbox task persisted with Writing and 15 minutes. |
| Keep the task's category popover open during real focus | PASS. It remained open from 24:51 to 23:37 as the day summary reached 1m focused. Choosing Writing then updated the task. |

Artifacts include `baseline-tests.log`, `final-tests.log`, `build.log`, `signing.log`, `category-popover.png` and `native-results.json` under `build/category-picker/`.

The isolated focus session ended. No authenticated model command ran. macOS 26, VoiceOver, native menu-bar interaction and minimum-width dragging are not accepted by these checks. The attempted pane drags did not resize the native split view. BPRO-396 retains its existing release gates.

Exploration, design, implementation and review ran sequentially in-thread under the user's AGENTS.md. No delegates or independent model review ran. No PR or push was requested.
