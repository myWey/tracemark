---
id: adr-index
status: active
---

# 架构决策记录（ADR）索引

> Append-only。每行：ID、slug、状态、supersedes、epoch、一句话摘要。

| ID | Slug | 状态 | Supersedes | Epoch | 摘要 |
|----|------|------|------------|-------|------|
| 0001 | foundation | active | — | epoch-0 | 初始 stack 与分层 |
| 0002 | annotations-serialization | proposed | — | epoch-0 | 标注的序列化与历史记录再编辑架构 |
| 0003 | native-ocr-and-translation | proposed | — | epoch-0 | 调用 macOS 原生 Vision 与 Translation 框架实现 OCR 与翻译 |

## 状态枚举

- `proposed`——讨论中
- `active`——当前
- `superseded`——被新 ADR 取代（`supersedes` 标注）
- `rejected`——提议但未采纳（保留以追溯）
- `ratified-retroactively`——retrofit 时追认；表示决策早已发生，文档是补的

## 如何新增

1. 复制 `_template.md` 为 `{NNNN}-{slug}.md`。NNNN 为下一个补零编号。
2. 填模板。
3. 在本索引追加一行。
4. 如果取代了旧 ADR：旧 ADR 的状态改为 `superseded`，`superseded-by` 指向新 ADR。
5. 跑 `.agent/sub-agents/impact-analyzer.md`，把输出附到新 ADR 的 Impact 段。

## ADR vs Flow（什么时候写哪个）

- **写 ADR**：决策影响**架构层**——状态库选型、路由方案、API 风格、跨层规则、
  部署形态、关键依赖。
- **写 flow**：决策影响**用户感知层**——这个流程几步、loading 怎么呈现、
  empty 文案、错误如何挽救、跨页跳转。
- **两个都写**：架构选型由 UX 约束反推（如"必须能离线"→选本地优先架构）。

## Retrofit 追认

- 状态用 `ratified-retroactively`
- 头部 `original-decision-time: best-guess | git-blame-derived | unknown`
- Decision 段写**当前如何做**，不假装当时讨论过备选
- Consequences 段务实写**已观察到的**正负后果
