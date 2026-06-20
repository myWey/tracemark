#!/usr/bin/env bash
set -euo pipefail

echo "[TraceMark] Building debug binary via Swift Package Manager..."
swift build

echo "[TraceMark] Debug build complete."
echo "[TraceMark] For a full release .app / .dmg, use: bash scripts/build-app.sh && bash scripts/build-dmg.sh"
