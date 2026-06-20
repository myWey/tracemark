#!/usr/bin/env bash
# SessionStart hook: inject project context for cross-session continuity.
# Reads HookInput JSON from stdin, outputs a bilingual summary to stdout.
set -euo pipefail

input=$(cat)

# Extract cwd from HookInput; fall back to git root or pwd.
extract_cwd() {
  if command -v jq >/dev/null 2>&1; then
    echo "$input" | jq -r '.cwd // empty'
  elif command -v python3 >/dev/null 2>&1; then
    echo "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))'
  fi
}

PROJECT_ROOT=$(extract_cwd)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Aggregate health signal
SPECS_DIR="$PROJECT_ROOT/.trae/specs"
uncommitted=$(git -C "$PROJECT_ROOT" status --short 2>/dev/null | wc -l | tr -d ' ' || true)
uncommitted=${uncommitted:-0}

incomplete_specs=0
if [ -d "$SPECS_DIR" ]; then
  for spec_dir in "$SPECS_DIR"/*/; do
    [ -d "$spec_dir" ] || continue
    checklist="$spec_dir/checklist.md"
    [ -f "$checklist" ] || continue
    total=$(grep -c '^\s*-\s*\[' "$checklist" 2>/dev/null || echo "0")
    done=$(grep -c '^\s*-\s*\[x\]' "$checklist" 2>/dev/null || echo "0")
    if [ "$done" -lt "$total" ]; then
      incomplete_specs=$((incomplete_specs + 1))
    fi
  done
fi

if [ "$incomplete_specs" -gt 0 ]; then
  echo "🔴 RED: $incomplete_specs incomplete spec(s), $uncommitted uncommitted files"
elif [ "$uncommitted" -gt 10 ]; then
  echo "🟡 YELLOW: $uncommitted uncommitted files, all specs complete"
elif [ "$uncommitted" -gt 0 ]; then
  echo "🟢 GREEN: $uncommitted uncommitted files, all specs complete"
else
  echo "🟢 GREEN: clean working tree, all specs complete"
fi
echo ""

echo "=== Project Context / 项目上下文 ==="
echo ""

# 1. Git status
echo "## Git Status / Git 状态"
BRANCH=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
STATUS=$(git -C "$PROJECT_ROOT" status --short 2>/dev/null | wc -l | tr -d ' ' || true)
STATUS=${STATUS:-0}
echo "- Branch / 分支: $BRANCH"
echo "- Uncommitted changes / 未提交变更: $STATUS files"
echo ""

# 2. Active specs / plans
echo "## Active Specs / 活跃 Spec"
if [ -d "$SPECS_DIR" ]; then
  for spec_dir in "$SPECS_DIR"/*/; do
    [ -d "$spec_dir" ] || continue
    spec_name=$(basename "$spec_dir")
    checklist="$spec_dir/checklist.md"
    if [ -f "$checklist" ]; then
      total=$(grep -c '^\s*-\s*\[' "$checklist" 2>/dev/null || echo "0")
      done=$(grep -c '^\s*-\s*\[x\]' "$checklist" 2>/dev/null || echo "0")
      echo "- $spec_name: checklist $done/$total completed"
    else
      echo "- $spec_name: no checklist"
    fi
  done
else
  echo "- No active specs / 无活跃 spec"
fi
echo ""

# 3. Project asset index
echo "## Project Assets / 项目资产"
for asset in AGENTS.md docs/PHILOSOPHY.md docs/TERMS.md docs/ARCHITECTURE.md docs/UI-UX-SPEC.md docs/ROADMAP.md; do
  if [ -f "$PROJECT_ROOT/$asset" ]; then
    echo "- $asset: present"
  fi
done
if [ -d "$PROJECT_ROOT/docs/adr" ]; then
  adr_count=$(ls "$PROJECT_ROOT/docs/adr/"*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "- docs/adr/: $adr_count decision records"
fi
echo ""

# 4. Recent memory
echo "## Recent Memory / 最近记忆"
MEMORY_DIR="$PROJECT_ROOT/.trae/memory"
if [ -d "$MEMORY_DIR" ]; then
  # Inject actual memory content (not just timestamp)
  pm="$MEMORY_DIR/project_memory.md"
  if [ -f "$pm" ]; then
    echo "### Conventions / 约定"
    sed -n '/^## .*[Cc]onvention/,/^## /{ /^## .*[Cc]onvention/p; /^## /!p; }' "$pm" 2>/dev/null | head -10
    echo ""
    echo "### Recent Decisions / 近期决策"
    sed -n '/^## .*[Dd]ecision/,/^## /{ /^## .*[Dd]ecision/p; /^## /!p; }' "$pm" 2>/dev/null | head -10
    echo ""
    echo "### Lessons / 教训"
    sed -n '/^## .*[Ll]esson/,/^## /{ /^## .*[Ll]esson/p; /^## /!p; }' "$pm" 2>/dev/null | head -5
  else
    topics=$(find "$MEMORY_DIR" -name "topics.md" -mtime -7 2>/dev/null | head -3)
    if [ -n "$topics" ]; then
      echo "- Memory updated within 7 days / 近 7 天有记忆更新"
    else
      echo "- No recent memory updates / 无近期记忆"
    fi
  fi
else
  echo "- Memory directory not initialized / memory 目录未初始化"
fi
echo ""

# 5. Build/test commands hint from AGENTS.md
echo "## Build Commands / 构建命令"
agents_md="$PROJECT_ROOT/AGENTS.md"
if [ -f "$agents_md" ]; then
  grep -E '^# (install|build|test|lint|typecheck)' "$agents_md" 2>/dev/null | while read -r line; do
    echo "- $line"
  done
fi

echo ""
echo "=== Context injection complete / 上下文注入完成 ==="
