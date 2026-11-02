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

exec swift "$@"
