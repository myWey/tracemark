#!/usr/bin/env bash
# Diagnostic hook: capture the exact JSON Trae sends to hooks.
# Use this to empirically verify field names and nested structures.
# DO NOT leave this enabled in production — it writes raw input to disk.
set -euo pipefail

DEBUG_LOG=".trae/hooks/debug.log"
input=$(cat)

echo "$(date -Iseconds) [${hook_event_name:-unknown}] $input" >> "$DEBUG_LOG"

# Always allow the operation to continue; this is a passive observer.
exit 0
