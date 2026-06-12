---
description: 
---

# 工作流：patch-check（已 bootstrap 项目的补丁检查清单）

## 目的

模板在持续演进。已经跑过 bootstrap 的项目可能**缺少后来新增的文件或规则**。
本 workflow 是一份"补丁清单"——逐项检查、缺什么补什么。

## 何时跑

- 模板升级后（pull 了新版 AgentOS template）
- 发现 agent 行为不符合预期（可能是缺了某个规则文件）
- 定期（每 epoch 末跟 drift-check 一起）

## 检查清单

逐项检查。缺的标 ❌，有但过时的标 ⚠️，OK 的标 ✅。

### 必须存在的文件（always-on 层）

| 文件　　　　　　　　　　　　　　　　| 检查　　　　　　　　　　　　　　　　　　　　　　　　　　　　| 缺失时动作　　　　　　 |
| -------------------------------------| -------------------------------------------------------------| ------------------------|
| `AGENTS.md`　　　　　　　　　　　　 | 含 sub-agent 触发决策表？含 fix-review-feedback 触发规则？　| 从模板复制 + 项目化　　|
| `.agent/skills/agent-discipline.md` | 含 6.9（workflow adherence）+ 6.10（sub-agent mandatory）？ | 从模板复制　　　　　　 |
| `.agent/core/philosophy.md`　　　　 | 已填实（无 `{...}` 占位）？　　　　　　　　　　　　　　　　 | 跑 bootstrap Stage 2　 |
| `.agent/core/design-system.md`　　　| 已填实？　　　　　　　　　　　　　　　　　　　　　　　　　　| 跑 bootstrap Stage 2.5 |
| `.agent/core/conventions.md`　　　　| 已按栈裁剪（无 `{TBD}`）？　　　　　　　　　　　　　　　　　| 跑 bootstrap Stage 3　 |
| `.agent/core/boundaries.md`　　　　 | 指向真实目录？　　　　　　　　　　　　　　　　　　　　　　　| 跑 bootstrap Stage 4　 |
| `.agent/core/glossary.md`　　　　　 | ≥ 3 个 active 术语？　　　　　　　　　　　　　　　　　　　　| 跑 bootstrap Stage 6　 |
| `.agent/adr/0001-foundation.md`　　 | Decision 段已填实？　　　　　　　　　　　　　　　　　　　　 | 跑 bootstrap Stage 5　 |
| `.agent/flows/_index.md`　　　　　　| 存在？　　　　　　　　　　　　　　　　　　　　　　　　　　　| 从模板复制　　　　　　 |
| `.agent/flows/_template.md`　　　　 | 存在？　　　　　　　　　　　　　　　　　　　　　　　　　　　| 从模板复制　　　　　　 |

### 编译层（⚠️ 最常见的"范式没生效"原因就在这里）

> **第一步永远是跑 `bash scripts/sync-shims.sh --check`**。如果报 DRIFT，
> 说明 `.agent/` 源已更新但 `.kiro/` 还是旧内容——agent 读到的是旧的。

| 检查　　　　　　　　　　　　　　　　　　　　　　　　| 动作　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　|
| -----------------------------------------------------| -----------------------------------------------------------------------------|
| `scripts/sync-shims.sh` 存在且可执行？　　　　　　　| 从模板复制 + `chmod +x`　　　　　　　　　　　　　　　　　　　　　　　　　　 |
| **`bash scripts/sync-shims.sh --check` 通过？**　　 | ❌ DRIFT → 跑 `bash scripts/sync-shims.sh` 立刻修复　　　　　　　　　　　　　|
| (Antigravity) 根目录 `AGENTS.md` 含 `AUTO-GENERATED SHIMS START`？ | 跑 `python scripts/sync-shims.py` 注入编译产物 |
| `.kiro/steering/00-discipline.md` 含 6.9 + 6.10？　 | 跑 sync-shims（源是 `.agent/skills/agent-discipline.md`）　　　　　　　　　 |
| `.kiro/steering/01-philosophy.md` 内容 ≠ 模板占位？ | 如果 `.agent/core/philosophy.md` 已填实但 `.kiro/` 还是模板 → 跑 sync-shims |
| `.kiro/steering/02-conventions.md` 已按栈裁剪？　　 | 同上　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　|
| `.kiro/steering/03-boundaries.md` 指向真实目录？　　| 同上　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　|
| `.kiro/steering/04-glossary.md` 有实际术语？　　　　| 同上　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　|
| `.kiro/steering/05-indexes.md` 含最新索引？　　　　 | 同上　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　|
| `.kiro/skills/frontend-patterns/SKILL.md` 存在？　　| 跑 sync-shims　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　 |
| `.kiro/skills/design-tokens/SKILL.md` 存在？　　　　| 跑 sync-shims　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　 |
| `.kiro/skills/state-machines/SKILL.md` 存在？　　　 | 跑 sync-shims　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　 |
| `.kiro/skills/pbt-cookbook/SKILL.md` 存在？　　　　 | 跑 sync-shims　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　 |

> **记住**：`.kiro/` 下所有 `AUTO-GENERATED` 文件都是 `.agent/` 的编译产物。
> 编辑了 `.agent/` 之后**必须跑 `sync-shims.sh`**，否则 agent 读到的是旧版。
> lefthook 在 commit 时会拦截漂移，但如果你还没 commit 就开新对话——漂移就生效了。

### Hook 层

| 检查　　　　　　　　　　　　　　　　　　　　　　　　　　 | 动作　　　 |
| ----------------------------------------------------------| ------------|
| `.kiro/hooks/post-task-verify-and-sync.kiro.hook` 存在？ | 从模板复制 |
| `.kiro/hooks/pre-task-context-check.kiro.hook` 存在？　　| 从模板复制 |
| `.kiro/hooks/post-merge-sync-map.kiro.hook` 存在？　　　 | 从模板复制 |
| `.kiro/hooks/post-adr-impact.kiro.hook` 存在？　　　　　 | 从模板复制 |
| `lefthook.yml` 存在且含 `shim-in-sync` 规则？　　　　　　| 从模板复制 |

### Sub-agent 层

| 检查 | 动作 |
|---|---|
| `.agent/sub-agents/executor.md` 存在？ | 从模板复制 |
| `.agent/sub-agents/researcher.md` 存在？ | 从模板复制 |
| `.agent/sub-agents/fixer.md` 存在？ | 从模板复制 |
| `.agent/sub-agents/_index.md` 含 9 个 sub-agent？ | 从模板复制 |

### Workflow 层

| 检查　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　| 动作　　　 |
| -------------------------------------------------------------------------| ------------|
| `.agent/workflows/fix-review-feedback.md` 存在？　　　　　　　　　　　　| 从模板复制 |
| `.agent/workflows/verify-loading.md` 存在？　　　　　　　　　　　　　　 | 从模板复制 |
| `.agent/workflows/patch-check.md`（本文件）存在？　　　　　　　　　　　 | 从模板复制 |
| `.agent/workflows/bootstrap-project.md` 含 Stage 2.5（design-system）？ | 从模板复制 |

### 项目化检查（这些不能从模板复制，必须根据项目填）

| 文件 | 检查 | 缺失时动作 |
|---|---|---|
| `.agent/core/philosophy.md` | 无 `{...}` 占位 | 跟用户对话填写 |
| `.agent/core/design-system.md` | DS-1 到 DS-8 至少填了 DS-1/2/3/4 | 跟用户对话填写 |
| `.agent/core/conventions.md` | 分层表用真实目录名 | 根据 ADR-0001 调整 |
| `.agent/core/boundaries.md` | import 图用真实目录名 | 根据 ADR-0001 调整 |
| `.agent/core/glossary.md` | ≥ 3 个 active 术语 | 从代码 + 对话提取 |
| `.agent/adr/0001-foundation.md` | Decision 段无 `{TBD}` | 根据实际栈填写 |
| `.agent/skills/frontend-patterns.md` | Layer 表用真实目录名 | 根据 boundaries 调整 |
| `.agent/skills/design-tokens.md` | token 分类匹配 `shared/tokens/` 实际结构 | 根据 design-system 调整 |
| `shared/tokens/` | 至少有 `base/color.json` | 根据 design-system 创建 |

## 输出

```
📋 Patch-check 结果：

✅ OK: {N} 项
⚠️ 过时: {N} 项（需要 sync-shims 或小调整）
❌ 缺失: {N} 项（需要从模板复制或跟用户对话填写）

缺失清单：
1. {文件} — {动作}
2. ...

建议：先跑 sync-shims，再逐个补 ❌ 项。
```

## 反模式

- **跳过项目化检查**——从模板复制的文件如果没填实，agent 会读到 `{TBD}` 占位然后困惑
- **只跑 sync-shims 不检查项目化**——编译层 OK 但内容层可能全是模板占位
- **把 patch-check 当成 bootstrap 的替代**——patch-check 是"补丁"，不是"从头来"