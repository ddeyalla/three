# BPRO-396 bounded fresh status probe

Three still needs acceptance of the frozen v0.3 status popover. **COULD NOT RUN its controls.** One materially different direct native mouse attempt produced no observed popover. This does not establish a product defect or close BPRO-396.

The BPRO-399 correction checks and native draft review completed first. Its QA app quit before this probe began. Only the prepared review worktree `/Users/divyanshudv/.t3/worktrees/adhd/t3-6b0bc9e3` was writable. This probe ran in-thread on `codex/gpt-6.1-sol`, High, without children.

## Frozen artifact and isolation

The input was read-only `/Users/divyanshudv/.t3/worktrees/adhd/t3-59968077/build/Three.app`, product source `d993f48`. Its executable SHA-256 matched the earlier frozen report exactly:

`e3ca87a1f2c52373379a60efeea7dd00bf3430658f4e7e7a39f32752ed4fb12d`.

The scratch copy was `build/final-review/frozen396/Three B396 Fresh QA.app`, executable `ThreeB396FreshQA`, bundle ID `com.deyalla.three.b396freshqa`, PID 98621. Relabelling and signing preserved every executable instruction. Its `__TEXT,__text` hash was `fd5b9e659c5873f2fae2bf6e2073b1c9fdeee77560c4e8b32e721ad849cc3845`. Strict signature verification passed. `run.json` records the frozen input separately from the current review branch.

The helper seeded only `Fresh frozen status QA` in the scratch SQLite database. The app used that database and an empty scratch Chrome-data directory. No browser or distraction fixture was launched. No timer was started.

## Single direct mouse attempt

All evidence paths below are relative to `build/final-review/frozen396`.

`status-probe.swift` read the actual QA AX tree. Existing AX trust, event-posting access, and screen-capture access all returned true. It requested no permission.

The actual status element was `Next: Fresh frozen status QA`. Its observed global rectangle was x=2682, y=-1436.5, width=33.5, height=24. The current display arrangement differed from the earlier report, so the previous negative coordinates were not reused.

The command `status-probe 98621 click` posted exactly one native CGEvent mouse-down and mouse-up pair at the observed center `(2698.75, -1424.5)`. It used the existing event-posting permission and avoided CUA's negative-window lookup. It did not substitute AXPress.

The post-action AX window list still contained only the main Three window. CUA likewise reported the unchanged main window. No popover, menu, or timer control became visible. `status-before.log`, `status-click.log`, `after-click-ax.txt`, and `after-click-main-window.png` record the result. The screenshot is the main window, not evidence of a working popover.

No second mouse attempt, repeated AXPress, browser-profile trial, or privilege prompt followed. Timer, pause, finish, and unblock controls inside the actual frozen popover remain unaccepted. The macOS 26 runtime and physical OS hide-refusal gates also remain open. The host was macOS 27.0.1.

## Cleanup

Native Command-Q stopped PID 98621. No timer was created. `build/final-review/cleanup-and-preservation.json` records zero owned processes and no future writes. Production PID 92331, its start time, installed executable hash, and database fingerprints matched the BPRO-399 baseline exactly. No production or browser profile was operated. Desktop ownership is released. Parent integration, acceptance, and release decisions remain with the parent.
