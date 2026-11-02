#!/usr/bin/env bash
# Screenshot the Three main window: scripts/shot.sh out.png
set -euo pipefail
ID="$(swift "$(dirname "$0")/shot.swift")"
[ -n "$ID" ] || { echo "no Three window on screen" >&2; exit 1; }
screencapture -x -o -l "$ID" "${1:-build/shot.png}"
echo "${1:-build/shot.png}"
