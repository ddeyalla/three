#!/usr/bin/env bash
# Screenshot a Three window: scripts/shot.sh <pid> out.png [window-layer, 3 = reflection panel]
set -euo pipefail
ID="$(swift "$(dirname "$0")/shot.swift" "$1" "${3:-0}")"
[ -n "$ID" ] || { echo "no window for pid $1" >&2; exit 1; }
screencapture -x -l "$ID" "$2"
echo "$2"
