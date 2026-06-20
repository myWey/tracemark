#!/usr/bin/env bash
# UserPromptSubmit hook: warn on suspicious prompt patterns.
# Reads HookInput JSON from stdin. Outputs warning to stderr; JSON hint to stdout.
set -euo pipefail

input=$(cat)

extract_prompt() {
  if command -v jq >/dev/null 2>&1; then
    echo "$input" | jq -r '.prompt // .user_prompt // .message // empty'
  elif command -v python3 >/dev/null 2>&1; then
    echo "$input" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for k in ("prompt","user_prompt","message","content"):
    v=d.get(k)
    if v:
        print(v)
        break
'
  fi
}

prompt=$(extract_prompt | tr '[:upper:]' '[:lower:]')
[ -z "$prompt" ] && exit 0

suspicious_patterns=(
  'ignore previous instructions'
  'ignore all prior'
  'you are now .* mode'
  'disregard .* rules'
  'jailbreak'
  'dan mode'
  'do anything now'
  'rm -rf /'
  'format c:'
  'dd if=/dev/zero'
  'del /f /s /q'
  'sudo rm'
)

for pattern in "${suspicious_patterns[@]}"; do
  if echo "$prompt" | grep -qiE "$pattern"; then
    reason="Suspicious prompt pattern detected: '${pattern}'. Verify user intent before acting."
    reason_zh="检测到可疑提示词模式：'${pattern}'。执行前请确认用户真实意图。"

    message="warning: $reason | $reason_zh"
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput': {'permissionDecision': 'allow'}, 'systemMessage': sys.argv[1], 'reason': sys.argv[1]}))" "$message"
    elif command -v jq >/dev/null 2>&1; then
      jq -n --arg msg "$message" '{"hookSpecificOutput": {"permissionDecision": "allow"}, "systemMessage": $msg, "reason": $msg}'
    fi

    echo "warning: $reason" >&2
    echo "warning: $reason_zh" >&2
    exit 0
  fi
done

exit 0
