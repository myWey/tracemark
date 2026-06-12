---
id: workflow-fix-review-feedback
status: active
---

# 工作流：fix-review-feedback（走查修复）

> Spec tasks 完成后，用户走查产出一批混杂反馈（bug、视觉、体验、逻辑）。
> 本 workflow 规定：**主 agent triage + 决策，sub-agent 执行重 IO**。

## 何时触发

- 用户在 spec tasks 完成后给出反馈（关键词：bug、报错、不对、修、调整、问题）
- 用户粘贴控制台报错 / 截图 / 走查清单
- `post-task-execution` hook 后用户开始提问题

## 输入

用户的混杂反馈——**不要求格式化**。可以是：
- 编号清单
- 一段吐槽
- 截图 + 一句话
- 控制台报错粘贴
- 以上混合

## Stage 列表

| # | Stage | 产物 | 必停 |
|---|---|---|---|
| 1 | Triage（分类 + 排序） | 分类表 | ✅ |
| 2 | 逐个修复（按优先级） | 代码改动 | 每 2–3 个停一次 |
| 3 | 批量验证 | executor 输出 | ✅ |
| 4 | 视觉确认（如有 UI） | visual-reviewer 输出 | ✅ |
| 5 | 收尾 | 更新 spec / flow 状态 | — |

## Stage 1: Triage

**必须先分类再动手。不允许看到第一个 bug 就开始修。**

输出格式：

```
📋 Triage（{N} 条反馈）：

| # | 问题摘要 | 分类 | 严重度 | 修复方式 | 调谁 |
|---|---|---|---|---|---|
| 1 | ... | token/状态机/代码bug/UI补充/API/体验 | crash/功能/体验 | 改 N 行/加组件/改状态机/... | 主agent/explorer→主/fixer/... |

优先级：crash > 功能缺失 > 行为错误 > 视觉 > 体验微调
建议顺序：#{X} → #{Y} → #{Z}...

Continue? (y / 调整顺序 / 先只修前 N 个)
```

**分类规则**：

| 分类 | 判据 | 典型修复 |
|---|---|---|
| crash / 报错 | 控制台 error、白屏、500 | 读代码 → 修逻辑 |
| 功能缺失 | "点了没反应"、"没有 loading" | 加状态 / 加 handler |
| 行为错误 | "跳转到了错误页面" | 修路由 / 条件 |
| 视觉-token | "颜色不对"、"间距太紧" | 改 token 引用 |
| 视觉-组件 | "缺空状态"、"缺插图" | 加组件 |
| 体验微调 | "感觉不够流畅" | 加动效 / 调时序 |

### Sub-agent 在 triage 阶段的使用

- 如果报错信息不足以定位（只有 error message 没有 stack）→ 调 **executor**
  跑一次 reproduce 拿完整 stack
- 如果反馈涉及"不确定现在代码是怎么写的"→ 调 **explorer** 先看

## Stage 2: 逐个修复

按 triage 排好的顺序，**每个问题**走这个 mini-loop：

```
修复 #{N}: {问题摘要}
├── 需要探查？ → 🔧 explorer（返回位置 + 上下文）
├── 主 agent 修改代码
├── 需要验证？
│   ├── 改动 < 50 行输出 → 主 agent 自己跑
│   └── 改动可能影响其它 → 🔧 executor（跑相关测试）
└── ✅ #{N} done
```

**每修完 2–3 个问题**，输出一次 checkpoint：

```
✅ 已修：#{1} #{3} #{5}
⏳ 待修：#{2} #{4} #{6}
🔧 executor 验证中间状态...
📤 executor: 全部 pass / {N} 失败

Continue? (y / 暂停 / 调整)
```

### 什么时候调 sub-agent（修复阶段）

| 情况 | 调谁 |
|---|---|
| 需要定位 bug 根因（不确定在哪） | **explorer** |
| 修完后跑测试 | **executor** |
| 同类问题 > 5 处（如"所有按钮颜色都错"） | **fixer**（pattern + scope） |
| 不确定某个 API 的正确行为 | **researcher** |
| 修完 UI 后看效果 | **visual-reviewer** |

### 什么时候主 agent 自己修

- 已知位置、改 ≤ 5 文件、不需要大量探查
- 涉及判断（"这里该用哪个方案"）
- 状态机调整（需要理解 flow 上下文）

## Stage 3: 批量验证

所有问题修完后（或一批修完后）：

```
🔧 Calling sub-agent: executor
📥 Input:
    task: "全量验证走查修复"
    commands:
      - cmd: "npm run typecheck"
        expect: pass
      - cmd: "npm test"
        expect: pass
      - cmd: "npm run lint"
        expect: pass
    budget:
      max_total_seconds: 300

📤 executor output:
    status: pass | fail
    failures: [...]
```

如果有失败 → 回到 Stage 2 修对应问题。

## Stage 4: 视觉确认（如有 UI 改动）

```
🔧 Calling sub-agent: visual-reviewer
📥 Input:
    target:
      components: [修改过的组件]
      states: [涉及的交互态]
    baseline: previous
    intent:
      spec: {当前 spec}
      philosophy_principles: [P1, P3]

📤 visual-reviewer output:
    status: pass | warn
    diffs: [...]
```

给用户看视觉差异报告。用户确认 → 进 Stage 5。

## Stage 5: 收尾

- 如果修复涉及 flow 变更 → 更新对应 `.agent/flows/{NNN}-*.md`
- 如果修复暴露了 ADR 不足 → 提议新 ADR
- 如果修复暴露了 glossary 缺词 → 提议加入
- spec 状态确认仍为 `done`（修复不改 spec 状态，除非发现 spec 本身有误）
- 跑 `regenerate-map`（如果改动涉及 shared/ 或新组件）

## 上下文管理（关键）

修复阶段是**上下文消耗最快**的——每个 bug 都要读 + 改 + 验证。

| 反馈数量 | 策略 |
|---|---|
| 1–3 个简单 | 同窗口搞定 |
| 4–8 个混合 | 同窗口，每 2–3 个 checkpoint |
| > 8 个 / 跨多模块 | **分批**：先修 crash → handoff → 新窗口修体验 |
| 修到一半 > 60% | 立刻 handoff，把"已修/未修"写进去 |

## 反模式

- **看到第一个 bug 就开始修，不 triage**——后面的 bug 可能跟前面的有因果关系
- **一次修完 8 个再验证**——中间某个修复可能破坏另一个
- **把完整报错日志粘进对话**——只粘关键行，让 explorer 去看全文
- **在修复阶段引入新 feature**——修复是修复，新功能开新 spec
- **让 sub-agent 独立修 bug**——sub-agent 没有 philosophy / ADR 上下文，修出来可能违反设计
- **不调 executor 自己看测试输出**——3000 行日志进主 context 是灾难
