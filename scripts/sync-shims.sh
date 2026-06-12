#!/usr/bin/env bash
# scripts/sync-shims.sh
# 
# 转发调用编译脚本 scripts/sync-shims.py

set -euo pipefail

cd "$(dirname "$0")/.."
python3 scripts/sync-shims.py "$@"
