---
id: workflow-start-feature
status: active
---

# 工作流：start-feature（Spec 的 pre/post 补充）

> **方向 A**：Kiro spec（Requirements → Design → Tasks）是主工作流。
> **方向 B**：Antigravity Planning Mode（implementation_plan → task → walkthrough）。
> 本 workflow 不替代 spec 流程，而是在它**之前**做 triage + 意图确认，
> 在它**之后**做 verify + flow 更新 + 收尾。IDE 不同，中间段自动切换。

## 何时触发

- 用户说"做 X" / "加 X" / "我要让用户能 X"
- 意图匹配：AGENTS.md 规则自动识别

## 整体流程

```
用户提需求
    ↓
[Pre-spec] 本 workflow 前半段（triage + 确认 + 探查）
    ↓
┌─── Kiro ───────────────────────────────────┐  ┌─── Antigravity ─────────────────────────┐
│ 用户点 Create New Spec                     │  │ Agent 创建 implementation_plan.md       │
│ → Requirements → Design → Tasks → 执行     │  │ → 用户批准 → 创建 task.md → 执行        │
└────────────────────────────────────────────┘  └─────────────────────────────────────────┘
    ↓
[Post-spec] 本 workflow 后半段（verify + visual-review + flow + 收尾）
    ↓
[走查修复] 如有问题 → fix-review-feedback workflow
```

---

## Pre-spec 阶段（在 Kiro spec 之前）

### Step 1: 反向确认意图

用**用户的心智模型**复述：

- 用户能从{何处}做{什么}
- 系统在{触发条件}下展示{什么}
- 验收信号是{什么}

得到"对"才继续。

### Step 2: 判定层级

判断触动哪些层（参考 `boundaries.md`）：

- L0 token / L1 primitive / L2 composite / L3 feature / L4 page
- shared schema / event / api-contract
- 是否需要新 flow

### Step 3: 探查现状（调 explorer）

```
🔧 Calling sub-agent: explorer
📥 Input:
    question: "是否已有相似 flow？这个域里已有哪些 schema/event？邻近哪些页面？"
    scope: {相关目录}
    budget: { max_files_read: 30 }
📤 Output: {结构化清单}
```

用结论决定：复用什么、新建什么。

### Step 4: 启动 Spec 流程（按 IDE 分支）

#### 4A. Kiro 路径

告诉用户：

```
✅ Pre-spec 完成。建议：
- Spec 名称：{slug}
- 涉及层级：{L3 + L4 + shared/schemas}
- 可复用的现有组件：{explorer 发现的}
- 需要新建的：{列表}
- 建议同时创建/更新的 flow：FLOW-{NNN}

请点 Kiro 面板的 "Create New Spec" 开始。
Spec 完成后告诉我，我来做 post-spec 验证。
```

**然后停。等 Kiro spec 流程走完。**

#### 4B. Antigravity Planning Mode 路径

不需要 Kiro 面板。Agent 直接利用 Antigravity 原生 Planning Mode：

1. **创建 `implementation_plan.md`**（对应 Kiro 的 Requirements + Design）：
   - 目标描述 + 背景
   - 用户审核项（Breaking changes / 重大设计决策）
   - 逐文件的 Proposed Changes（按组件分组）
   - Verification Plan
   - 设置 `RequestFeedback: true` 请求用户批准

2. **等用户批准** → 停。不要在批准前写任何代码。

3. **创建 `task.md`**（对应 Kiro 的 Tasks）：
   - 将 implementation_plan 拆解为可勾选的 checklist
   - 逐项标记 `[ ]` → `[/]` → `[x]`

4. **执行**：按 task.md 逐项实施，遵循 `agent-discipline.md` 6.9 停点纪律。

5. **创建 `walkthrough.md`**（对应 Kiro 的 Post-spec summary）：
   - 记录所有变更、测试结果、验证结论

```
✅ Pre-spec 完成。我将创建 implementation_plan.md。
- Feature 名称：{slug}
- 涉及层级：{L3 + L4 + shared/schemas}
- 可复用的现有组件：{explorer 发现的}
- 需要新建的：{列表}
- 建议同时创建/更新的 flow：FLOW-{NNN}

请审阅 implementation_plan 后批准，我再开始执行。
```

**然后停。等用户批准 implementation_plan。**

---

## Post-spec 阶段（Kiro spec tasks 全部完成后）

### Step 5: 验证（调 executor + verifier）

```
🔧 Calling sub-agent: executor
📥 Input:
    task: "全量验证 feature {slug}"
    commands:
      - cmd: "npm run typecheck"
      - cmd: "npm test"
      - cmd: "npm run lint"
📤 Output: {pass/fail + 失败摘要}
```

如果有 PBT：

```
🔧 Calling sub-agent: verifier
📥 Input:
    spec: .kiro/specs/{slug}
    suites: { unit: true, pbt: true, e2e: true }
📤 Output: {结果}
```

### Step 6: 视觉确认（如有 UI）

```
🔧 Calling sub-agent: visual-reviewer
📥 Input:
    target:
      components: {新增/修改的组件}
      states: {交互态矩阵}
    baseline: previous
    intent:
      philosophy_principles: [P1, P3]
      design_system: [DS-1, DS-2, DS-7]
📤 Output: {视觉差异报告}
```

给用户看报告。

### Step 7: 更新 flow（如有 UI）

如果 pre-spec 判定需要新 flow 或更新现有 flow：

- 新建：用 `.agent/flows/_template.md` 创建 `FLOW-{NNN}`
- 更新：修改现有 flow 的路径 / 交互态矩阵 / 引用

### Step 8: 收尾

- glossary 有新术语 → 提议加入
- 有非平凡决策 → 写 ADR
- 如果本 feature 引入了新实体或改变了实体关系 → 更新 `domain/entities.md` + `domain/concept-map.mmd`
- 跑 `regenerate-map`（hook 应该已自动触发，确认一下）
- 确认 spec 状态为 `done`

```
✅ Feature {slug} 完成。
📂 产物：
  - Spec: .kiro/specs/{slug}/ (done)
  - Flow: FLOW-{NNN} (active)
  - Tests: pass
  - Visual: reviewed

有问题？直接告诉我，我会走 fix-review-feedback 流程。
```

---

## 与其它 workflow 的关系

| 场景 | 用什么 |
|---|---|
| 新功能的规划+实施（Kiro） | **本 workflow**（pre/post）+ **Kiro spec**（中间） |
| 新功能的规划+实施（Antigravity） | **本 workflow**（pre/post）+ **Planning Mode**（中间） |
| spec 完成后走查修复 | `fix-review-feedback.md` |
| 架构层调整 | `architecture-change.md` |
| 上下文将满 | `write-handoff.md` |

## 反模式

- **跳过 pre-spec 直接建 spec / plan**——没有 triage 和 explorer，可能基于错误假设
- **跳过 post-spec 直接说"完成"**——没有 verify 和 visual-review，bug 留到走查
- **在 post-spec 里引入新 feature**——那是另一个 spec
- **Antigravity 下跳过 implementation_plan 直接写代码**——违反 Planning Mode 的批准流程
