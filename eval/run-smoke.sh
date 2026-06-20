#!/usr/bin/env bash
# agentOS Smoke Test Runner
# Automated verification based on eval/agentOS-smoke-eval.md
set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ✅ PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ❌ FAIL: $1"
}

# ── S1: Rules 文件存在且有 frontmatter ──
echo ""
echo "=== S1: Rules files exist with frontmatter ==="
all_have_frontmatter=true
for f in .trae/rules/*.md; do
  if [ ! -f "$f" ]; then
    all_have_frontmatter=false
    echo "  Missing: $f"
  elif ! head -1 "$f" | grep -q '^---'; then
    all_have_frontmatter=false
    echo "  No frontmatter: $f"
  fi
done
if $all_have_frontmatter; then
  pass "All rule files have frontmatter"
else
  fail "Some rule files missing or lack frontmatter"
fi

# ── S2: Rules 总行数在合理范围 ──
echo ""
echo "=== S2: Rules total line count ≤ 150 ==="
total_lines=$(cat .trae/rules/*.md | wc -l | tr -d ' ')
echo "  Total rule lines: $total_lines"
if [ "$total_lines" -le 150 ]; then
  pass "Rules line count ($total_lines) ≤ 150"
else
  fail "Rules line count ($total_lines) > 150"
fi

# ── S3: AGENTS.md 存在且行数 ≤ 150 ──
echo ""
echo "=== S3: AGENTS.md exists and ≤ 150 lines ==="
if [ -f AGENTS.md ]; then
  agents_lines=$(wc -l < AGENTS.md | tr -d ' ')
  echo "  AGENTS.md lines: $agents_lines"
  if [ "$agents_lines" -le 150 ]; then
    pass "AGENTS.md exists ($agents_lines lines ≤ 150)"
  else
    fail "AGENTS.md too long ($agents_lines lines > 150)"
  fi
else
  fail "AGENTS.md not found"
fi

# ── S4: Hook 脚本 bash 语法检查通过 ──
echo ""
echo "=== S4: Hook scripts pass bash syntax check ==="
hooks_ok=true
for f in .trae/hooks/*.sh; do
  if [ ! -f "$f" ]; then
    hooks_ok=false
    echo "  Missing: $f"
  elif ! bash -n "$f" 2>/dev/null; then
    hooks_ok=false
    echo "  Syntax error: $f"
  fi
done
if $hooks_ok; then
  pass "All hook scripts pass bash -n syntax check"
else
  fail "Some hook scripts have syntax errors"
fi

# ── S5: Hook JSON 输出格式统一（含 hookSpecificOutput）──
echo ""
echo "=== S5: Hook JSON output contains hookSpecificOutput ==="
# Capture stdout before grep to avoid pipefail from the hook's exit 2.
hook_output=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":".env"}}' \
  | bash .trae/hooks/protect-files.sh 2>/dev/null || true)
if echo "$hook_output" | grep -q '"hookSpecificOutput"'; then
  pass "protect-files.sh outputs hookSpecificOutput"
else
  fail "protect-files.sh missing hookSpecificOutput in output"
fi

# ── S6: reviewer.md 不含完整 checklist（无 - [ ] 条目）──
echo ""
echo "=== S6: reviewer.md has no - [ ] checklist items ==="
if [ -f .trae/agents/reviewer.md ]; then
  if grep -q '^\s*- \[ \]' .trae/agents/reviewer.md 2>/dev/null; then
    fail "reviewer.md contains - [ ] checklist items"
  else
    pass "reviewer.md has no - [ ] checklist items"
  fi
else
  fail "reviewer.md not found"
fi

# ── S7: Verdict 命名统一（无 "NEEDS CHANGES" 空格版）──
echo ""
echo "=== S7: Verdict naming consistent (NEEDS_CHANGES, not NEEDS CHANGES) ==="
# Only check runtime docs (rules/skills/commands/agents), not conversation archives.
found=false
for dir in .trae/rules .trae/skills .trae/commands .trae/agents; do
  if [ -d "$dir" ] && grep -rq 'NEEDS CHANGES' "$dir" --include='*.md' 2>/dev/null; then
    found=true
    echo "  Found in $dir"
  fi
done
if $found; then
  fail "Found 'NEEDS CHANGES' (with space) in runtime .trae/ markdown files"
else
  pass "No 'NEEDS CHANGES' (with space) found in runtime docs; verdicts use NEEDS_CHANGES"
fi

# ── S8: Project Asset Check 路径正确 ──
echo ""
echo "=== S8: Project assets use docs/PHILOSOPHY.md (not root) ==="
if grep -q 'docs/PHILOSOPHY\.md' .trae/hooks/session-start.sh 2>/dev/null; then
  pass "session-start.sh references docs/PHILOSOPHY.md"
else
  fail "session-start.sh does not reference docs/PHILOSOPHY.md"
fi
if grep -q 'docs/PHILOSOPHY\.md' .trae/rules/01-conventions-and-safety.md 2>/dev/null && grep -q 'Subagent Project Asset Check' .trae/rules/01-conventions-and-safety.md 2>/dev/null; then
  pass "rules/01 contains Subagent Project Asset Check with docs/PHILOSOPHY.md"
else
  fail "rules/01 missing Subagent Project Asset Check or docs/PHILOSOPHY.md reference"
fi

# ── S9: mcp.json 是有效 JSON ──
echo ""
echo "=== S9: mcp.json is valid JSON ==="
if python3 -m json.tool .trae/mcp.json >/dev/null 2>&1; then
  pass "mcp.json is valid JSON"
else
  fail "mcp.json is not valid JSON"
fi

# ── S10: 骨架 scripts/ 可执行 ──
echo ""
echo "=== S10: Skeleton scripts are executable and exit 0 ==="
scripts_ok=true
for s in scripts/build.sh scripts/test.sh scripts/lint.sh scripts/typecheck.sh; do
  if ! bash "$s" >/dev/null 2>&1; then
    scripts_ok=false
    echo "  Failed: $s"
  fi
done
if $scripts_ok; then
  pass "All skeleton scripts exit 0"
else
  fail "Some skeleton scripts failed"
fi

# ── S11: 非 git 目录下 hook 不崩溃 ──
echo ""
echo "=== S11: Hook does not crash outside git directory ==="
if echo '{"cwd":"/tmp"}' | bash .trae/hooks/session-start.sh >/dev/null 2>&1; then
  pass "session-start.sh exits 0 with /tmp cwd"
else
  exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass "session-start.sh exits 0 with /tmp cwd"
  else
    fail "session-start.sh crashed (exit $exit_code) with /tmp cwd"
  fi
fi

# ── S12: stop-check.sh 在非 git 目录下不崩溃 ──
echo ""
echo "=== S12: stop-check.sh exits 0 outside git directory ==="
if echo '{"cwd":"/tmp"}' | bash .trae/hooks/stop-check.sh >/dev/null 2>&1; then
  pass "stop-check.sh exits 0 with /tmp cwd"
else
  fail "stop-check.sh crashed with /tmp cwd"
fi

# ── S13: orchestrator 包含 negative/forbidden 任务指引 ──
echo ""
echo "=== S13: orchestrator.md contains negative/forbidden task guidance ==="
if grep -qi "negative\|forbidden\|must not\|do not" .trae/agents/orchestrator.md 2>/dev/null; then
  pass "orchestrator.md contains negative/forbidden task guidance"
else
  fail "orchestrator.md missing negative/forbidden task guidance"
fi

# ── S14: memory-management skill 包含 maturation/checkpoint ──
echo ""
echo "=== S14: memory-management skill contains maturation/checkpoint ==="
if grep -qi "maturation\|checkpoint" .trae/skills/memory-management/SKILL.md 2>/dev/null; then
  pass "memory-management skill contains maturation/checkpoint"
else
  fail "memory-management skill missing maturation/checkpoint"
fi

# ── S15: 文档模板含 Status: Template 标识 ──
echo ""
echo "=== S15: Doc templates contain Status: Template banner ==="
if grep -rl "Status: Template" docs/PHILOSOPHY.md docs/TERMS.md docs/ARCHITECTURE.md docs/ROADMAP.md 2>/dev/null | wc -l | tr -d ' ' | grep -q '^4$'; then
  pass "All 4 doc templates have Status: Template banner"
else
  fail "Doc templates missing Status: Template banner"
fi

# ── 汇总 ──
echo ""
echo "=============================="
echo "  Smoke Test Summary"
echo "  $PASSED/$TOTAL passed"
echo "=============================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
