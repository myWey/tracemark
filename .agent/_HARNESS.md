---
id: harness
status: active
audience: human + senior agent
purpose: 说明 AgentOS 在 harness 各维度的取舍，与 2026 前沿（Karpathy、Cat Wu、OpenAI Codex 团队）的对照
last-confirmed: null
---

# Harness 设计说明（AgentOS 是一份 lean harness）

> "Harness" 是 2026 年的 framing 词：**模型周围的一切让模型能稳定干活的脚手架**——
> instruction、context、tool、permission、verification、recovery。
> Anthropic（Cat Wu）、OpenAI（Codex 团队）、Mitchell Hashimoto 都在用同一个词。
>
> Anthropic 在分析 Claude Code v2.1.88 源码（2026.3 意外泄漏的 sourcemap）后给出
> 的数字：**98.4% 的代码是 harness，1.6% 是 AI decision logic**。harness 就是
> 项目的真正资产。
>
> 这份文档说明 AgentOS 在 harness 各维度上的取舍——哪些做了、哪些刻意没做、
> 哪些借自前沿。

## Harness 的 7 个维度（业界共识）

| 维度 | 说明 | AgentOS 的位置 |
|---|---|---|
| 1. Instruction surface | 模型读到的指令层 | `AGENTS.md` + steering shim + skills/agent-discipline |
| 2. Context engineering | 模型看到什么、什么时候、多大密度 | inner-onion + map + handoff + cache 边界 |
| 3. Tool & permission | 模型能调什么、不能调什么 | sub-agents I/O contracts + tool 白/黑名单 |
| 4. Verification loop | 跑测试、对结果、给反馈 | verifier + visual-reviewer + lefthook |
| 5. Memory & recovery | 跨窗口接续、错误回滚 | sessions/handoff + git + ADR supersede 链 |
| 6. Orchestration | 主-子 agent 协作、何时触发什么 | workflows + 触发关系图 + sub-agents 三判据 |
| 7. Observability | 出问题能看出来 / 能复盘 | drift-check + prune + 文档头部审计字段 |

## Lean harness 哲学（与 Anthropic、Codex 团队对齐）

Cat Wu（Claude Code 产品负责人，2026.5）反复强调 **"lean harness"**：

> 不要给模型加它不需要的工具；不要给模型加它能自然完成的脚手架。

AgentOS 在这条上做的取舍：

- **没有自定义 LLM 调度框架**——交给 IDE
- **没有 RAG 系统**——长 context + cache + map 派生足够
- **没有 vector store**——`shared/`、`adr/`、`flow/` 是结构化检索的 ground truth
- **没有自定义 telemetry**——git history 是最稳的审计
- **没有 multi-agent 编排框架**——主 agent + 6 个 stateless sub-agent 三判据足以

模板的整体行数比 LangGraph、Autogen、CrewAI 这种"框架式 harness"少**两个数量级**——
但覆盖了 95%+ 的实际需求。这是有意为之。

## 与前沿的对照

| 要点 | 前沿做法（2026.5） | AgentOS 做法 |
|---|---|---|
| 行为护栏 | Karpathy + Chang CLAUDE.md / mnilax 12 条 | `skills/agent-discipline.md`，全文吸收 |
| Context 分层 | KV cache 边界（Claude Code 显式控制） | inner-onion + always-on / on-demand 区分；cache 表达，但跨 IDE 实际效果不可保证 |
| 单 vs 多 agent | Anthropic 三判据（context pollution / parallelizable / specialization） | sub-agents 仅 6 个，按动作类型分；主 agent 单线程写 |
| 验证 | PBT + verifier-in-the-loop（Anthropic Property-Based Testing 2026.1） | `verifier` sub-agent + `agent-discipline` 5.5"fail visibly" |
| 视觉反馈 | Browser use / Playwright MCP / vision model | `visual-reviewer` sub-agent + flow 交互态矩阵 |
| Long-horizon checkpoint | mnilax 5.4 + Cognition handoff | `write-handoff` workflow + `_template` |
| 决策 retention | Codex 用 AGENTS.md / Anthropic 用 ADR | ADR + flow 双层（前端层独立） |
| Tool budget | OpenAI Codex"approval / sandbox / token budget" | `agent-discipline` 5.1 + sub-agent budget 字段 |
| Surface conflicts | mnilax 5.2 / Karpathy "don't average" | `agent-discipline` 5.2 |
| 自动化 | Codex CLI 用 `AGENTS.md` 引导 + 自生成 scaffold | `wizard` workflow 引导 |

## 哪些前沿要点 AgentOS 没做（暂时）

诚实说：

1. **没有形式化 verifier 框架**（如 Microsoft Interwhen 的 LTL 实时校验）。
   AgentOS 停留在 PBT + 类型 + lint 这个层级。原因：跨语言通用，引入门槛低。
   高保障行业自行扩展。
2. **没有自动 prompt cache 测试**。能不能进 cache 由 IDE 决定，模板只能"建议"。
3. **没有 telemetry / cost tracking**。前沿团队会接 LangFuse / Helicone /
   Phoenix 做成本、延迟、失败模式分析。AgentOS 留给项目自接，不内置。
4. **没有 multi-agent consensus / debate**。这条是有意——属于反 Cognition
   "Don't Build Multi-Agents" 论点，不打算引入。
5. **没有自动 reward model**。RL post-training 是模型层的事，harness 不卷进去。

如果项目长大到需要这些，加 ADR 引入即可——它们不与 AgentOS 冲突。

## 一句话总结

> AgentOS 是 **lean harness**：把已经被验证有效的最小公约数做实，把没收敛的或
> 平台特定的东西留给项目按需扩展。模板能让你**比大多数项目做得好**，能不能
> 做到**最前沿**，看你愿意在它之上加多少。
