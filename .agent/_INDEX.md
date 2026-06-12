---
id: agent-index
status: active
audience: human + agent
purpose: 整个 .agent/ 的入口索引；杀掉所有孤儿文档
last-confirmed: null
---

# .agent/ 总索引

> 所有 `.agent/` 下的文档都从这里可达。**没有从这里可达的文档 = 孤儿**，
> 应该被 prune 或注册进来。

## 第一次来？

读 [`_README.md`](./_README.md)（5 分钟）。

## Meta 文档（关于范式本身）

| 文件 | 给谁看 | 什么时候看 |
|---|---|---|
| [`_README.md`](./_README.md) | 人（新读者） | 首次接触 |
| [`_meta.md`](./_meta.md) | 人 + 资深 agent | 想理解结构 |
| [`_LIMITATIONS.md`](./_LIMITATIONS.md) | 人 | 决定要不要用、单人项目取舍 |
| [`_HARNESS.md`](./_HARNESS.md) | 人 + 资深 agent | 想知道与前沿对齐情况 |
| [`_TRIGGERS.md`](./_TRIGGERS.md) | 人 | 想知道哪份文档何时被读 |

## 主要内容（按层级）

### Core 层（始终注入 agent）
- [`core/philosophy.md`](./core/philosophy.md)——产品哲学（人主导）
- [`core/conventions.md`](./core/conventions.md)——代码 / 命名 / 分层 / 语言约定
- [`core/boundaries.md`](./core/boundaries.md)——模块边界
- [`core/glossary.md`](./core/glossary.md)——领域术语
- [`core/dialog-rules.md`](./core/dialog-rules.md)——**给人**的对话规则

### Domain 层
- [`domain/entities.md`](./domain/entities.md)
- [`domain/concept-map.mmd`](./domain/concept-map.mmd)

### Decision 层
- [`adr/_index.md`](./adr/_index.md)——架构决策清单
- [`adr/_template.md`](./adr/_template.md)
- [`flows/_index.md`](./flows/_index.md)——前端流程清单
- [`flows/_template.md`](./flows/_template.md)

### Map 层（自动生成）
- [`map/_generators.md`](./map/_generators.md)——生成器说明
- `map/architecture.md` / `map/api-surface.md` / `map/component-tree.md` /
  `map/adr-timeline.md`——派生视图

### Session 层
- [`sessions/_template.md`](./sessions/_template.md)——handoff 模板

### Skills 层（按需 + 一个 always-on）
- [`skills/_index.md`](./skills/_index.md)
- [`skills/agent-discipline.md`](./skills/agent-discipline.md)——**always-on** 行为护栏

### Workflows 层
- [`workflows/_index.md`](./workflows/_index.md)
- 关键入口：[`wizard`](./workflows/wizard.md) / [`verify-loading`](./workflows/verify-loading.md) /
  [`start-feature`](./workflows/start-feature.md) / [`prune`](./workflows/prune.md)

### Sub-agents 层
- [`sub-agents/_index.md`](./sub-agents/_index.md)
- 6 个 sub-agent：explorer / verifier / visual-reviewer / impact-analyzer /
  doc-syncer / scribe

## 阅读路径推荐

**第一次接触**：
`_README.md` → `_LIMITATIONS.md` → `core/dialog-rules.md`

**想了解结构**：
`_meta.md` → `_TRIGGERS.md` → `_HARNESS.md`

**开干**：
`workflows/wizard.md` → `workflows/verify-loading.md` →
`workflows/start-feature.md`

**调试范式没生效**：
`workflows/verify-loading.md` → `_TRIGGERS.md` → `_LIMITATIONS.md` 第 1、3、7 条

## 孤儿检测

如果你新增了 `.agent/` 下的文档：

1. 这份索引必须有它。
2. 如果它属于某个子目录，对应的 `_index.md` 也必须有它。
3. 如果都没有 → 它是孤儿，跑 `prune` 时会被标记。
