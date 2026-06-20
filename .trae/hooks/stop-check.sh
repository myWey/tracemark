#!/usr/bin/env bash
# Stop hook: verify checklist completion before agent stops.
# Reads HookInput JSON from stdin. Outputs structured decision on block.
set -euo pipefail

input=$(cat)

extract_cwd() {
  if command -v jq >/dev/null 2>&1; then
    echo "$input" | jq -r '.cwd // empty'
  elif command -v python3 >/dev/null 2>&1; then
    echo "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))'
  fi
}

PROJECT_ROOT=$(extract_cwd)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SPECS_DIR="$PROJECT_ROOT/.trae/specs"

[ ! -d "$SPECS_DIR" ] && exit 0

incomplete_specs=()

for spec_dir in "$SPECS_DIR"/*/; do
  [ -d "$spec_dir" ] || continue
  checklist="$spec_dir/checklist.md"
  [ -f "$checklist" ] || continue

  total=$(grep -c '^\s*-\s*\[' "$checklist" 2>/dev/null || echo "0")
  done=$(grep -c '^\s*-\s*\[x\]' "$checklist" 2>/dev/null || echo "0")

  if [ "$done" -lt "$total" ]; then
    spec_name=$(basename "$spec_dir")
    incomplete_specs+=("$spec_name ($done/$total)")
  fi
done

if [ ${#incomplete_specs[@]} -gt 0 ]; then
  reason="Incomplete checklist items detected: ${incomplete_specs[*]}. Please finish or explicitly confirm stopping."
  reason_zh="检测到未完成的 checklist：${incomplete_specs[*]}。请完成或向用户确认是否可以结束。"

  message="$reason | $reason_zh"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput': {'permissionDecision': 'deny'}, 'systemMessage': sys.argv[1], 'reason': sys.argv[1]}))" "$message"
  elif command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "$message" '{"hookSpecificOutput": {"permissionDecision": "deny"}, "systemMessage": $msg, "reason": $msg}'
  fi

  echo "$reason" >&2
  echo "$reason_zh" >&2
  exit 2
fi

# Warning checks (non-blocking)
warnings=()

# 1. Uncommitted changes check
uncommitted=$(git -C "$PROJECT_ROOT" status --short 2>/dev/null | wc -l | tr -d ' ' || true)
uncommitted=${uncommitted:-0}
if [ "$uncommitted" -gt 5 ]; then
  warnings+=("uncommitted files: $uncommitted (consider committing)")
fi

# 2. Spec without tasks.md check
for spec_dir in "$SPECS_DIR"/*/; do
  [ -d "$spec_dir" ] || continue
  spec_name=$(basename "$spec_dir")
  if ! find "$spec_dir" -maxdepth 1 -iname 'tasks.md' -type f 2>/dev/null | grep -q .; then
    warnings+=("spec '$spec_name' has no tasks.md")
  fi
done

if [ ${#warnings[@]} -gt 0 ]; then
  warning_msg=""
  for w in "${warnings[@]}"; do
    if [ -z "$warning_msg" ]; then
      warning_msg="$w"
    else
      warning_msg="$warning_msg; $w"
    fi
  done
  warn_msg="warning: $warning_msg"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput': {'permissionDecision': 'allow'}, 'systemMessage': sys.argv[1], 'reason': sys.argv[1]}))" "$warn_msg"
  elif command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "$warn_msg" '{"hookSpecificOutput": {"permissionDecision": "allow"}, "systemMessage": $msg, "reason": $msg}'
  fi
  echo "$warn_msg" >&2
fi

exit 0
