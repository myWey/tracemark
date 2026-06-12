---
id: workflow-architecture-change
status: active
---

# 工作流：architecture-change

## 目的

干净地落地一次架构调整：写 ADR、产出 migration plan、作为**独立 PR**（不与
feature 混合）落地。这是对抗 "edit-and-pray" 熵增的最大单点防御。

## 何时跑

- schema / 契约要做破坏性变更
- 跨层模块的拆 / 合 / 改名
- 替换某个主要依赖或模式（状态库、ORM、路由器…）
- 在做某个 feature 时发现架构无法干净承载——暂停 feature，跑这个，再回去

## 输入

- 触发：是什么让你（或用户）意识到要改
- 期望终态（粗略即可）

## 步骤

### 1. 停止 feature 工作

架构调整**不**与 feature 共享 PR。如有 feature 在飞，先 `write-handoff`，
切分支，做这个工作流，再 resume feature。

### 2. 起草 ADR

复制 `.agent/adr/_template.md` 为 `.agent/adr/{NNNN}-{slug}.md`。填：

- 上下文（什么问题、什么力量、现状）
- 决策（一段话、不留歧义）
- 备选方案（≥ 2）
- 后果（正 / 负 / 中性）
- 验证（怎么知道选对了）

状态：`proposed`。

### 3. 跑 impact-analyzer

调 `impact-analyzer`：

- kind：`adr`（或 rename / move / schema-change）
- proposed_adr：新 ADR 路径
- description：决策摘要

把输出粘到 ADR 的 "Impact" 段。`confidence: low` 或 gaps 多 → 扩大 scope 重跑。

### 4. 识别 supersession

对 `affected.adrs` 与 `affected.flows` 中每一项：

- 真正被取代 vs 只是受调整 → 区分
- 真正被取代：把 ID 加到本 ADR 的 `supersedes`，把旧 ADR / flow 的 `status`
  改为 `superseded`，`superseded-by` 指向本 ADR

### 5. 用户确认

呈现：

- ADR 文本
- migration plan（原子步骤 + 风险等级）
- 风险 + 缓解

等明确 go / no-go。否则不要继续。

### 6. 执行 migration

每个 migration step 作为小 commit：

- 实施
- 调 `verifier`
- `must_be_atomic: true` 的 step 必须在该 PR 内完成

### 7. 不留半新半旧状态

代码不能在 PR merge 时处于"半新半旧"。要么变更在本 PR 内完整，要么本 PR 加
feature flag / adapter 让两态同时合法。

### 8. 落地

- ADR 状态 → `active`
- 更新 `.agent/adr/_index.md`
- 跑 `regenerate-map`
- 范围足够大 → 打新 epoch tag：`git tag epoch-N`

### 9. 后续

- 该最终迁移但本 PR 没做完的代码 → 显式归到 `.kiro/specs/migration-{NNNN}/`
- 代码里的 TODO 注释引用本 ADR + 后续 spec 链接

## 输出

- 新 ADR（status `active`）
- 更新过的 `_index.md`，可能多个 ADR / flow 转 `superseded`
- migration commits（无 feature 混入）
- 刷新过的 map
- 可能的 `epoch-N` tag

## 完成判定

- ADR 是 `active`
- 全部 `must_be_atomic` 步骤已落地
- 没有边界违反、没有失败测试
- 后续如有，已归档为显式 spec

## 反模式

- 把架构调整与 feature 混进同一 PR
- 直接编辑既有 ADR "修复"它（应该 supersede）
- 因"小所以跳过"impact-analysis——小恰恰是 blast-radius 出意外的时候
