---
id: skills-index
status: active
---

# Skills 索引

> 按需加载的知识包。主 agent 只在当前任务匹配 `relevance` 时加载某个 skill。
> 用来给主 prompt **瘦身**，不让无关知识常驻。

## 现有 skill

| Skill | 何时相关 | 加载时机 |
|---|---|---|
| [`agent-discipline`](./agent-discipline.md) | **Always-on** 行为约束（Karpathy pitfalls + 项目扩展） | 每次会话常驻 |
| [`pbt-cookbook`](./pbt-cookbook.md) | 写 / review property-based test | 按需 |
| [`frontend-patterns`](./frontend-patterns.md) | 在 Layer 1–4 构建 UI | 按需 |
| [`state-machines`](./state-machines.md) | 设计复杂 UI 交互的状态 | 按需 |
| [`design-tokens`](./design-tokens.md) | 改 / 提议 `shared/tokens/` 下的 token | 按需 |

## 文件语言约定

skill 文件**保留英文为主**——它们是技术 reference，跨工具传播性更好。
主 agent 解读后用中文跟用户讨论。

例外：`agent-discipline.md` 是行为护栏，部分项目特定扩展可能含中文 ID
（如 `P1`），这是正常的——它是给主 agent 的常驻 prompt。

## 新增 skill

1. `skills/{topic}.md` 头部：
   ```yaml
   ---
   id: skill-{topic}
   relevance: {简短触发条件 / always-on}
   ---
   ```
2. 正文：短、动作导向。skill 不是教程。
3. 在本索引追加一行。
4. 如果是 always-on，必须在 `AGENTS.md` 必读清单中也注册。

## 加载量预算

- 平凡任务：仅 always-on（`agent-discipline`）
- 范围明确的任务：always-on + 1–2 个按需 skill
- 超过 always-on + 2 个按需 → 怀疑任务太宽，先拆

## 长尾 skill 的 prune 策略

skill 数量超过 8 个 → 跑 `.agent/workflows/prune.md`。长尾 skill 比缺失
skill 更糟：它们抢加载预算，agent 在选择时会噪声化。
