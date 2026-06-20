#!/usr/bin/env bash
# PreToolUse hook: block dangerous or sensitive file modifications.
# Reads HookInput JSON from stdin. Outputs structured decision to stdout on block.
set -euo pipefail

input=$(cat)

# Extract tool_name and file_path from HookInput.
extract_field() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$input" | jq -r --arg k "$key" '.[$k] // empty'
  elif command -v python3 >/dev/null 2>&1; then
    echo "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$key',''))"
  fi
}

extract_nested() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$input" | jq -r --arg k "$key" 'getpath($k / ".") // empty'
  elif command -v python3 >/dev/null 2>&1; then
    echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for k in '$key'.split('.'):
    d=d.get(k,{}) if isinstance(d,dict) else {}
print(d if isinstance(d,str) else '')
"
  fi
}

tool_name=$(extract_field "tool_name")
file_path=$(extract_nested "tool_input.file_path")

# No file_path: allow.
[ -z "$file_path" ] && exit 0

# Protected patterns.
protected_patterns=(
  '\.env$'
  '\.env\.'
  'credentials\.json$'
  '\.pem$'
  '\.key$'
  '\.pfx$'
  'id_rsa'
  'id_ed25519'
  'package-lock\.json$'
  'yarn\.lock$'
  'pnpm-lock\.yaml$'
  'Cargo\.lock$'
  'go\.sum$'
  'poetry\.lock$'
  '/\.git/'
  'production\.yml$'
  'production\.yaml$'
  'production\.json$'
  '\.circleci/'
  '\.github/workflows/'
)

for pattern in "${protected_patterns[@]}"; do
  if echo "$file_path" | grep -qE "$pattern"; then
    reason="Blocked ${tool_name} on protected file: ${file_path} (matches ${pattern}). Human approval required."
    reason_zh="阻止 ${tool_name} 操作受保护文件：${file_path}（匹配 ${pattern}）。需要人类明确批准。"

    # Structured decision for harness (safely escape JSON).
    message="$reason | $reason_zh"
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput': {'permissionDecision': 'deny'}, 'systemMessage': sys.argv[1], 'reason': sys.argv[1]}))" "$message"
    elif command -v jq >/dev/null 2>&1; then
      jq -n --arg msg "$message" '{"hookSpecificOutput": {"permissionDecision": "deny"}, "systemMessage": $msg, "reason": $msg}'
    fi

    # Human-readable feedback.
    echo "$reason" >&2
    echo "$reason_zh" >&2
    exit 2
  fi
done

exit 0
