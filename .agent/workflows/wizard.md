---
id: workflow-wizard
status: active
---

# 工作流：wizard（自动引导落地范式）

## 目的

通过几轮**结构化对话**，自动把 AgentOS 范式完整落到一个项目里——无论是
0→1 全新项目还是已经在跑的项目。

> 这是 `bootstrap-project` 与 `retrofit-project` 的**入口包装**：先判断
> 项目类型，再分流到合适的工作流，把人类只需要回答的问题逐轮抛出，避免
> 一次塞太多。

## 何时跑

- 第一次接入 AgentOS（不管空 repo 还是既有项目）
- 用户希望"被引导"而不是自己读 workflow

## 调用方式

用户在 agent chat 里说：

```
跑 .agent/workflows/wizard.md
```

agent 接管后**逐轮**问问题，每一轮等用户答复后再问下一轮。

## 流程（多轮对话）

### Round 0 — 类型判定（1 轮）

agent 自动检测 + 1 个确认问题：

```
我看到工作区当前：
- {如果有 package.json/git history/已有代码}：这看起来是已在进行的项目
- {如果检测到 docs/specs/ 或 docs/rfcs/ 等}：且似乎已有旧范式产出
- {否则}：这看起来是空 repo 或刚开始

请确认或纠正：
[A] 0→1 全新项目
[B] 已在进行的项目（散乱或无范式）
[C] 已在进行的项目，**有旧范式 + 大量旧文档**（specs / RFCs / 旧 ADR）
[D] 实验/学习项目（不需要全套范式，给我精简版）
```

- A → Round 1A（bootstrap）
- B → Round 1B（retrofit-project）
- **C → Round 1C-legacy（retrofit-with-legacy）**
- D → 精简模式

### Round 1A — 0→1 项目（4–5 轮）

按 `bootstrap-project.md` 的内容，**每轮只问 1–2 个问题**，避免一次性塞十项：

- **Round 1A.1 定位与痛点**：定位一句话 + 2–5 个用户痛点场景
- **Round 1A.2 受众**：主 / 次 / 不服务的
- **Round 1A.3 哲学**：agent 起草 5–7 条原则（P1…Pn），用户审 + 调
- **Round 1A.4 栈与边界**：语言、框架、状态思路、API 风格、部署、关键约束
- **Round 1A.5 首个 vertical slice**：选一个最能压力测试假设的 feature

每轮结束 agent 写 / 改对应文件，让用户**看到产物**再进入下一轮。

### Round 1B — 已在进行项目（3–4 轮）

按 `retrofit-project.md` 三阶段，但拆成对话节奏：

- **Round 1B.1 摸清现状**：agent 调 explorer 跑现状探查（通常 30–90 秒），
  返回 retrofit 报告草稿，用户审
- **Round 1B.2 哲学对齐会议**：**这一轮无法跳过**。agent 抛 5–7 个问题
  让用户口头答复（不参考代码），从答复抽哲学
- **Round 1B.3 追认 ADR / flow**：agent 提议清单，用户勾选哪些要追认；
  agent 批量写
- **Round 1B.4 边界软强制**：agent 配 lint 规则（既有违规 warn，新代码
  error），跑一次看现状

### Round 1C-legacy — 有旧范式 + 大量旧文档（5 阶段，跨多轮）

按 `retrofit-with-legacy.md` 5 阶段：

- **Round 1C.0 Discovery**：调 explorer 盘点旧文档；产出 legacy-inventory
- **Round 1C.1 Classify**：跟用户对每类做决策（archived / active-bridged /
  active-orphan）；批量分类时仍要逐个确认 active 项
- **Round 1C.2 Bridge**：为 active-bridged 创建 bridge 文档；旧文档原位不动
- **Round 1C.3 Harden**：跑 sync-shims 让 legacy/_index 进 always-on
- **Round 1C.4 哲学对齐会议**：跟 1B.2 一样**不能跳过**——legacy 区填好
  之后还是需要团队对齐当前哲学
- **Round 1C.5 First feature**：用 start-feature 走一次，验证 bridge 是否
  真的工作（agent 是否正确把 legacy 当二等权威）

### Round 1D — 精简模式（1 轮）

只装最低限度：

- 复制 `AGENTS.md`、`.agent/skills/agent-discipline.md`、
  `.agent/core/dialog-rules.md`
- 跳过 ADR / flow / spec / map / hook
- 给用户一段提醒："如果项目长大，跑 `wizard` 重新评估"

### Round 2 — 验证落地（1 轮）

agent 跑一个**空对话验证**：

- 用一个简短的假任务（"列出本项目当前的设计原则"）测试 agent 是否真的读到
  了 philosophy / glossary / boundaries
- 报告：
  - ✅ Kiro / Claude Code 的 hook 是否注册成功
  - ✅ lefthook 是否安装
  - ✅ 跨 IDE shim 是否就位
  - ⚠️ 任何加载失败的项

如果 ⚠️ 项存在，agent 给修复建议。

验证通过后，向用户交付：
```
📖 最后一步：请阅读 `.agent/core/dialog-rules.md`
   它教你如何与 agent 说话才能让这套范式发挥最大作用。
   核心要点：说意图与判断，让 agent 管结构与执行。
```

### Round 3 — 第一次真任务（1 轮）

引导用户提出第一个真实任务（不是练手），跑 `start-feature` 或
`architecture-change` 走完整一次，**强化范式肌肉记忆**。

## 输出

- 阶段性产物（每轮结束都已写到磁盘）
- 一份"上手报告"`.agent/sessions/{ulid}/wizard-report.md`：
  - 完成了哪几轮
  - 用户的关键回答
  - 验证结果
  - 推荐下一步动作

## 完成判定

- 路径 A：bootstrap 完成判定满足，且 epoch-0 已 tag
- 路径 B：retrofit 阶段 0+1 完成，进入阶段 2 的常态
- 路径 C：精简文件就位，用户知道何时升级

## 反模式

- 一轮塞十个问题——人会跳着答，质量差。**严格逐轮**。
- 跳过 1B.2（哲学对齐会议）——retrofit 最容易失败的点
- wizard 帮人写哲学——必须由人决定，agent 只做整理
- 完成 wizard 后再没人跑 drift-check——3 个月后哲学开始漂移

## 跨 IDE 注意

- Kiro：触发命令在 chat 里直接说"跑 .agent/workflows/wizard.md"
- Claude Code：同上，或在 `.claude/commands/wizard.md` 加一个 alias
- Cursor：同上
- Antigravity / Trae：在主对话里手动粘 prompt
