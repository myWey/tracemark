---
id: agent-readme
status: active
audience: human (first-time reader)
purpose: 给"第一次接触 AgentOS"的人 5 分钟知道这是什么、值不值得用、怎么开始
last-confirmed: null
---

# AgentOS 5 分钟入门

> 你是**第一次**看到 `.agent/` 这个目录吗？这份是给你看的。
> 5 分钟读完决定要不要深入。

## 这是什么

一份**跨 IDE 的 agentic coding 工作骨架**。把"决策、流程、上下文、工具触发、
跨窗口续接"这些事在 `.agent/` 里一次性定下来，IDE（Kiro / Cursor / Claude
Code / Windsurf / Trae / Antigravity）通过薄壳引用。**换 IDE 不丢知识**。

## 值不值得用（30 秒判断）

✅ 值得：
- 项目生命周期 > 6 个月
- 你打算让 agent 写大部分代码而不只是补全
- 你担心几个月后忘记"为什么这么做"
- 你换过 IDE 或预期会换

❌ 不值得（直接关掉这页）：
- 一次性脚本
- 学习项目（要的就是从乱中找秩序的过程）
- 周末 demo

详细判断见 `.agent/_LIMITATIONS.md`。

## 怎么开始（3 步）

1. **开新对话窗口，粘**：
   ```
   跑 .agent/workflows/wizard.md
   ```
   wizard 会自动判断你是 0→1 还是嵌入既有项目，分流引导。

2. **跑验证**：
   ```
   跑 .agent/workflows/verify-loading.md
   ```
   确保 IDE 真的加载了 `.agent/`（光面板显示不算数）。

3. **跟 agent 干第一个 feature**——这一步比读文档更能学到。

## 你只需要主动读 4 份文档

其它都是 agent / 工作流自己处理。

| 文件 | 为什么读 | 何时读 |
|---|---|---|
| `_README.md`（本文件） | 决定要不要用 | 现在 |
| `_LIMITATIONS.md` | 知道它做不到什么 | 用之前 |
| `core/dialog-rules.md` | 跟 agent 高效说话 | 用之前 |
| `core/philosophy.md`（项目自己的） | 给 agent 的判断器 | bootstrap 后审核 |

## 完整地图（想了解全貌再读）

| 维度 | 文档 |
|---|---|
| 这套结构是什么 | `_meta.md` |
| 跟 harness 前沿对齐情况 | `_HARNESS.md` |
| 哪个文件何时被读写 | `_TRIGGERS.md` |
| 局限与减害 | `_LIMITATIONS.md` |
| 怎么跟 agent 说话 | `core/dialog-rules.md` |
| Agent 行为护栏 | `skills/agent-discipline.md` |
| 工作流清单 | `workflows/_index.md` |
| Sub-agent 清单 | `sub-agents/_index.md` |
| Skill 清单 | `skills/_index.md` |
| ADR 清单 | `adr/_index.md` |
| FLOW 清单 | `flows/_index.md` |

## 一句话

> **用 ADR / flow / shared / map 把决策固化下来，让 agent 只要遵守你的
> 哲学和约定就能干活——而不是靠人每次提醒**。

接下来：跑 `wizard` 或先读 `_LIMITATIONS.md`。
