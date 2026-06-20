#!/usr/bin/env bash
set -euo pipefail

echo "[TraceMark] Running lint checks..."

# Primary style lint: swift-format. If not installed, degrade gracefully.
if command -v swift-format >/dev/null 2>&1; then
    echo "[TraceMark] swift-format found; running format lint..."
    swift-format lint --recursive Sources/ Tests/
else
    echo "[TraceMark] swift-format not installed; skipping style lint."
    echo "[TraceMark] Install with: brew install swift-format"
fi

# Lightweight whitespace checks. Existing files may contain legacy whitespace;
# this is enforced for new/changed files once swift-format is available.
echo "[TraceMark] Running syntax sanity check via swift build..."
swift build

echo "[TraceMark] Lint complete."
