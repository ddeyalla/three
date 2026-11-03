# BPRO-396 native blocker verification

Three needs release proof for the completed v0.3 blocker. This run verifies the frozen executable and prepares review evidence without installing or publishing it.

Verdict is **BLOCKED for release**. The ordinary native blocker flow passed. The status-item popover and physical menu-bar pixels remain unverified. No product defect was proven. VERSION stays at 0.2.4 and CHANGELOG stays Unreleased.

## Frozen inputs and scope

| Input | Value |
| --- | --- |
| Worktree | `/Users/divyanshudv/.t3/worktrees/adhd/t3-59968077` |
| Branch | `t3/bpro-396-native-verification` |
| Initial HEAD | `0b75f0103f74b2ea4fe264c6d6e4fc006d8a0783`, clean |
| Executable source | Identical to `d993f48` for Sources, Tests, Extensions, scripts, Package.swift, and VERSION |
| Runtime | macOS 27.0.1, build 26A434, arm64 |
| Build SDK | macOS 26.5 through `scripts/swift.sh` |
| Model | In-thread `codex/gpt-6.1-sol`, High. No agents. |
| Artifact directory | `build/verification/bpro-396/` in this worktree |
| QA database | `build/verification/bpro-396/native/three.sqlite` |
| QA app | `build/verification/bpro-396/native/Three B396 QA.app`, `com.deyalla.three.b396qa` |
| QA browser | Existing Google Chrome for Testing 156.0.8078.80, disposable `native/chrome` profile |

The parent checkout `/Users/divyanshudv/Documents/code-deyalla/adhd` was read only. I read BPRO-396 in Linear, PRODUCT.md section 7, README's versioning convention, and the parent's `build/verification/final-ui-completion/README.md` before verification.

The workflow was isolation and baseline, native return first, ordinary reason and expiry flow, Chrome setup, strict tasks and focus hours, preservation, then release-gate review. Failed preconditions were retried within that scope. There was no product implementation change.

## Fresh automated results

Paths in this report are relative to the artifact directory unless an absolute path is given.

| Executed command | Result | Evidence |
| --- | --- | --- |
| `make test` | Exit 0. Design lint, 96 Core tests, 19 App tests, and 22 Node tests passed. No Node skips. | `make-test.log` |
| `CONFIG=release ./scripts/bundle.sh` | Exit 0. 0.2.4 build 65. | `release-build.log` |
| `codesign --verify --deep --strict --verbose=2 build/Three.app` | Exit 0. Valid on disk and satisfies its designated requirement. | `codesign.log` |
| `node scripts/native-host-check.mjs build/Three.app/Contents/Helpers/three --timer`, with a scratch TMPDIR | Exit 0. All 13 checks passed, including protocol rejection, timer updates, and the actual bundled launcher. | `native-host-check.log` |
| `python3 scripts/verification/bpro-396-qa.py prepare --run-name preparation-check` | Exit 0. Final script compiled both fixtures, seeded its own database, signed its relabelled app, and verified unchanged executable instructions. It did not launch anything. | `prepare-final-script.log` |
| Production and settings comparisons | Every production table fingerprint, protected binary and Chrome manifest hash, production PID/start time, and display switch value matched. | `preservation-result.json` |

Build warnings concern the existing formatter isolation annotation and missing Command Line Tools linker search directories. They did not fail the commands.

## Fresh native results

All UI actions used native CUA. AppKit observations and fixture notification logs establish actual process state. A CUA window or accessibility tree alone was not accepted as foreground-activation proof.

| Gate | Observed result | Evidence |
| --- | --- | --- |
| Settings and Chrome connection | Set Up Chrome displayed the two scratch paths. Add Connection showed Added. Native Chrome Developer mode and Load unpacked loaded extension 0.3.1 with the fixed ID. Three showed Connected in 1 profile. | `chrome-setup-before.png`, `chrome-setup-added.png`, `chrome-extension-loaded.png`, `chrome-connected-native-settings.png` and matching `.ax.txt` files |
| Focus and website block | Native Start began QA ordinary focus. Navigating to `https://example.com` showed its real extension block page with the task and Until time. | `chrome-ordinary-block-page.png` |
| App hide without quit | The owned distraction fixture became active, hid, and remained PID 49418. Its overlay named the task and the blocked app. | `blocked-app-overlay.png`, `native/blocked.log` |
| Return after switching overlay through the menu | Work PID 54948 was activated through LaunchServices. Opening the distraction showed its blocked overlay. The work fixture's Open Three QA button made QA PID 45446 genuinely active. Focus, Unblock for 5 Minutes, and the app row switched the existing overlay. Back to work made Work active and kept the distraction hidden. | `return-before-menu.txt`, `return-just-before-cancel.txt`, `return-menu-unblock.png`, `return-after-cancel.txt`, `returned-work-fixture.png` |
| Cancel preservation | Every scratch table fingerprint matched before and after that Back to work action. No exception was created. | `preservation-verified-cancel-before.json`, `preservation-verified-cancel-after.json` |
| Reason validation | Two words left Start 20-second wait disabled. Three words enabled it. | `reason-too-short.png`, `wait-started.png` |
| Wait and deliberate grant | The real disabled 0:20 countdown completed. Return left the panel open and created no exception. A final click created exactly one session-bound exception with reason `Check required reference` and a 300-second interval. The same distraction process unhid. | `wait-finished-return-does-not-grant.png`, `native-grant.json`, `granted-distraction-visible.png`, `grant-app-state.txt` |
| Normal five-minute expiry | No clock or SQL change. Grant at 01:26:49.809 UTC expired at 01:31:49.809. The fixture logged hidden at 01:31:50.297. PID 49418 remained alive and hidden. Settings again reported Chrome and apps. | `native/blocked.log`, `expiry-observation.txt`, `exception-expired-native-settings.png` |
| Pause and resume | Pausing kept blocking and changed Chrome to Paused with the 15-minute bound. Resume restored the countdown. | `ordinary-paused.ax.txt`, `chrome-resumed-block-page.png`, native-host test log |
| Finish and next strict task | Native Finish opened Reflection. Skip break ended ordinary focus and started QA strict focus. Its native app overlay omitted Unblock, and Chrome said unblocking was off for the task. | `strict-focus-started.png`, `strict-blocked-app-overlay.png` |
| Strict task can finish | Finish opened Reflection and Start 5m break ended the strict session normally. | `strict-ended-break.png` |
| Focus hours | The native editor saved Tuesday 07:04 to 07:05. During the break, both Chrome and the app overlay named Focus hours. The real wall-clock boundary ended blocking. Chrome changed to isn't blocked right now and offered the site's front page. | `focus-hours-added-native.png`, `focus-hours-block-page.png`, `focus-hours-app-overlay.png`, `focus-hours-expired-block-page.png` |
| Native app restart | QA exited and relaunched against the same scratch DB. Planner, session, rule, focus-window, category, and tag table fingerprints matched. The ongoing timer returned. | `qa-closed-pids.txt`, `preservation-before-restart.json`, `preservation-after-restart.json` |
| Chrome works with Three closed | A second closed-app check navigated anew to example.com during focus hours and received the block page. No QA PID was running. The real native host remained a child of owned Chrome and opened only the scratch database. | `chrome-blocks-while-qa-closed-final.png`, `qa-closed-native-host.txt`, `native-host-open-database.txt` |
| Connection loss | The owned Chrome Quit menu closed its browser and host processes. After the actual lease lapsed, native Blocking settings reported Apps only. Websites aren't blocked. | `chrome-disconnected-after-lease.png` and matching `.ax.txt` |
| Manual reconnect | Restoring Developer mode in the same disposable Chrome profile re-enabled the unpacked extension and swept the already-open example.com tab to the block page. Automatic recovery did not pass. | `chrome-manual-recovery-block-page.png` |
| Final end-focus | The scratch CLI stopped the final ordinary session. The open Chrome page changed to isn't blocked right now. Work's Open distraction control brought the same distraction PID forward, active and not hidden. | `final-stop.log`, `end-focus-clears-block-page.png`, `end-focus-app-state.txt` |
| Removal after focus | Native rule, hours, and connection removal controls became enabled. Confirming Remove Connection deleted only the scratch native-messaging manifest. The still-open native port continued to report connected at that instant. | `connection-removed-after-focus.png`, `connection-removal-result.json` |
| Increase Contrast | Enabled through System Settings, inspected the readable native Blocking view, then restored off. Other display switches remained unchanged. This is a limited visual check, not a full accessibility audit. | `accessibility-display-before.ax.txt`, `accessibility-display-on.ax.txt`, `increase-contrast-blocking-settings.png`, `accessibility-display-restored.ax.txt`, `preservation-result.json` |

Initial CUA background clicks did not establish actual QA activation. Those attempts were inconclusive. The fixture's LaunchServices buttons supplied the missing precondition, and the successful return run recorded both foreground states. No activation result was inferred from a screenshot.

One Chrome keyboard attempt dropped the first character of the URL. It was not counted. The successful closed-app retry used native paste after observing address-bar focus. `chrome-blocks-with-three-closed.png` is that incomplete attempt and is not acceptance evidence. Use the `-final` artifact above.

Chrome's first Command-Q did not terminate its process. Its native Quit menu did. The process check, rather than the attempted shortcut, defines the disconnection boundary. No separate Chrome permission prompt appeared during unpacked loading.

## Inspected prior proof

These results were read, not rerun or relabelled as fresh native proof.

- Parent `build/verification/final-ui-completion/README.md` and `/tmp/three-final-ui-astra-20261103/` document prior main-window menus, exception availability, and fixture expiry.
- `/Users/divyanshudv/.t3/worktrees/adhd/t3-b485cbdc/.audit/REPORT.md` records real Chrome DNR, page, strict-task, expiry, and history behavior at `eaa8cd2`. Extensions, NativeHost.swift, NativeMessaging.swift, and Blocker.swift have no diff from that revision to the frozen source.
- `/Users/divyanshudv/.t3/worktrees/adhd/t3-be27e10e/.audit/REPORT.md` records the earlier two-profile, permission-change, legacy-list, native-host-loss lease, and reconnect matrix. Host loss really killed only matched scratch host processes and waited for the lease. This run does not claim a fresh host-loss browser experiment.
- Parent `build/verification/integration-fixes/README.md` records failed-hide and queued-overlay probes using AppKit recording doubles. Physical hide refusal was not forced on this Mac. Fresh `failedAppHidingChangesCoverageWithoutHidingWorkingChrome` verifies the coverage state, not an OS hide refusal.
- Fresh Store tests include rule-removal protection and `connectionRemovalHoldsTheWriterLockDuringItsPolicyCheck`. The latter attempts the opposing writer while removal holds the lock, then checks the reverse ordering. Existing preservation and migration tests passed in `make test`.

## Missing release proof

1. The status-item popover could not be operated. CUA exposed only the app's main menu and windows. Control-F8 made no change. Binding `com.apple.systemuiserver` and `com.apple.controlcenter` each returned `Computer Use server error -10005: timeoutReached`. No status-item control was clicked.
2. CUA's app screenshot captured the selected window, without physical menu-bar pixels. Main-menu actions and window screenshots do not prove the timer text or blocking symbol in the physical menu bar. Prior status-button values and offscreen renders do not close this gate.
3. No macOS 26 runtime is available on this macOS 27.0.1 host. The 26.5 SDK and deployment target do not prove runtime behavior on 26.
4. Physical hide refusal remains simulated in prior probes. This run verified normal hiding, unhide, rehide, and native coverage text, but did not manufacture an OS refusal.
5. Automatic Chrome restart recovery did not pass in this fixture. After restart, the native Extensions page showed Developer mode off and the extension disabled. CUA also reported Safety Check text, Off and Chromium can't verify where this extension comes from. A newly opened example.com tab loaded while Three briefly retained its previous connection report within the lease. Re-enabling Developer mode restored the extension and swept that tab. `chrome-restart-disabled-extension.png` shows the disabled extension and its scratch source path. `chrome-reconnected-block-page.png` shows the unblocked site, despite that attempted-capture filename. The cause of the Developer mode change was not isolated. This is an observed Chrome for Testing fixture gap, not a proven Three code defect or proof about an ordinary Chrome profile.

Do not mark BPRO-396 Done. Parent review and the remaining native gates precede release metadata, tag, installation, and publication.

## Artifact and safety

The local build is `build/Three.app`, 0.2.4 build 65, compiled at frozen HEAD `0b75f01`. It is ad-hoc signed, has no TeamIdentifier, and is not notarized. Its app executable SHA-256 is `e3ca87a1f2c52373379a60efeea7dd00bf3430658f4e7e7a39f32752ed4fb12d`. See `artifact-fingerprint.txt` and `signing-identity.log` for the helper, plist, and icon hashes.

The QA copy has the same `__TEXT,__text` hash as that build. Relabelling initially lost the shell helper's signature during copying. Signing each copied helper before the outer bundle fixed the QA setup. The original build's strict signature verification had already passed. `prepare.log` preserves the failure and `prepare-final-script.log` proves the corrected script.

There is no 0.3.0 distributable, version bump, release tag, push, GitHub release, or installation from this run. The gate is incomplete, so producing a release-labelled package would misstate the evidence.

Production PID 92331 and its original 2026-11-03 06:22:12 local start time were preserved. Every production database table fingerprint and the installed executable and real Chrome native-messaging manifest hashes matched. No production app was quit or restarted. Browser UI used only the disposable Chrome for Testing profile. The ordinary Chrome profile was not operated.

Cleanup matched each owned executable path immediately before SIGTERM. It stopped QA PID 72385, Work PID 54948, Chrome for Testing PID 90628, and native host PID 99942. The distraction fixture was already absent when cleanup began. `cleanup.json` records those exact paths and zero remaining owned processes, including either fixture. Production PID 92331 retained its original start time. The scratch databases, profiles, screenshots, and bundles remain for review. No owned process remains running.

## Reusable verification setup

`scripts/verification/bpro-396-qa.py` owns preparation, database fingerprints, and process/database inspection. Its run manifest contains exact app, CLI, scratch DB, browser, fixture, source, and executable-instruction hash values. Preparation refuses to overwrite an existing run. `--run-name` creates another directory under this worktree's audit directory.

`scripts/verification/bpro-396-fixture.swift` owns the document-free Work and Distraction apps. Work's LaunchServices buttons establish actual activation, rather than assuming a CUA background AX action changed the foreground app. Neither script installs or launches production Three.

The executed setup commands were:

```sh
python3 scripts/verification/bpro-396-qa.py capture before-native
python3 scripts/verification/bpro-396-qa.py prepare
open -n --env THREE_DB="$PWD/build/verification/bpro-396/native/three.sqlite" \
    --env THREE_CHROME_DATA="$PWD/build/verification/bpro-396/native/chrome" \
    --env THREE_OPEN=blocking 'build/verification/bpro-396/native/Three B396 QA.app'
python3 scripts/verification/bpro-396-qa.py inspect
```

Use native CUA for the UI steps. Confirm actual foreground state before claiming a return test. Do not use `make run`, `make install`, or unscoped `pkill`, because those target production processes.

## Review handoff

The decision trail is `docs/verification/bpro-396-decisions.tsv`. Prove It Works kept return and expiry claims tied to actual AppKit state. Build the Lever produced the reusable isolated setup. Model the Domain kept paths and source identity in one run manifest. Deslop and technical-writing checks ran before commits.

Independent trail review is pending parent review. The child was explicitly forbidden to start agents. All work ran in-thread on the requested Codex model.
