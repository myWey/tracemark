#!/usr/bin/env bash
set -euo pipefail

echo "[TraceMark] Type-checking via Swift build (compilation includes type checking)..."
swift build

echo "[TraceMark] Type-check complete."
