# agentOS Smoke Eval

## E1: Hook 保护受保护文件

**场景**：agent 收到修改 `.env` 的指令。

**预期**：`protect-files.sh` 输出 `permissionDecision: deny` 并退出码 2。

**验证命令**：
```bash
echo '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":".env"}}' | bash .trae/hooks/protect-files.sh
echo $?
```

**通过标准**：stdout 包含 `"permissionDecision":"deny"`，退出码为 2。

---

## E2: 骨架构建入口可执行

**场景**：无具体项目嵌入时运行构建脚本。

**预期**：脚本退出 0 并打印骨架提示。

**验证命令**：
```bash
bash scripts/build.sh && bash scripts/test.sh && bash scripts/lint.sh && bash scripts/typecheck.sh
```

**通过标准**：所有命令 exit 0，输出包含 "[agentOS]" 或 "Skeleton" 提示。

---

## E3: Spec 路径统一

**场景**：检查 spec 输出目录是否符合单一事实来源。

**预期**：`.trae/specs/README.md` 存在，根目录无 `specs/` 或 `plans/` 目录。

**验证命令**：
```bash
test -f .trae/specs/README.md && test ! -d specs && test ! -d plans && echo PASS || echo FAIL
```

**通过标准**：输出 `PASS`。

---

## E4: MCP 配置有效

**场景**：`.trae/mcp.json` 已配置。

**预期**：文件为有效 JSON，包含至少一个 MCP server。

**验证命令**：
```bash
python3 -m json.tool .trae/mcp.json >/dev/null && jq '.mcpServers | length > 0' .trae/mcp.json
```

**通过标准**：`python3 -m json.tool` 无错误，`jq` 输出 `true`。

---

## E5: Rules 瘦身生效

**场景**：检查 always-on rules 是否保持精简。

**预期**：`.trae/rules/*.md` 总行数在 120-140 行范围内，且所有文件都有 frontmatter。

**验证命令**：
```bash
total=$(cat .trae/rules/*.md | wc -l | tr -d ' ')
echo "Total rule lines: $total"
test "$total" -ge 120 && test "$total" -le 140 && grep -q '^---' .trae/rules/*.md && echo PASS || echo FAIL
```

**通过标准**：总行数在 120-140 范围内，每个规则文件包含 frontmatter 分隔线 `---`。

---

## E6: stop-check hook 在非 git 目录下不崩溃

**场景**：agent 在 `/tmp` 等非 git 目录下结束会话。

**预期**：`stop-check.sh` 正常退出，不因为 `git status` 失败而崩溃。

**验证命令**：
```bash
echo '{"cwd":"/tmp"}' | bash .trae/hooks/stop-check.sh >/dev/null 2>&1 && echo PASS || echo FAIL
```

**通过标准**：输出 `PASS`。

---

## E7: orchestrator 包含 negative/forbidden 任务指引

**场景**：autopilot / orchestrator 自动分派任务。

**预期**：orchestrator 明确列出禁止自动处理的任务类型（negative/forbidden/must not/do not）。

**验证命令**：
```bash
grep -qi "negative\|forbidden\|must not\|do not" .trae/agents/orchestrator.md && echo PASS || echo FAIL
```

**通过标准**：输出 `PASS`。

---

## E8: memory-management skill 包含 maturation/checkpoint

**场景**：完成一个 spec 周期后，agent 应回顾并更新 memory。

**预期**：memory-management skill 定义了 maturation 或 checkpoint 机制。

**验证命令**：
```bash
grep -qi "maturation\|checkpoint" .trae/skills/memory-management/SKILL.md && echo PASS || echo FAIL
```

**通过标准**：输出 `PASS`。

---

## E9: 文档模板含 Status: Template 标识

**场景**：检查战略层文档模板是否带有 Template 状态标识。

**预期**：docs/PHILOSOPHY.md、docs/TERMS.md、docs/ARCHITECTURE.md、docs/ROADMAP.md 均包含 `Status: Template` 标识。

**验证命令**：
```bash
grep -rl "Status: Template" docs/PHILOSOPHY.md docs/TERMS.md docs/ARCHITECTURE.md docs/ROADMAP.md | wc -l | tr -d ' ' | grep -q '^4$' && echo PASS || echo FAIL
```

**通过标准**：输出 `PASS`（4 个文件均含标识）。
