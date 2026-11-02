#!/usr/bin/env bash
# Runs `swift` with a clean PackageDescription when the Command Line Tools still
# carry stale 2024 *.private.swiftinterface files, which shadow the current API.
# Permanent fix: sudo rm /Library/Developer/CommandLineTools/usr/lib/swift/pm/*/*.swiftmodule/*.private.swiftinterface
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYSTEM_LIBS="$(dirname "$(dirname "$(xcrun -f swift)")")/lib/swift/pm"

if ls "$SYSTEM_LIBS"/*/*.swiftmodule/*.private.swiftinterface >/dev/null 2>&1; then
    CLEAN="$ROOT/build/.pmlibs"
    if [ ! -d "$CLEAN/PluginAPI" ]; then
        rm -rf "$CLEAN" && mkdir -p "$CLEAN"
        cp -R "$SYSTEM_LIBS/ManifestAPI" "$SYSTEM_LIBS/PluginAPI" "$CLEAN/"
        rm -f "$CLEAN"/*/*.swiftmodule/*.private.swiftinterface
    fi
    export SWIFTPM_CUSTOM_LIBS_DIR="$CLEAN"
fi

# The macOS 27 SDK implements SwiftUI's @State as a macro whose plugin ships only with
# Xcode. Without Xcode, build against 26.5, which still has Liquid Glass.
if ! xcode-select -p | grep -q "Xcode"; then
    for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk; do
        if [ -d "$sdk" ]; then export SDKROOT="$sdk"; break; fi
    done
fi

# SwiftBuild doesn't pass the toolchain's Swift Testing macro plugin; add it for tests.
TESTING_PLUGINS="$(dirname "$(dirname "$(xcrun -f swift)")")/lib/swift/host/plugins/testing"
if [ "${1:-}" = "test" ] && [ -d "$TESTING_PLUGINS" ]; then
    exec swift "$@" -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGINS"
fi

exec swift "$@"
