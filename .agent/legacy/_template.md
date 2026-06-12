---
id: legacy-{slug}
status: active-bridged
legacy-source: {repo 内绝对路径，例如 docs/rfcs/2024-payment-flow.md}
type: RFC | DESIGN | SPEC | OAPI | ADR-OLD | WIKI | README-LEGACY
original-author: {如能确定}
last-touched-in-legacy: {git log 最后修改的 commit 短 sha 或日期}
related-adrs: []
related-flows: []
canonical-status: bridged | orphan
---

# Bridge: {Legacy 标题}

> 这是 **legacy bridge**，不是新决策。原文在
> `{legacy-source}`，**保留原位**。本文件让 agent 知道：
>
> - 原文在哪
> - 关键决策摘要（≤ 5 条）
> - 当前 AgentOS 下 canonical 版本在哪（`related-adrs` / `related-flows`）

## 原文位置

`{legacy-source}`（点击直接打开）

> **不要修改原文**。原文是历史记录，git blame 不能断。

## 关键决策摘要（agent 抽取，人审）

> ≤ 5 条。如果旧文档里有 20 条，挑最关键的；其余仍在原文。

1. {决策 1}
2. {决策 2}
3. ...

## Canonical 版本

| 决策 # | 当前 canonical 在哪 |
|---|---|
| 1 | ADR-{NNNN} or FLOW-{NNN} |
| 2 | shared/api-contracts/{path} |

如果 `canonical-status: orphan` → 还没有 canonical 版本，本 bridge 是**临时
权威**，下次相关 PR 必须把它迁到 ADR / FLOW，并把状态升到 `bridged`。

## 已知偏离（旧文档错的地方）

> 旧文档跟现状不一致的地方。**不要改原文**——这里记录"读时怎么修正"。

- {段落 / 章节}：原文说 X，但实际代码已改为 Y（见 commit {sha}）

## Agent 用法

1. 读到代码注释引用 `{legacy-source}` 时——先来本 bridge 看 canonical 在哪
2. 如果 `related-adrs` 非空 → 直接读 ADR；旧文档**不再权威**
3. 如果 `canonical-status: orphan` → 涉及该决策的代码改动**必须 flag** 给
   用户，提议把决策迁到 ADR / FLOW
4. **永远不要**直接基于 legacy 内容做新决策——bridge 是只读引用层
