---
id: workflow-drift-check
status: active
---

# 工作流：drift-check

## 目的

定期验证内层洋葱（philosophy、glossary、boundaries、ADR、flow）仍贴近外层
现实（代码、行为、契约）。这是 agentic 版的"复盘"——**不按时间驱动，按
epoch 驱动**。

## 何时跑

- 一个 epoch 结束（重大里程碑后或累计了 N 条重要 ADR 后）
- 任意核心文件的 `last-confirmed` 距今 > ~3 个月**且**期间有大量变更
- 重大外部事件之前（发布、审计、新成员入场）

## 步骤

### 1. 快照现实

- 列出上次 drift-check 后落地的 ADR
- 列出上次后变 `done` 的 spec
- 跑 `regenerate-map`，与上次重生成做 diff

### 2. 对齐哲学

每条原则（P1…Pn）：

- 找出至少一个最近的决策 / 代码**遵守**了它（说明仍在用）
- 找出至少一个**违反**了它（说明漂移）
- 既无遵守也无违反（孤立）→ 标出来

反模式（A1…An）同样的检查。

向用户提议：

- 可退役的原则（已不具判断力）
- 可新增的原则（从真实决策中浮现）
- 优先级是否要调整

### 3. 对齐 glossary

- 代码里出现但 glossary 里没有的词 → 提议加入（征询用户）
- glossary 里有但代码里完全没有的词 → 标 `deprecated` 或移除
- 同义词渗入代码 → 提示一致性问题（征询用户）

### 4. 对齐 ADR

- `active` 的 ADR 但其决策已不在代码中体现 → 候选 `superseded`（需要新 ADR
  说明替代物）
- 验证标准已无法验证的 ADR → 标出来

### 5. 对齐 flow

- `active` 但实际产品已不是这个流程的 flow → 候选 `superseded` 或 `deprecated`
- 实际有但 flow 没记的用户路径 → 提议补 flow
- flow 引用了已不存在的组件 / API / 事件 → 引用失效，必须修

### 6. 对齐 boundaries

- 跑 dep graph，列每个跨层 import
- 每个违反要么修，要么以 ADR 记录例外

### 7. 更新 `last-confirmed`

每个用户确认仍正确的核心文件，把 `last-confirmed` 更新为今日（仅审计）。

### 8. 可能开新 epoch

显著的内层变化发生 → `git tag epoch-N`。

## 输出

- 一份简短报告：漂移项、建议更新
- 已更新的 `last-confirmed` 字段
- 必要时的新 ADR

## 完成判定

每个核心文件要么有新鲜的 `last-confirmed`，要么有 tracked 的漂移项。

## 反模式

- 当成例行公事。它的价值在**强迫问"这个还成立吗"**。
- 按日历跑（每周一）。按 epoch / 变更体量跑。
