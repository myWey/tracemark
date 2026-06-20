> Project-level feature lock list. These interfaces, behaviors, and files are considered stable. Modify only through the full spec/plan/review/ship loop.

# Feature Lock: agentOS

本文件记录 agentOS 工作环境中已经验证、不应被临时改动的基础设施约定。它们不是“永远不改”，而是“改之前必须重新走完整闭环”。

## Locked Interfaces / 锁定的接口与协议

| 项目 | 当前约定 | 变更流程 |
|------|----------|----------|
| Hook 输入协议 | stdin JSON，含 `hook_event_name`、`tool_name`、`tool_input` 等 | `/spec` → `/plan` → 修改 hook → `/review` → `/ship` |
| Hook 阻止输出 | exit 2，stdout JSON `{"hookSpecificOutput":{"permissionDecision":"deny"}, "reason":"...", "systemMessage":"..."}` | 同上 |
| Hook 允许/警告输出 | exit 0，stdout JSON `{"hookSpecificOutput":{"permissionDecision":"allow"}, "reason":"...", "systemMessage":"..."}` | 同上 |
| Spec 输出目录 | `.trae/specs/<change-id>/`（spec.md + tasks.md + checklist.md） | 目录结构变更需 ADR |
| Always-on rules | `.trae/rules/00-core-principles.md` + `01-conventions-and-safety.md` + globs 语言规则 | 新增/删除 rule 需 review |
| Build entrypoints | `scripts/*.sh` | 嵌入具体项目后替换，需 review |
| docs/FEATURES.md | auto-updated by /ship, do not manually edit | /spec → /plan → /review → /ship |
| docs/rfc/ | RFC directory, created on-demand by RFC trigger rule | /spec → /plan → /review → /ship |
| spec.md structure | 6 sections (Problem/Solution/Success Criteria/Out of Scope/Implementation Phases/Constraints), do not revert to 10-section PRD format | /spec → /plan → /review → /ship |
| Update mechanism | `.trae/VERSION` + `.trae/MANIFEST` + `scripts/update-agentos.sh` + `<!-- agentOS:project begin/end -->` markers in AGENTS.md | /spec → /plan → /review → /ship |

## Locked Files / 锁定的文件

- `.trae/hooks.json`
- `.trae/hooks/*.sh`
- `.trae/rules/*.md`
- `.trae/mcp.json`（仅当启用 MCP 时；默认禁用，需复制 `mcp.json.template`）
- `AGENTS.md`

## 修改前检查清单

- [ ] 是否已创建 `/spec`？
- [ ] 是否已创建 `/plan` 并明确影响范围？
- [ ] 是否已更新相关 eval/smoke tests？
- [ ] 是否已通过 `/review`？
- [ ] 是否已通过 `/ship`？

## 更新记录

- 2026-06-17: 初始化 feature lock，记录 P0–P2 优化后稳定下来的基础设施。
