# BPRO-398 native draft review

Three must let an agent propose a draft that a person can review and commit without replacing accepted work. The native draft path passed at integrated `d183692f83b9ebd2aa0ce4cd047fa52113923a87`. Connect's copied Codex TOML failed. The small fix in `772fddc2e56ae77402baaa536b10606fe73f4777` passed a rebuilt native Copy and standard TOML parser check.

**BPRO-397 verdict is PASS for this assigned verification scope. BPRO-398 verdict is PASS for the tested native path after the fix.** Neither verdict authorizes release or asserts a full accessibility audit. BPRO-396 remains blocked and has a separate follow-up report.

## Executed inputs

| Input | Value |
| --- | --- |
| Prepared worktree | `/Users/divyanshudv/.t3/worktrees/adhd/t3-25eb1c32` |
| Branch | `t3/bpro-native-qa` |
| Initial integrated source | `d183692f83b9ebd2aa0ce4cd047fa52113923a87` |
| Adversarial review scope | `9c0da8f..e69612e`, exercised on the integrated executable |
| Initial bundle | Read-only copy of `/Users/divyanshudv/Documents/code-deyalla/adhd/build/Three.app` |
| Native process | `Three B398 QA.app`, `com.deyalla.three.b398qa`, PID 35808 |
| Fixed native process | `Three B398 Fix QA.app`, `com.deyalla.three.b398fixqa` |
| Runtime | macOS 27.0.1, arm64 |
| Agent | In-thread `codex/gpt-6.1-sol`, High. No child agents. |

All artifacts below use this absolute base directory.

`/Users/divyanshudv/.t3/worktrees/adhd/t3-25eb1c32/build/verification/bpro-398/`

The original database is `native/three.sqlite`. The fixed QA app deliberately reopened that same scratch database. `native-fixed/run.json` records the runtime override separately from its unused preparation database. Production Three was already running and was never launched, installed, restarted, or operated.

The prepared copies of `scripts/verification/bpro-396-qa.py` relabel and sign each QA bundle. Preparation compares every `__TEXT,__text` instruction line with its input bundle. The initial instruction hash is `08804ce8df4307476c887290a1cf35763b05c16088a563d225452d950c8c8d90`. The fixed instruction hash is `160e44d582f61502d94660b4c0ea4a7cfec4acdcb46f9a6ed18e2019cdc1053c`. See `prepare.log`, `prepare-fixed.log`, both `run.json` files, and `binary-sha256.json`. The fixed build preceded its commit but contains exactly the SettingsView change committed as `772fddc`.

`qa-open-files.txt` proves PID 35808 opened the scratch database and did not open the production database. A first detached launch ended before observation and was not counted. The persistent process launched through the execution session is the process used for acceptance.

## Native draft and explicit commitment

The test client used the actual packaged helper over MCP stdio. It submitted three Coding tasks with 30-minute blocks, `commit=false`, tags, notes, a verified-shape HTTPS Linear reference, and one deliberately unsupported reference. The stated availability was 120 minutes, with 90 minutes proposed and 30 minutes left as buffer. No model or paid provider ran.

| Native action | Observed behavior | Evidence relative to the artifact base |
| --- | --- | --- |
| Observe empty app, then create through external MCP | The already-open native process refreshed without a relaunch. It displayed `Draft from MCP · 3 tasks · 1h 30m`. | `empty.png`, `draft-from-mcp.png`, matching `.ax.txt` files, `mcp-proposal.json` |
| Open the first pencil editor | Changed `QA Review migration` to `QA Reviewed migration` and changed 30 minutes to 45 with the native stepper. Return saved and closed the editor. | `reviewed-before-commit.png`, matching AX, `mcp-reviewed-before-commit.json` |
| Use the second task's native menu | Move Up placed `QA Trace guard` first. | `reviewed-before-commit.png`, `mcp-reviewed-before-commit.json` |
| Drop the third task through its native menu | It disappeared from the proposed commitment. The summary became two tasks and 1h 15m. Its stored row became dropped. | Same reviewed artifacts |
| Click the native Commit button | The draft line and Commit button disappeared. MCP returned committed status with source `mcp`. | `mcp-committed-and-rejected.json`, `draft-assertions.txt` |
| Propose another draft over the committed day | MCP returned `invalid_input` and `A draft cannot replace a committed plan. Replan explicitly with commit=true.` Every task row remained identical. | `mcp-committed-and-rejected.json` |

The committed rows exactly match the reviewed rows, including IDs and order.

| Position | Task ID | Reviewed result |
| --- | --- | --- |
| 0 | `D175C036-99EF-4FC1-AE46-1467B94A4208` | QA Trace guard, 30 minutes, todo |
| 1 | `A4B1564E-C116-481D-BE86-A6CDB626757C` | QA Reviewed migration, 45 minutes, todo |
| 2 | `18956CE0-3F84-45D8-9C91-9E85965F2EE0` | QA Omit from commitment, 30 minutes, dropped |

No timer ran during draft review or Commit. Commit changed plan commitment metadata and retained the task rows. The comparison initially expected the wrong status spelling, `planned`. The actual domain value is `todo`. The corrected comparison passed without changing the app or its assertions about row identity and content.

## Carry-over and failure behavior

Four older tasks were added through MCP on yesterday's date. The packaged CLI added one checked and one unchecked step to each. Two short real scratch focus sessions supplied 17.961 and 20.733 seconds of history. No session time was fabricated.

| Check | Native result and stored result | Evidence |
| --- | --- | --- |
| Offer without acceptance | Earlier tasks remained on their original day. The running task's Accept today button was disabled. | `carry-running-disabled.png`, matching AX, `carry-focus-start.json`, `carry-before-choice.json` |
| Accept today | Added one distinct copy. Original became carried. Copy retained `createdBy=mcp`, strictness, issue URL, notes, tags, and checked step states. Task and step IDs were new. Original history stayed attached to the original. Copy had zero focus time and no scheduled start. Today's existing committed plan and MCP source stayed intact. | `carry-before-choice.json`, `carry-after-choice.json`, `carry-assertions.txt` |
| Dismiss | Original became dropped without adding a task today. Its steps, tags, notes, and focus history remained. | Same carry comparison artifacts |
| Five-task ceiling | The native view displayed `Five is the limit. Move one to the inbox to add another.` Both remaining Accept buttons were disabled. MCP carry returned `too_many_tasks` and left all destination rows unchanged. | `cap-full-native.png`, matching AX, `cap-full.json`, `cap-rejected.json` |
| Closed source | Selecting Accept today displayed `A closed day cannot be changed.` Both days' saved contents remained identical. | `closed-source-error.png`, matching AX, `closed-source-fixture-before.json`, `closed-source-after.json` |
| Blank title | Whitespace disabled the native editor's Save button. | Native CUA observation in this run |
| Day closes while editor is open | Return attempted Save, showed the closed-day error, and kept the edited text and editor open. Escape cancelled. The day stayed closed and every stored row remained unchanged. MCP Commit and a new proposal also returned `invalid_input`. | `stale-editor-error.png`, matching AX, `closed-destination-before.json`, `closed-destination-after.json` |

There is no close-day tool. The two closed-day fixtures changed only the scratch `dayPlan.status` through SQL. The destination fixture changed while the native editor remained open. Its status was restored only in scratch for the remaining UI checks. Comparisons omit only the MCP response's changing `takenAt` timestamp. They retain plan, task, session, step, and tag content.

## Native controls, links, and Connect

The Tasks pane was set to its 328-point minimum split thickness through CUA's native accessibility value. `narrow-pane.png` shows title truncation with pencil, duration, menu, issue link, and carry-over controls still available. Return saved a valid editor. Escape cancelled a failed editor. This is bounded keyboard proof, not VoiceOver acceptance. Several coordinate divider drags were inconclusive and were not counted. Reordering was proven through the menu. Drag ordering was not separately accepted.

The valid Linear reference appeared as native link `BPRO-398` with the exact HTTPS destination. `javascript:alert(1)` appeared as selectable text, with no link action. The native tree is in `draft-from-mcp.ax.txt`, and the focused link-validation test passed. The link was not dispatched to the real default browser, which would operate the user's profile. No product Linear API request ran. Tracker comments used the authorized Linear connector separately.

Native Connect exposed both connection formats and all three bundled guidance documents. Native Copy output for Claude JSON parsed and matched the QA app's helper and `mcp` argument. Native copies of the guide, Codex prompt, and Claude skill matched their source files byte for byte. Evidence is `copied-claude.json`, `copied-guide.md`, `copied-codex-prompt.md`, `copied-claude-skill.md`, and `connect-guidance-copy.png` with AX. Calendar displayed v0.5. No configuration file, CLI symlink, skill, or calendar connection was installed.

### Reproduced and fixed Codex configuration defect

The native Copy action at `d183692` produced `command = "\/Users\/..."`. Python `tomllib` rejected it with `Unescaped '\\' in a string (at line 2, column 14)`. The app used a default JSONEncoder for a TOML string, and its optional slash escaping is invalid TOML. This is the only confirmed product finding from the fresh behavioral review.

`772fddc` sets `.withoutEscapingSlashes` on that existing encoder. It introduces no new state or API. The rebuilt and re-signed native app's Copy action then produced TOML that `tomllib` parsed successfully. Its decoded command exactly matched the packaged helper path, including spaces, and its arguments were exactly `["mcp"]`.

Regression artifacts are `copied-codex-before.toml`, `codex-toml-failure.txt`, `copied-codex-fixed.toml`, `codex-toml-fixed-result.txt`, and `codex-config-fixed.png` with AX. This is native before-and-after proof with a standard parser. It is not a claim that a real Codex client was configured or invoked.

## Fresh automated checks

| Command | Result | Log |
| --- | --- | --- |
| `./scripts/bundle.sh` after the fix | Passed. Debug bundle 0.2.4 build 74. | `fix-bundle-build.log` |
| `./scripts/swift.sh test --filter 'DraftReviewTests\|Carry\|carry\|pushToTomorrow\|TodayOrderTests'` | Nine Core tests and seven App tests passed. | `focused-tests.log` |
| `python3 scripts/test-mcp.py --binary build/Three.app/Contents/Helpers/three` | Passed real initialization, 26 tools, two resources, invalid requests, persistence, cap and timer races, and shared CLI writes. | `mcp-suite.log` |
| `python3 scripts/test-draft-review.py --app build/Three.app` | Passed relocated helper and shared Store review. Headless only. | `headless-draft-review.log` |
| `make test` after the fix | Design lint, 115 Core tests, 22 App tests, and 22 extension tests passed. No extension skips. | `final-make-test.log` |
| `codesign --verify --deep --strict --verbose=2 build/Three.app` | Passed. | `fixed-signature.log` |

## Preservation and handback

`cleanup-and-preservation.json` records zero remaining owned QA, fixture, browser, or native-host processes. All native apps were serialized and stopped before handback. Clipboard contents were restored after Copy checks, and the private temporary clipboard backup was removed. The reports and ignored evidence files are the only remaining task artifacts.

Every production database table fingerprint, the installed executable hash, the protected native-messaging manifest state, production PID 92331, and its original local start time `2026-11-03 06:22:12` matched the baseline. The real Chrome app and its profiles were never operated. No broad process kill, live provider, release build promotion, install, push, tag, or production restart occurred.

The test agent performed its own fresh behavioral review because the task forbids children. This is not a separate independent review verdict. The parent retains any independent review and final ticket acceptance gates. BPRO-399 was not implemented or tested by this QA run.
