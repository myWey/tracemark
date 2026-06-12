---
id: legacy-index
status: active
audience: human + agent
purpose: 列出旧范式遗留的所有文档及其在 AgentOS 下的处置；agent 看到 legacy 内容时知道权威性
last-confirmed: null
---

# Legacy 文档索引

> 这个项目嵌入 AgentOS 时，已存在大量旧范式产出（feature specs、RFC、wiki、
> ADR…）。这份索引让 agent **知道这些文档存在、知道它们的当前权威性**——
> 不是丢弃，也不是无差别遵守。

## 三种状态枚举（重要）

| 状态 | 含义 | Agent 行为 |
|---|---|---|
| `archived` | 已实施且稳定，纯历史价值 | 仅追溯时读；当前决策**不参考** |
| `active-bridged` | 仍在指导代码，但已经在 ADR / FLOW 里有 canonical 版本 | 以 canonical 版本为准；旧文档作为补充信息 |
| `active-orphan` | 仍在指导代码，**尚未** 迁出 canonical 版本 | **临时权威**，下一个相关 PR 必须迁出来 |

> **极重要的硬规则**：当 ADR / FLOW 与 legacy 冲突时——
> - 如果 legacy 是 `archived` → ADR / FLOW 胜
> - 如果 legacy 是 `active-bridged` → ADR / FLOW 胜（legacy 是 superseded）
> - 如果 legacy 是 `active-orphan` → **flag 给用户，不静默选**

## 索引

| 旧文档路径 | 类型 | 状态 | 桥接到 | 备注 |
|---|---|---|---|---|
| _暂无_ | | | | |

## 类型缩写

- `RFC` — Request for Comments
- `DESIGN` — design doc / 技术设计
- `SPEC` — feature spec
- `OAPI` — OpenAPI / GraphQL / proto
- `ADR-OLD` — 旧的决策记录
- `WIKI` — Confluence / Notion / 等
- `README-LEGACY` — 旧 README

## 添加规则

新发现一份 legacy 文档：

1. 在表格里加一行（路径相对于 repo 根；保留原始路径，**不要 mv**）
2. 决定状态（默认 `active-orphan`，待用户确认后定）
3. 如果是 `active-bridged`，用 `_template.md` 创建一个 bridge 文档
4. 在原 legacy 文档**末尾**加一个 markdown 注释（不改正文）：

   ```html
   <!-- AgentOS legacy: bridged-to .agent/adr/0007-foo.md
        canonical authority is in the ADR; this file kept for history only -->
   ```

## 减员策略

`active-orphan` 不应长期存在。每个 epoch 末跑 `drift-check`，把当时仍然 orphan
的文档列为下一个 epoch 的迁移目标。

`archived` 状态保留即可，**永不删除**——它们是 git history 的索引。
