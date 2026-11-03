# BPRO-405 native setup

The native setup unit adds the global menu-bar shortcut, dismissible setup guide, notification actions, and opt-in launch at login. It also composes the imported BPRO-403 Trends view. Recovery accounting and recovery controller integration belong to the coordinator and recovery owner.

## Revision and ownership

Initial inspection confirmed `/Users/divyanshudv/.t3/worktrees/adhd/t3-ad41897c`, HEAD `3270869ce3165137f228e3a36243450929bfcfd3`, branch `t3/ad41897c`, and a clean diff. The host subsequently named this branch `t3/native-setup-hotkey-onboarding`.

The coordinator requested two dependency imports. `b1d28dc` became local `e469fea`, and `9ed1136` became local `b84f5d5`. They supply Stats and TrendsView. Do not cherry-pick these imports back onto a coordinator that already contains them. This worker did not change Stats or History calculations.

The worker owns AppModel, ThreeApp, SettingsView, MenuBarView, the granted RootView composition, new native setup modules, and their tests. The coordinator pause/resume fix `d4cd2567449c14d591d9c713cf88e7133f9ebf7d` was imported as local `41f4987`. Its decision-log conflict retained both incoming coordinator rows. AppModel and Notch now use its transactional identity API. The coordinator owns later recovery integration. No calendar, CLI/MCP registration, Notch module, task view, package, icon, version, or release change belongs to this unit.

## Runtime contracts

- `AppDelegate.prepare(model:)` retains the existing AppModel and constructs one menu-bar controller and the existing notch controller. `applicationDidFinishLaunching` starts both even when no main window appears. Repeated starts are idempotent. Termination stops the native owners before the existing planning shutdown.
- `MenuBarController` owns one `NSStatusItem` and one transient `NSPopover`. The popover hosts the existing `MenuBarView` with the same AppModel. It has explicit main-window and Settings closures because an AppKit host has no SwiftUI scene actions. No new timer, scheduler, Store, or accounting owner exists.
- Label observation updates only the native button. Timer, paused, break, saved-reflection precedence, blocking precedence, Reduce Motion, and the spoken label follow the previous composition. Opening a popover is limited to an explicit status-item click or shortcut action.
- `GlobalMenuShortcut` defaults to Option-Command-Space. Setup supports Space and physical US letter keys with Command, Option, Control, and Shift modifiers. A shortcut needs Command, Option, or Control. Disabling it persists. A failed registration remains visible in Setup and the menu controls, with an explicit retry.
- `CarbonMenuShortcut` reads enabled macOS symbolic shortcuts before registration and uses `kEventHotKeyExclusive`. It rejects a conflicting symbolic shortcut and reports Carbon registration failures. It never changes System Settings or overrides an existing registration. Carbon registration needs no Accessibility permission. Native app hiding also uses existing public APIs without an Accessibility requirement, so onboarding invents no permission request.
- `NativeSetup` persists only the setup dismissal and shortcut preference. Skip setup leaves all timer controls functional. The main window and menu controls offer the guide. Connect remains the single owner of optional CLI installation and the existing Codex TOML and Claude JSON snippets. No agent configuration is written automatically.
- Notification authorization is requested only by **Allow timer notifications**. Launch reads the authorization state without prompting. Denied, provisional, unsupported, and request-error states remain visible. Permission and scheduling errors are bounded. A successful explicit authorization action retries the existing reminder schedule.
- `LoginItemControl` reads `SMAppService.mainApp.status`. The UI shows enabled, requires approval, not registered, unsupported, and operation errors. Only the explicit toggle calls register or unregister. There is no persisted enabled flag and no second launch agent.
- AppModel retains the existing one-notification reconciliation. Notification categories add **Review block**, **Add 5 minutes**, and **Open Three**. Payloads bind the session ID, kind, planned seconds, and planned end. The reference-date representation preserves the exact date value through property-list serialization. Pausing, resuming, extending, ending, or replacing a session invalidates obsolete timer actions.
- Notification routing reloads Store state. A live review uses the existing reflection panel. A deferred review opens only its saved session. Extension uses the existing transactional `Store.extend(minutes:expectedSession:)` guard. Break and open actions only open Three. A stale or malformed review cannot start or modify a timer. It displays a bounded explanation. Concurrent schedule completions are checked against the current request revision.
- Trends uses a dedicated RootView branch and History's 600-point narrow-window rule. The quiet footer entry and Go → Trends use Command-7. Done remains Command-4 and History remains Command-6.

## Integration hooks

New files are `GlobalMenuShortcut.swift`, `MenuBarController.swift`, `NativeSetup.swift`, `SetupViews.swift`, and `TimerNotifications.swift` under `Sources/ThreeApp`. Tests are `NativeSetupTests.swift` and `TimerNotificationTests.swift` under `Tests/ThreeAppTests`. Modified app files are AppModel, ThreeApp, SettingsView, MenuBarView, and the explicitly granted RootView.

Recovery integration must reuse the AppModel retained by `AppDelegate.prepare(model:)`. The delegate's `startControllers()` and termination method own native controller lifetime. RootView retains the existing day-review sheet. AppModel retains its existing tick, reload, day-close, reflection, and wake hooks. Attach the recovery owner's returned controller and presentation hooks there. No recovery API or sleep accounting is implemented by this unit.

Check pending recovery before dispatching notification actions after integration. Keep or trim can change the session's accounting and notification deadline. Reconcile the existing AppModel schedule and invalidate an obsolete payload rather than dispatching a stale extension. Rerun `TimerNotificationTests` and the full App suite against the v12 accounting candidate. This worker's proof is against the imported pre-v12 Core.

## Executed headless evidence

Evidence logs are under `build/verification/non-calendar/` in this worktree. Tests use temporary Store databases and isolated defaults. Native shortcut, login, and permission operations are injected in the tests. No test registers a real shortcut or login item, changes notification authorization, or launches an app.

The initial real-state notification tests exposed date precision loss in a Unix epoch conversion. The payload now uses Foundation reference-date seconds. Fixtures read persisted sessions before dispatch, as AppModel does. The tests retain exact identity and duration assertions, including a binary property-list round trip.

The following checks ran in this prepared worktree.

| Result | Command | Evidence |
| --- | --- | --- |
| PASS | `./scripts/swift.sh test --filter 'NativeSetupTests\|TimerNotificationTests'` | `405-focused-tests.log`, 11 tests before adding the separate native fixture test |
| PASS | `THREE_DB="$PWD/build/verification/non-calendar/405-final-suite.sqlite" THREE_CHROME_DATA="$PWD/build/verification/non-calendar/405-final-suite-chrome" make test` | `405-make-test.log`, design lint, 191 Core tests, 54 App tests, and 22 extension tests |
| PASS | `./scripts/swift.sh test --filter ThreeAppTests` with the disposable App-suite database and Chrome directory | `405-app-suite.log`, 54 tests, including the setup and notification tests |
| PASS | `./scripts/lint-design.sh` | `405-lint.log`, exit 0 |
| PASS | `CONFIG=release ./scripts/bundle.sh` | `405-release-bundle.log`, complete local bundle |
| PASS | `codesign --verify --deep --strict build/Three.app` and `plutil -lint build/Three.app/Contents/Info.plist` | `405-signing.log`, exit 0 and plist OK |
| PASS | `THREE_SETUP_FIXTURE_DB=<new disposable path> ./scripts/swift.sh test --filter TimerNotificationTests/prepareNativeSetupFixture` | `405-native-fixture.log`, 1 test, fixture generated without launching an app |
| PASS | Packaged helper `status --json` and `today --json` with the generated fixture's `THREE_DB` and `THREE_CHROME_DATA` | `405-packaged-status.json`, `405-packaged-today.json`, and `405-packaged-fixture.json` |
| PASS | `git diff --check` | Exit 0 |

The full suite includes the imported transaction-identity tests. Setup tests use fake registration and OS-operation closures. Notification tests use real Store state for current, paused, resumed, extended, ended, saved, newer-session, and write-time-race cases. Registration-conflict tests include enabled symbolic shortcuts, disabled shortcuts, and different keys or modifiers.

The source trace in `405-owner-trace.txt` records one AppModel timer constructor, one PlanningController initialization, one status-item creation site, and the existing notification scheduling site. The lifecycle guards and injected action tests support idempotent ownership. Actual status-item count and global keyboard delivery remain native acceptance gates.

## Terra native acceptance

These cases remain **COULD NOT RUN** for this worker because desktop use and app launching are excluded. Headless PASS does not prove delivery by macOS, real keyboard focus, login approval, notification permission acceptance, display hardware, or macOS 26 behavior. Only the Terra desktop owner runs the following isolated acceptance procedure.

Create a new QA copy from the final signed bundle. This command refuses to reuse an existing QA directory and does not launch anything.

```sh
python3 - <<'PY'
import json, plistlib, shutil, subprocess, uuid
from pathlib import Path
root = Path.cwd()
token = uuid.uuid4().hex[:10]
base = root / 'build/verification/non-calendar' / ('405-native-' + token)
base.mkdir()
app = base / 'Three 405 QA.app'
shutil.copytree(root / 'build/Three.app', app)
plist = app / 'Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
exe = 'Three405QA' + token
info.update(CFBundleIdentifier='com.deyalla.three.setupqa.' + token,
            CFBundleName='Three 405 QA', CFBundleDisplayName='Three 405 QA',
            CFBundleExecutable=exe)
plist.write_bytes(plistlib.dumps(info))
(app / 'Contents/MacOS/ThreeApp').rename(app / 'Contents/MacOS' / exe)
for target in [app / 'Contents/Helpers/three-native-host', app / 'Contents/Helpers/three', app]:
    subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
manifest = dict(app=str(app), executable=str(app / 'Contents/MacOS' / exe),
                helper=str(app / 'Contents/Helpers/three'), database=str(base / 'three.sqlite'),
                chrome=str(base / 'chrome'), bundle_id=info['CFBundleIdentifier'])
(base / 'chrome').mkdir()
(base / 'run.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(base / 'run.json')
PY
```

Use the printed absolute manifest path for `QA_MANIFEST`. Seed the disposable fixture through the focused real Store test. Then launch only that uniquely named executable. The launch command belongs to Terra and was not run by this worker.

```sh
export QA_MANIFEST=/absolute/path/printed/above/run.json
THREE_SETUP_FIXTURE_DB="$(python3 -c 'import json,os; print(json.load(open(os.environ["QA_MANIFEST"]))["database"])')" \
  ./scripts/swift.sh test --filter TimerNotificationTests/prepareNativeSetupFixture
python3 - <<'PY'
import json, os, subprocess
m = json.load(open(os.environ['QA_MANIFEST']))
env = dict(os.environ, THREE_DB=m['database'], THREE_CHROME_DATA=m['chrome'])
p = subprocess.Popen([m['executable']], env=env)
print('QA PID', p.pid)
PY
```

Terra records the QA identity, exact frozen source, PID, evidence screenshots, and the following cases.

1. First launch shows the short guide and no permission dialog. Skip setup, quit only the QA PID, relaunch it, and confirm the guide stays dismissed. Timer controls still work. Setup can reopen the guide. Connect shows the existing optional CLI installer and copyable Codex configuration. Avoid the installer unless testing its isolated destination is separately authorized.
2. Check the default shortcut result in Setup. If macOS already owns Option-Command-Space, Three must show a conflict and leave the existing shortcut working. Choose an unused combination through Setup. From another app, invoke it and confirm the same menu controls open and accept keyboard input. Click the status item and compare its controls. Escape and outside click dismiss the popover.
3. Close Three's main window while focus runs. Use the shortcut from another app, pause and resume the same session, add five minutes, and compare the QA helper's `status --json` output. Finish opens the existing reflection flow. Main, Settings, Blocking Settings, and Review closed day routes remain functional from the hosted menu.
4. Keep nested task and category menus open across clock ticks. Confirm they remain usable. Saved-reflection and blocking symbols, timer text, paused and break labels, VoiceOver labels, and Reduce Motion remain correct. Confirm no unrelated app loses focus on launch or on a passive refresh.
5. In the uniquely identified QA app, explicitly request notifications. Record allow or deny. Denial must leave timer and reflection actions usable and show the denied state. If isolated authorization is unavailable, leave delivery acceptance **COULD NOT RUN**. Do not change production Three's notification settings.
6. For an authorized QA identity, the fixture reaches expiry about 15 seconds after seeding. Use Review block and Add 5 minutes on separate fixture runs. Confirm one reflection flow and one session extension. Deliver another reminder, pause or extend through the QA CLI, or stop it and start a newer task. An old action must leave the newer timer unchanged. Review a saved reflection without changing a newer timer. Record native payload delivery separately from the passing headless route tests.
7. Read the login state in Setup without toggling it. The headless suite covers enabled, not registered, requires approval, unsupported, and failure states. Actual isolated QA login registration and login-at-session-start need a separately permitted acceptance session. Never register, unregister, or change the user's installed Three app for this check.
8. Go → Trends opens the imported view with Command-7 and returns to Today. Done Command-4 and History Command-6 remain unchanged. Check the footer entry, tag selector, refresh, and History-width window behavior. CLI/MCP statistics remain the coordinator's responsibility.
9. Quit only the recorded QA PID. Confirm its status item disappears and its registered shortcut no longer opens it. Relaunch it and confirm one status item and one working shortcut. Verify production and the existing Three Manual Test app/process/data remain unchanged.

Use the manifest's helper with its disposable environment for comparisons. The following commands do not address production data.

```sh
python3 - <<'PY'
import json, os, subprocess
m = json.load(open(os.environ['QA_MANIFEST']))
env = dict(os.environ, THREE_DB=m['database'], THREE_CHROME_DATA=m['chrome'])
for args in [['status', '--json'], ['today', '--json']]:
    subprocess.run([m['helper'], *args], env=env, check=True)
PY
```

Recovery reconciliation, physical sleep and lock, real login startup, actual notification delivery, macOS 26 acceptance, and independent review remain open until their owners record separate evidence.
