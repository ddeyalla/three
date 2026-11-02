#!/usr/bin/env bash
# Enforces DESIGN.md: text uses a Typo role, so sizes and weights live only in Theme.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
hits=$(grep -rn -E '\.font\((\.system|\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2))' Sources/ThreeApp \
    --include='*.swift' | grep -v 'Sources/ThreeApp/Theme.swift' || true)
if [ -n "$hits" ]; then
    echo "Use a Typo role instead of a raw font (see DESIGN.md, Typography):" >&2
    echo "$hits" >&2
    exit 1
fi
