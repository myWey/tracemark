---
id: sub-agents-index
status: active
---

# Sub-Agents 索引

> 9 个**按动作类型**而非按角色的 sub-agent。**没有** "frontend-agent" /
> "backend-agent" / "PM-agent"——那些是反模式。

## 触发原则（决定该不该调 sub-agent 的根本判据）

主价值是 **context isolation**，不是 parallelism。业界（2026.5）量化：用对
sub-agent 能减少主 context token 用量 **90%+**。

调用条件（满足任一）：

1. **Context pollution**：任务会向主 context 引入大量噪音中间产物（搜 50 个
   文件、跑 3000 行测试日志、读 5 份外部文档）
2. **Parallelizable**：有真正独立的子任务（同时跑测试 + 视觉差 + lint）
3. **Specialization**：需要不同的 prompt / 工具集 / 模型（视觉 review 需要
   多模态）

否则主 agent 自己做。

## 9 个 Sub-Agent

按职能分三类：

### Read-only investigators（只读探查类，4 个）

| Sub-agent | 何时调 | 输入 → 输出 |
|---|---|---|
| [`explorer`](./explorer.md) | 需要了解既有代码/状态 | 问题 + scope → 结构化清单 + 引用 |
| [`researcher`](./researcher.md) | 需要消化外部 docs / API / RFC | 问题 + sources → ≤ 800 字 actionable 摘要 |
| [`impact-analyzer`](./impact-analyzer.md) | 新 ADR / 重命名 / 重构提议 | 变更 + scope → 影响清单 + 迁移 task |
| [`visual-reviewer`](./visual-reviewer.md) | UI 改动后做视觉差异 | 组件 + 状态矩阵 → 差异报告 |

### Heavy-IO executors（执行类，2 个）

| Sub-agent | 何时调 | 输入 → 输出 |
|---|---|---|
| [`executor`](./executor.md) | 跑测试 / build / migration / 任何输出 > 200 行 | 命令序列 → pass/fail + 失败摘要 + reproduce_cmd |
| [`fixer`](./fixer.md) | 批量确定性修补（rename / codemod / lint-fix） | pattern + scope → applied N files + verification |

### Verifiers（验证类，1 个）

| Sub-agent | 何时调 | 输入 → 输出 |
|---|---|---|
| [`verifier`](./verifier.md) | 实施完成后验证行为（含 PBT） | spec → suites 结果 + counterexamples |

> **executor vs verifier 的区别**：executor 跑任意命令（build / migration
> / 重 IO），verifier 专跑测试套件并解读"对不对"。简单 commit-check 用
> executor；spec 验收用 verifier。

### Curators（维护类，2 个）

| Sub-agent | 何时调 | 输入 → 输出 |
|---|---|---|
| [`doc-syncer`](./doc-syncer.md) | merge 后更新派生文档 / map | trigger + changed paths → 已更新文件 |
| [`scribe`](./scribe.md) | 长任务、上下文将满 | task + ulid → handoff.md + quick-resume |

## 主 agent 决策表（什么任务调谁）

```
你要做什么                    →  调谁
────────────────────────────  ────────────────
理解既有代码                  →  explorer
理解外部库/API                →  researcher
评估改动影响                  →  impact-analyzer
跑测试/build/migration        →  executor
跑 spec 验收 + PBT            →  verifier
批量 rename / codemod          →  fixer
UI 改完看视觉                 →  visual-reviewer
merge 后刷新 docs/map         →  doc-syncer
上下文将满 / 阶段末           →  scribe
```

## 反模式（**不要**这样用 sub-agent）

- "frontend-agent" 写前端 + "backend-agent" 写后端——他们对彼此的假设会漂移
- "reviewer-agent" 审 "coder-agent" 而**没有人类参与**——同质失败
- "PM-agent" 把模糊请求转 spec **不跟用户对话**——杜撰需求
- "do-everything-agent"——sub-agent 应当任务 scoped，否则就是另一个主 agent

## I/O 契约（硬纪律）

每个 sub-agent 的独立文件里有显式的 input / output 契约。主 agent 传结构化输入，
拿回结构化输出。Sub-agent 是**无状态**的：每次调用都是新的；持久化通过文件。

## 调用强制（agent-discipline 6.10）

主 agent 调 sub-agent 时**必须可见**：

```
🔧 Calling sub-agent: {name}
📥 Input: {structured input}

[执行]

📤 Sub-agent {name} output: {structured output}
```

**禁止**默默在主 context 里干 sub-agent 该做的事。

## 文件语言约定

Sub-agent 定义文件**保留英文**——它们是 prompt + I/O schema，对模型友好。
人机共读的文档（philosophy / glossary / ADR / flow / spec）才用中文。
