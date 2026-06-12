---
id: flows-index
status: active
---

# 前端流程索引（FLOWS）

> 前端的"决策有家"。承载页面、组件、交互、跳转、状态——人类讨论前端时的自然介质。
>
> 与 ADR 平行：ADR 解决**架构决策**（占决策的少数），flow 解决**前端实现层决策**
> （占决策的多数）。

## 索引

| ID | Slug | Status | Epoch | 摘要 |
|----|------|--------|-------|------|
| 001 | screenshot-and-thumbnail | active | epoch-0 | 区域截图与悬浮分发流程 |
| 002 | annotation-canvas | active | epoch-0 | 矢量标注层与画布编辑流程 |
| 003 | pin-and-history-edit | proposed | epoch-0 | 贴图Pin与历史截图再编辑流程 |
| 004 | ocr-and-image-translation | proposed | epoch-0 | OCR文字识别与图像一键翻译流程 |

## flow 与 ADR 的边界

- **写 ADR**：决策影响**架构层**——状态管理库、路由方案、API 风格、跨层规则。
- **写 flow**：决策影响**用户感知层**——这个流程几步、loading 怎么呈现、
  empty 状态文案、错误如何挽救、跨页跳转动效。
- **既写 ADR 又写 flow**：架构选型受 UX 约束反推（如"流程必须能离线，所以选
  本地优先架构"）——两份都要，互相引用。

## 状态

- `proposed`——讨论中
- `active`——当前
- `superseded`——被新 flow 替代（在 `supersedes` 标注）
- `deprecated`——功能下线，flow 保留供历史

## 如何新增

1. 复制 `_template.md` 为 `{NNN}-{slug}.md`。NNN 是下一个补零编号。
2. 填模板。
3. 在本索引追加一行。
4. 如果替代了既有 flow，标注 `supersedes` 并把旧 flow 状态改为 `superseded`。
5. 在引用的 spec / 代码注释里用 `FLOW-NNN` 引用。

## flow 与 spec 的关系

- spec（`.kiro/specs/{slug}/`）是**实施单位**——一个开发周期的计划与产物。
- flow 是**流程定义**——可能跨多个 spec 沉淀，比 spec 更长寿。
- 一个 spec 通常产出/更新一个或多个 flow。
