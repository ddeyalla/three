# BPRO-396 and BPRO-399 completion pass

The user requested completion of both tickets on 2026-11-03 while away for a short break. BPRO-399 is Done after parent acceptance at 04:42:44 UTC. BPRO-396 remains blocked on actual native/runtime/release gates. This pass used the prepared worktree, preserved existing independent desktop ownership, and did not substitute implementation status for acceptance.

## Source and ownership

- Worktree is `/Users/divyanshudv/.t3/worktrees/adhd/t3-fe1cb47d` on `t3/scheduled-planning-runner`.
- Pickup HEAD was `b86d1a8f05650d1541e17d63cfd3b9bc9ca6619d`, with a clean worktree.
- Parent corrections `b000a8d`, `01a0f69`, and `5b9cd9a` were reused as `b4e46a2`, `0542d08`, and `2a75118`. The final timestamp correction `5d2cb4a` was subsequently reused as `c8113ed`. Product Sources and Tests match the integration checkout at `08cd936`.
- The existing final reviewer retains exclusive desktop ownership. This worker started no child, operated no desktop concurrently, and changed no production app, data, PID, browser profile, global setting, VERSION, or CHANGELOG.
- `fae663b` adds an explicit frozen-app input and executable hash to the existing QA preparation script. `9855d17` aligns this branch's planning guidance with the already-verified helper architecture.

## Fresh final artifact proof

All artifacts in this section are under `/Users/divyanshudv/.t3/worktrees/adhd/t3-fe1cb47d/build/verification/finish-396-399/`.

| Proof | Result | Artifact |
| --- | --- | --- |
| `make test` | 134 Core, 26 App, and 22 extension tests pass. | `final-make-test.log` |
| `CONFIG=release ./scripts/bundle.sh` | Release build and bundle pass, 0.2.4 build 90. | `final-release-build.log` |
| `codesign --verify --deep --strict build/Three.app` | Pass. | `final-signature.log` |
| Packaged planning supervisor | Real owner death, cancellation, and deadline terminate the owned group and child, and persist terminal results. An expired claim launches no command. | `final-supervisor.log` |
| Relocated scheduled fixture | Restricted MCP creates one routine draft, refuses prohibited mutations and duplicate drafts, and leaves explicit commit to the normal channel. | `final-scheduled.log` |
| Normal MCP regression | 26 schemas, resources, real stdio, malformed requests, concurrency and persistence pass. | `final-mcp.log` |

The epoch-boundary regression passes with the original deadline and assertions. The existing native/correction review passed at `9d31500`, integrated here as `24b11a7`. The narrowly scoped [timestamp follow-up](bpro-399-timestamp-review.md), committed as `5f819f2` and integrated here as `9155906`, also passed with no new verified findings. It reproduced the original failures through extracted original source and passed fifteen current boundary/day cases with real process cleanup.

The helper supervisor now keeps command lifetime bounded across GUI death. Complete-form Save/Test prevents enabling an older saved command. Last-run insertion order survives clock rollback. No authenticated model/provider call ran.

## BPRO-396 remaining acceptance

The original ordinary blocker flow and physical menu-bar proof remain in `bpro-396.md` and `bpro-396-followup.md`. They are inherited evidence, not fresh runs by this worker.

A fresh isolated QA app was prepared with:

```sh
python3 scripts/verification/bpro-396-qa.py prepare --run-name finish-native --source-app /Users/divyanshudv/.t3/worktrees/adhd/t3-59968077/build/Three.app
```

Its source executable hash is `e3ca87a1f2c52373379a60efeea7dd00bf3430658f4e7e7a39f32752ed4fb12d`, and its instruction hash is `fd5b9e659c5873f2fae2bf6e2073b1c9fdeee77560c4e8b32e721ad849cc3845`. Both match the frozen `d993f48` evidence. Preparation compiled the document-free fixtures, created only scratch data, and passed deep strict signing. The prepared apps were not launched by this worker while the reviewer owned the desktop.

The host is macOS 27.0.1. No macOS 26 runtime, CoreSimulator runtime, UTM, VMware Fusion, or Parallels installation is present in the checked standard locations. The connected runtime exposed no environment-links tool. A real macOS 26 machine is still required for the stated runtime gate. The SDK and deployment target do not satisfy it. On 2026-11-03, the user confirmed that no macOS 26 machine is available. This resolves the availability question but does not waive runtime verification or authorize a change to the supported minimum.

The actual status-item popover, automatic Chrome extension/connection recovery through native restart, and physical hide refusal remain separate acceptance gates. The existing final reviewer also made one bounded frozen-binary status-item probe with a real CGEvent at its freshly observed center. No popover appeared. The probe stopped, the QA app quit, and no new product defect was claimed. The committed report is [BPRO-396 final status probe](bpro-396-final-status-probe.md). No arbitrary release tag or release-labelled package is created while these gates remain open.

The frozen `macos26-handoff.zip` packet is under the artifact base above. It contains only the relabelled QA bundle, instructions, and `scripts/verification/bpro-396-runtime.sh`. The copied bundle passes strict deep signing. The launcher uses absolute system utilities, rejects every host outside macOS 26 before any launch or data write, refuses the production bundle identifier, and creates new scratch paths. The actual macOS 27 invocation returned the expected exit 78 and launched nothing. The macOS 26 launch branch remains unexecuted. A runtime receipt remains labelled native acceptance pending until actual UI checks pass.

## Next small task

The recommended small follow-up is an opt-in Launch at login toggle using `SMAppService.mainApp`, with actual enabled, approval-needed, and error states. PRODUCT section 5.6 already requests it. It requires no planner schema, provider, calendar, or timer change. It has not been implemented or enabled in this completion pass.

## Closure

The [BPRO-399 correction review](bpro-399-final-review.md) passed and released desktop ownership with no remaining owned processes. The exact-timestamp follow-up also passed. BPRO-399 has no remaining identified implementation or independent review blocker; parent tracker acceptance completed and Linear was independently read back as Done at `2026-11-03T04:42:44.568Z`. BPRO-396 cannot be truthfully marked Done while its native/runtime/release predicates remain false. Production database table fingerprints, installed binary/manifest hashes, PID and start time match the final baseline comparison in `final-cleanup.txt`. No owned QA app was launched by this worker, and all its fixture/supervisor processes have exited. BPRO-399 is Done; BPRO-396 stays In Progress with its concrete blocker comment and confirmed lack of a macOS 26 machine. No owned process or scheduled future write remains from this pass.

## Parent integration acceptance

Final integration is on `dv/ai-planning-v04` in `/Users/divyanshudv/Documents/code-deyalla/adhd`.
The parent read back Linear after acceptance. BPRO-397, BPRO-398, and BPRO-399 are Done. BPRO-396 remains In Progress with its release blocker recorded.

The final product Sources tree is `259dd94be221ceda95f666f5cf9544d21df1f689`.
The parent suite passed 134 Core, 26 App, and 22 extension tests. Release build and strict signing passed.
Normal MCP, relocated draft review, scheduled MCP, and all four supervisor cases passed against the packaged helper.
These results live in `build/final-planning-tests.log`, `final-planning-mcp.log`, `final-planning-draft.log`, `final-planning-scheduled.log`, and `final-planning-supervisor.log` in the integration checkout.

The source-aligned local release build is `build/Three.app`, version 0.2.4, and is not a published release.
Its app executable SHA-256 is `07313d4ec38b43abb4ee14a5fb28268f864e141e85e355715273a82cda98c39e`.
Its helper SHA-256 is `ff03e34736117aef2d013007e36cdc4040aa82a0e693d9e28b8d7e14341d251c`.
`build/final-artifact-release.log`, `final-artifact-signing.log`, and `final-artifact-sha256.txt` record that artifact.
The runtime launcher was syntax-checked and rejected this macOS 27 host with exit 78 before any QA launch.
The macOS 26 launch branch remains unexecuted.

Independent implementation, adversarial, native, correction, and timestamp reviews used `codex/gpt-6.1-sol` with high reasoning only.
The timestamp review reproduced the original defect and found no new failure in the correction.
The remaining attention item is BPRO-396's actual popover, Chrome restart, macOS 26, and hide-refusal acceptance.
No release tag, publication, push, installation, production restart, or real authenticated model run occurred.
