# Three

A focus app for an ADHD brain: three things today, each in a time box, driven by your AI harness.
The product spec is [PRODUCT.md](PRODUCT.md).

## Build and run

Needs macOS 26+ and the Xcode Command Line Tools. Xcode itself is not required.

```bash
make run       # debug build of build/Three.app, then launch it
make test      # core tests
make install   # release build to ~/Applications/Three.app, CLI linked at ~/.local/bin/three
```

`scripts/bundle.sh` assembles the `.app` from the SwiftPM products and ad-hoc signs it. Always launch through the bundle (`open`), not `swift run`; notifications need a bundle identifier.

`scripts/swift.sh` wraps `swift` for this machine's toolchain:

- The Command Line Tools here carry stale 2024 `*.private.swiftinterface` files that shadow the current `PackageDescription`. The wrapper points SwiftPM at a cleaned copy. To fix it for good: `sudo rm /Library/Developer/CommandLineTools/usr/lib/swift/pm/*/*.swiftmodule/*.private.swiftinterface`
- Without Xcode, it builds against the macOS 26.5 SDK. The 27 SDK's SwiftUI `@State` is a macro whose plugin ships only with Xcode. 26.5 still has Liquid Glass.

### Checking the UI without screen recording

```bash
THREE_DB=$PWD/build/demo.sqlite open -W -n --env THREE_DB=$PWD/build/demo.sqlite --env THREE_SNAPSHOT=$PWD/build/snap build/Three.app
```

This renders `today.png`, `timeline.png`, `reflection.png` and `menubar.png` into `build/snap` and quits. Glass materials don't render offscreen, and text fields show as yellow placeholders.

## CLI

```bash
three today [--date tomorrow] [--json]
three plan "Ship onboarding:Coding:90" "Write PRD:Writing:60" "Inbox:Admin:30m" [--commit]
three add "Fix login bug" --cat Coding --block 45m [--linear ENG-123] [--strict]
three start [task#] [--min 25]
three pause | resume | extend [5] | stop
three done 2 [--note "merged"]
three drop 3 | tomorrow 3
three status [--json]
three categories
```

The CLI and the app share `~/Library/Application Support/Three/three.sqlite` (override with `THREE_DB`). Every write posts a Darwin notification, so the running app updates immediately.

## Versioning

- **Semantic versions, one per milestone.** `VERSION` holds the marketing version (`CFBundleShortVersionString`). The release plan in PRODUCT.md §12 maps milestones to versions: v0.1 core loop, v0.2 blocker, v0.3 AI/MCP, v0.4 calendar, v0.5 record, v1.0 polish. Fixes inside a milestone bump the patch (0.1.1).
- **Build number** is `git rev-list --count HEAD`, stamped by `bundle.sh` (`CFBundleVersion`).
- **Tags** mark releases: `git tag v0.1.0` on the commit that ships it.
- **Changelog** in [CHANGELOG.md](CHANGELOG.md), one section per version, written when the version is tagged.
- **Commits** are small and each one builds and passes `make test`.

To cut a release: update `VERSION` and `CHANGELOG.md`, commit, `git tag vX.Y.Z`, `make install`.
