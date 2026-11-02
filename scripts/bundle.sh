#!/usr/bin/env bash
# Builds Three.app from the SwiftPM products. No Xcode needed.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-debug}"
VERSION="$(cat VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
APP="build/Three.app"

./scripts/swift.sh build -c "$CONFIG" --product ThreeApp
./scripts/swift.sh build -c "$CONFIG" --product three
BIN="$(./scripts/swift.sh build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/ThreeApp" "$APP/Contents/MacOS/ThreeApp"
# The CLI lives in Helpers: "three" and "Three" collide on a case-insensitive disk.
cp "$BIN/three" "$APP/Contents/Helpers/three"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.deyalla.three</string>
    <key>CFBundleName</key><string>Three</string>
    <key>CFBundleDisplayName</key><string>Three</string>
    <key>CFBundleExecutable</key><string>ThreeApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>UTExportedTypeDeclarations</key>
    <array><dict>
        <key>UTTypeIdentifier</key><string>com.deyalla.three.workspace-pane</string>
        <key>UTTypeConformsTo</key><array><string>public.data</string></array>
        <key>UTTypeDescription</key><string>Three Workspace Pane</string>
    </dict></array>
</dict>
</plist>
EOF

codesign --force --sign - "$APP/Contents/Helpers/three"
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION build $BUILD)"
