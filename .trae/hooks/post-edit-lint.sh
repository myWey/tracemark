#!/usr/bin/env bash
# PostToolUse hook: run formatter/linter after file edits.
# Reads HookInput JSON from stdin. Failures are reported to stderr and exit 1.
set -euo pipefail

input=$(cat)

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

file_path=$(extract_nested "tool_input.file_path")
[ -z "$file_path" ] && exit 0
[ ! -f "$file_path" ] && exit 0

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
errors=()

run_formatter() {
  local cmd="$1"
  shift
  # Capture output to variable; don't let it pollute stdout
  local output
  output=$("$cmd" "$@" 2>&1) || errors+=("$cmd failed for $file_path: $(echo "$output" | head -3)")
}

case "$file_path" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    if [ -f "$PROJECT_ROOT/node_modules/.bin/prettier" ]; then
      run_formatter "$PROJECT_ROOT/node_modules/.bin/prettier" --write "$file_path"
    elif command -v prettier >/dev/null 2>&1; then
      run_formatter prettier --write "$file_path"
    fi
    if [ -f "$PROJECT_ROOT/node_modules/.bin/eslint" ]; then
      run_formatter "$PROJECT_ROOT/node_modules/.bin/eslint" --fix "$file_path"
    fi
    ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      run_formatter ruff format "$file_path"
      run_formatter ruff check --fix "$file_path"
    elif command -v black >/dev/null 2>&1; then
      run_formatter black "$file_path"
    fi
    ;;
  *.go)
    if command -v gofmt >/dev/null 2>&1; then
      run_formatter gofmt -w "$file_path"
    fi
    ;;
  *.rs)
    if command -v rustfmt >/dev/null 2>&1; then
      run_formatter rustfmt "$file_path"
    fi
    ;;
  *.md)
    # Skip markdown to avoid content corruption.
    ;;
esac

if [ ${#errors[@]} -gt 0 ]; then
  reason="Post-edit lint/format warnings for $file_path"
  reason_zh="文件 $file_path 编辑后 lint/格式化警告"

  message="lint warning: $reason | $reason_zh"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput': {'permissionDecision': 'allow'}, 'systemMessage': sys.argv[1], 'reason': sys.argv[1]}))" "$message"
  elif command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "$message" '{"hookSpecificOutput": {"permissionDecision": "allow"}, "systemMessage": $msg, "reason": $msg}'
  fi

  echo "lint warning: $reason" >&2
  echo "lint warning: $reason_zh" >&2
  for err in "${errors[@]}"; do
    echo "  - $err" >&2
  done
  exit 0
fi

exit 0
