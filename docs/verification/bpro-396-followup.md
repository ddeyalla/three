# BPRO-396 follow-up native evidence

Three needs physical native proof for the frozen v0.3 blocker. This follow-up closes the physical running and paused menu-bar pixel check. **BPRO-396 remains BLOCKED.** The actual status popover, automatic Chrome recovery, macOS 26 runtime, and physical hide refusal remain unaccepted. No new blocker product defect was proven.

Read this report with [the original verification](bpro-396.md). The prior ordinary blocker results were not rerun or relabelled as fresh evidence.

## Frozen executable and isolation

The only writable checkout was `/Users/divyanshudv/.t3/worktrees/adhd/t3-25eb1c32`, branch `t3/bpro-native-qa`. The frozen input was read-only `/Users/divyanshudv/.t3/worktrees/adhd/t3-59968077/build/Three.app`. That worktree is at `b3d3c20dc5a9f6dce47fbeeb9016c360aeccb4c8`. Its product source has no diff from `d993f48` for Sources, Tests, Extensions, Package.swift, and VERSION. `frozen-product-source-diff.txt` records the command and exit 0.

The input executable SHA-256 is `e3ca87a1f2c52373379a60efeea7dd00bf3430658f4e7e7a39f32752ed4fb12d`, matching the original report. Prepared `Three B396Follow QA.app` has ID `com.deyalla.three.b396followqa` and executable `ThreeB396FollowQA`. Relabelling and signing preserved all `__TEXT,__text` instructions. Their hash is `fd5b9e659c5873f2fae2bf6e2073b1c9fdeee77560c4e8b32e721ad849cc3845`.

Every artifact below has this absolute base.

`/Users/divyanshudv/.t3/worktrees/adhd/t3-25eb1c32/build/verification/bpro-396-followup/`

`native/run.json` distinguishes the preparation checkout from the frozen executable source. QA PID 68448 opened only `native/three.sqlite`. `qa-open-files.txt` and `process-running.txt` prove that boundary. The Work fixture PID was 71908. BPRO-398 QA apps were already stopped before this app launched. The host is macOS 27.0.1, not macOS 26. All work ran in-thread on `codex/gpt-6.1-sol`, High, with no children.

## Physical menu-bar pixels now observed

`CGPreflightScreenCaptureAccess()` returned true. No permission request or elevated action was needed. `display.txt` and `cg-display-bounds.txt` record the three display frames. The relevant menu bar was on the display with global origin `(-1080,-1080)` and size 1920 by 1080.

The capture command was `screencapture -x -R -1080,-1080,1920,38 <artifact.png>`. These are physical display pixels, not an AppKit image rendered offscreen. The primary-display strip was insufficient because the QA status item was on the other display.

| State | Physical result | Evidence |
| --- | --- | --- |
| Idle | A circular timer symbol appeared at the QA item's observed native position. | `physical-left-idle.png`, `status-ax-inventory.txt` |
| Running | Native Start began QA ordinary focus. The physical menu bar showed the blocker hand symbol and `44:46`. Native AX named `QA ordinary focus, 44:46, Blocking until 8:33 AM`. | `physical-left-running.png`, `status-ax-running.txt`, `process-running.txt` |
| Paused | Native Command-Shift-P paused the timer. Physical pixels showed the blocker symbol and `Paused 43:46`. | `physical-left-paused.png`, `status-ax-paused.txt` |
| Stopped | The scratch CLI stopped the timer. The native planner returned to Start and native status AX returned to `Next: QA ordinary focus`. | `final-stop.log`, `status-ax-stopped.txt` |

The stopped-state strip captured browser tabs after the foreground changed, so it was excluded and removed. `stopped-capture-excluded.txt` records that decision. There is no accepted stopped-state physical image.

## Actual status popover still blocked

The read-only native AX inventory found a second `AXMenuBar` owned by PID 68448. Its actual status element exposed `AXPress` and the exact QA task name. Initially its rectangle was x 122, y -1076.5, width 33.5, height 24 in global desktop points. During focus it expanded to width 76.5.

CUA's click at the observed physical location returned `Computer Use server error -10005: windowNotFoundAtPosition((138.5, -1064.5))`. The requested alternative native AX method then pressed the exact observed status item. `AXUIElementPerformAction` returned 0. No popover became visible. This was also attempted after the owned Work fixture's Open Three QA button established real foreground activation. `foreground-before-status.txt` records `active=true` for QA.

`status-actions.txt`, `status-press.log`, `status-second-press.log`, `status-foreground-press.log`, `windows-after-press.txt`, `windows-immediately-after-press.txt`, and `windows-foreground-status.txt` record the attempts. `physical-status-popover-attempt.png` shows no open popover at the observed status location. CUA continued to expose the main window. No timer, pause, stop, or unblock control inside the status popover was operated. A successful accessibility return code alone is not acceptance proof.

The menu-bar label and its physical pixels passed independently of that missing popover interaction. This run does not infer a SwiftUI product defect from the unsuccessful automation action.

## Bounded disposable Chrome profile investigation

The browser was the already-existing `/private/tmp/three-browser-be27e10e/unpacked/chrome-mac-arm64/Google Chrome for Testing.app`, version 156.0.8078.80. No browser was downloaded or installed. No real Chrome profile was opened, copied, or edited.

The frozen packaged helper ran `block connect-chrome --chrome-folder <absolute native/chrome path>` with `THREE_DB` set to this run's scratch database. That wrote the ordinary Three native-messaging configuration and extension copy into this run's scratch directories. `connect-chrome.log` records both paths. No Three extension manifest or browser policy was modified.

| Trial | Exact additional launch flags | Observed result |
| --- | --- | --- |
| New disposable profile | `--user-data-dir=<artifact base>/native/chrome --no-first-run --no-default-browser-check chrome://extensions/` | Chrome started as PID 76579. Native navigation reached the Extensions URL, but its content was blank. Reload remained blank. The log reported `Requested load of chrome://newtab/ for incorrect profile type.` |
| Same disposable profile after native Quit | Same flags plus `--profile-directory=Default` | Chrome started as PID 85553. Native Extensions navigation again produced blank page content. The same profile-type error appeared in the new log. The native profile menu showed an unsigned-in profile with Customize Profile and Open Guest Profile actions. |

`chrome-launch-process.txt`, `chrome.log`, `chrome-profile-after-first-exit.json`, `chrome-explicit-profile.log`, and `chrome-explicit-profile-blank.png` with AX retain the evidence. Both browser instances were quit through their own native Quit menu before cleanup. The final profile stayed under the scratch artifact directory.

These trials failed before extension loading and the connected precondition. They do not reproduce the prior Developer-mode-off-on-restart observation, establish its cause, or prove an unpacked-extension platform policy. This run therefore cannot decide whether automatic recovery needs a Three fix. It records a new browser fixture blocker and leaves the recovery gate open. There was no repeated flag guessing after the explicit-profile retry.

## Remaining gates and cleanup

1. Operate the actual frozen status popover and prove its timer, pause, stop, and unblock controls.
2. Establish a working disposable native Chrome profile, then prove extension and connection persistence through a clean browser restart. The previous Developer-mode reset remains unexplained.
3. Run on macOS 26. The 26.5 SDK and macOS 27 execution do not satisfy that runtime gate.
4. Obtain a physical OS hide-refusal result if that acceptance remains required. Existing automated refusal-state proof is separate from real OS behavior.
5. Parent acceptance and release authorization still precede release metadata, tag, install, and publication.

The final preservation result is `/Users/divyanshudv/.t3/worktrees/adhd/t3-25eb1c32/build/verification/bpro-398/cleanup-and-preservation.json`. It records zero remaining owned QA, fixture, browser, or native-host processes. Production database table fingerprints, the installed executable, native-messaging manifest state, PID 92331, and local start time `2026-11-03 06:22:12` all matched the baseline. No global setting changed. Clipboard contents were restored after the BPRO-398 Copy checks. No production launch or restart, live provider, broad kill, release, push, or tag occurred.
