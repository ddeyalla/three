#!/bin/bash
# Launch only the isolated frozen QA bundle and retain the actual macOS runtime receipt.
set -euo pipefail

MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
if [[ "$MACOS_VERSION" != 26.* ]]; then
    echo "BLOCKED: macOS 26 is required; this host runs $MACOS_VERSION. No QA app was launched." >&2
    exit 78
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 '/absolute/path/Three B396 QA.app'" >&2
    exit 64
fi
APP_PATH="$1"
BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")"
if [[ "$BUNDLE_ID" != com.deyalla.three.b396qa ]]; then
    echo "Refusing to launch a production or unidentified bundle." >&2
    exit 65
fi
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

RUN_PATH="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/three-macos26-XXXXXXXX")"
/bin/mkdir "$RUN_PATH/chrome"
/usr/bin/sw_vers > "$RUN_PATH/runtime.txt"
/usr/bin/shasum -a 256 "$APP_PATH/Contents/MacOS/ThreeB396QA" > "$RUN_PATH/binary-sha256.txt"
export THREE_DB="$RUN_PATH/three.sqlite"
export THREE_CHROME_DATA="$RUN_PATH/chrome"
HELPER_PATH="$APP_PATH/Contents/Helpers/three"
"$HELPER_PATH" add 'Runtime ordinary focus' --block 25 > "$RUN_PATH/seed.log"
"$HELPER_PATH" add 'Runtime strict focus' --block 25 --strict >> "$RUN_PATH/seed.log"
"$HELPER_PATH" today --json > "$RUN_PATH/planner-before-native.json"

RECEIPT_PATH="$RUN_PATH/runtime-receipt.json"
/usr/bin/plutil -create xml1 "$RECEIPT_PATH"
/usr/bin/plutil -insert runtime -string "$MACOS_VERSION" "$RECEIPT_PATH"
/usr/bin/plutil -insert architecture -string "$(/usr/bin/uname -m)" "$RECEIPT_PATH"
/usr/bin/plutil -insert app -string "$APP_PATH" "$RECEIPT_PATH"
/usr/bin/plutil -insert database -string "$THREE_DB" "$RECEIPT_PATH"
/usr/bin/plutil -insert status -string 'native acceptance pending' "$RECEIPT_PATH"
/usr/bin/plutil -convert json "$RECEIPT_PATH"

/usr/bin/open -n --env "THREE_DB=$THREE_DB" --env "THREE_CHROME_DATA=$THREE_CHROME_DATA" "$APP_PATH"
echo "Isolated QA launched on macOS $MACOS_VERSION. Receipt and scratch data: $RUN_PATH"
echo 'This does not mark native acceptance passed. Record the actual status popover, Chrome restart recovery, and hide/return behavior separately.'
