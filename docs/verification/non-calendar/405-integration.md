# BPRO-405 App recovery integration

This unit composes durable recovery with the existing AppModel, reflection panel, timer notification scheduler, day-close flow, and native setup. It does not establish native acceptance.

## Revision and ownership

Initial inspection confirmed the host-prepared worktree `/Users/divyanshudv/.t3/worktrees/adhd/t3-ab5bcdfe`, branch `t3/recovery-review-lifecycle`, HEAD `7e0e382eab1f4f8a3b556f685fb9615f826370a1`, and a clean diff. The common Git directory is `/Users/divyanshudv/Documents/code-deyalla/adhd/.git`. Origin is `https://github.com/ddeyalla/three.git`.

The feature owns AppModel, ThreeApp, RootView, MenuBarView, TimerNotifications, SleepRecoveryController, RecoveryReviewView, new RecoveryIntegrationTests, and this report. Settings required no change. Existing Core, protocol, Stats, History, task cards, shortcut registration, schema, and decision-log work stays with its assigned owner.

The parent owns the `81be12edbc1062cd61ae7d30b47080ef056c56d6` trim identity dependency, imported here as `8a1cc9b81ba138bebe069b301957437ca07b1c26`. It changes `ReflectionPrompt.matches` to compare `recoveryTrimSeconds`, which also protects guarded finish and extend. Its regression tests and report belong to that dependency. That separate import is not feature work. Its decision-log conflict preserves the original rows and appends only the exact upstream identity-fix row. It does not import unrelated intervening context rows. The parent must not import its own dependency twice.

## Runtime contracts

AppModel constructs and starts one SleepRecoveryController immediately after Store opens. Relaunch recovery commits before planning initialization, catch-up close, snapshot reconciliation, notifications, or reflection timeouts. The controller callback invalidates affected pending and delivered session notifications, then reloads. Controller refresh does not call the callback.

The recovery controller owns sleep, wake, lock, unlock, and clock-change observations. AppModel retains the time-zone refresh observer. The existing notch controller still observes wake only to recompute display placement. It does not reconcile timer accounting. No additional timer, scheduler, Store, or window controller is introduced.

Normal reload and timer ticks refresh durable recovery before catch-up, reminders, and automatic reflection behavior. Failed event persistence preserves queued event timestamps and order. It suspends affected focus reconciliation and App catch-up until retry succeeds. The main window and menu controls expose the error and retry. A historical decision error remains visible without suspending an unrelated newer timer.

Recovery invalidates only the affected notification IDs and clears the cached schedule only when that ID is affected. Ordinary reload compares same-session trim changes, so another process can adjust the shared deadline without going through the controller callback. Existing obsolete-request cleanup on launch remains. Schedule completion revision guards reject obsolete asynchronous results. Foreground notification presentation and notification actions reread recovery. An automatically completed due break can still deliver its reminder during a focus-recovery failure. An unresolved action opens the explicit recovery route and does not extend or finish a timer.

ReflectionPresentation is an observable reference owned by AppModel. Recovery changes its prompt in place. The existing panel keeps its hosted view and SwiftUI draft state. The note retained for timeout remains separate from prompt identity. An explicit decision gives the same live draft a fresh 120-second deadline. A rejected stale timeout leaves the draft available for reload and rebinding. Saved presentations refresh adjusted session data without changing saved answers or a newer timer.

Unchanged recovery reads do not publish a replacement observable status. This prevents a one-second recovery refresh from invalidating the main view and its native task menus. The behavioral test observes a real consumer of the recovery collection. This is not proof of native submenu stability.

Main-window, menu-bar, and Go-menu entry points open the existing quiet RecoveryReviewView explicitly. Later and Escape dismiss its presentation only. Keep and Trim have no default keyboard action. Recovery and Day Review share the existing sheet route. Shutdown stops recovery observers, the existing ticker, the database signal observation, and the time-zone observer. Native menu and notch controllers retain their existing lifetime and start guards. Done, History, and Trends retain Command-4, Command-6, and Command-7.

The Model the Domain principle led to an observable per-panel presentation instead of replacing its hosted view. Test Behavior, Not Implementation led to assertions on stored sessions, notification requests, retained notes, and observable invalidation. Sequence Work into Verifiable Units kept the parent-owned transaction guard separate from App composition. Emil guidance led to quiet native buttons, stable focus, explicit choices, and no new authored animation.

## Cold-launch trace

The parent receipt at `cf39f64`, `native-fix-setup-trends-retry.md`, reports a running isolated QA process and a watched database but no accessible window. This worker read that receipt and traced ThreeApp initialization, AppDelegate.prepare, applicationDidFinishLaunching, MenuBarController.start/show, and NotchController.start. The model is retained by the app and delegate. Prepare constructs native controllers once. Did-finish-launching starts them even when no main window appears. Main-window appearance also calls the same idempotent starts. Window and Settings actions use the existing SwiftUI scene closures. Closing the last main window retains the app and menu controls.

No concrete source defect explaining `cgWindowNotFound` or the SystemUIServer timeout was established. No speculative startup patch was made. Actual cold launch, status-item visibility, and main-window reopen remain native checks.

## Executed checks

Raw logs live under `build/verification/non-calendar/` in this worktree. Test commands set disposable `THREE_DB` and `THREE_CHROME_DATA` paths. Recovery fixtures create unique temporary databases and remove them after each test. The headless App initializer disables system observers, window effects, sounds, global shortcut registration, and planning checks while keeping synchronous relaunch recovery and actual Store behavior.

The final Swift check includes the parent-owned trim guard and all eleven App integration tests.

| Result | Command | Evidence |
| --- | --- | --- |
| PASS | `./scripts/swift.sh test --filter 'RecoveryIntegrationTests\|recoveryTrimInvalidatesOldReflectionActions'` | `405-integration-focused-identity-final.log`, ten App integration tests plus the parent guard test with extend, finish, and defer cases |
| PASS | `./scripts/swift.sh test` | `405-integration-full-final.log`, 213 Core and 72 App tests, including eleven recovery integration tests |
| PASS | `./scripts/lint-design.sh` | `405-integration-lint-final.log` |
| PASS | `CONFIG=release ./scripts/bundle.sh` | `405-integration-release-final.log`, app and packaged helper built and signed locally |
| PASS | `codesign --verify --deep --strict build/Three.app` and `plutil -lint build/Three.app/Contents/Info.plist` | `405-integration-signature.log`, exit 0 and plist OK |
| PASS | `git diff --check` | Exit 0 |

The signed app executable SHA-256 is `cab257e33ce6f354ebbfa18990beee86b985b041641f6e2c0ee7ce0c88747df9`. The packaged helper SHA-256 is `a9e23906e85f9fd0b6e406d7f8d0987bab6d40fc4e2f32acad92ea8d77ac607a`. The receipt is `405-integration-binary-sha256.txt`.

These commands use `THREE_DB="$PWD/build/verification/non-calendar/405-integration-tests.sqlite"` and `THREE_CHROME_DATA="$PWD/build/verification/non-calendar/405-integration-chrome"`. The complete Swift run includes all App suites. It does not include extension tests or the coordinator's packaged protocol checks.

The first build failed with `No space left on device`. A second attempt failed while linking a package manifest for the same reason. Local SDK module files were cloned from the repository build cache into this worktree without modifying the source cache. Free space later increased and compilation proceeded. Initial test compilation also exposed optional DayKey and nested macro mistakes, then a missed enum-pattern conversion during presentation refactoring. Those errors were corrected before behavioral checks passed.

An intermediate full App run passed 69 tests. The next run passed all nine recovery cases but failed `ScheduledPlanningAppTests.shutdownCancelsAnAlreadyRunningOwnedProcessGroup` at its existing `ready` assertion. The exact test passed in isolation afterward. Its aggregate failure remains in `405-integration-app-final.log`; the isolated pass is `405-integration-scheduled-isolated.log`. No existing test, readiness bound, skip, or assertion was changed.

## Remaining acceptance

Physical sleep and lock, real notification delivery and removal, keyboard draft state, quiet recovery presentation, Later and Escape, main-window reopen, status-item and shortcut behavior, native menu stability, supported notch hardware, and macOS 26 remain COULD NOT RUN under this worker's headless-only scope. Deterministic clocks, Store writes, and notification delivery closures do not prove those cases.

The parent coordinates fresh independent review, packaged protocol verification, and the final Terra recovery pass. Native fixtures must use a uniquely identified app and disposable data. Recovery must be checked with a running session, a retained live reflection draft, a historical saved reflection plus a newer timer, an untrusted clock, an event write failure and retry, an external keep or trim, and relaunch after a durable begin. Installed Three and Three Manual Test must remain untouched. No desktop, browser, app launch, physical sleep or lock, production-data mutation, real sync, calendar action, release metadata change, paid provider call, or Linear write ran here.

Implementation, testing, source tracing, and cleanup ran in-thread on Codex gpt-6.1-sol High. The user prohibited nested delegates. The parent owns independent review and the playbook.
