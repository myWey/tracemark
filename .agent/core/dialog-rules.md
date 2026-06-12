---
id: dialog-rules
status: active
audience: human (the user talking to agent)
purpose: 教用户如何与 agent 说话才能让范式发挥作用——给人看的，agent 上下文不需要
last-confirmed: null
---

# 人机对话规则（Dialog Rules）

> 这份是给**人**看的，不是给 agent 的。讲清楚跟 agent 工作时，怎么说话能让
> 这套范式发挥作用。
>
> 概括：**你输入的越少结构、越多意图，agent 帮你做的结构化越好；反过来，你越
> 想插手细节，越容易绕过范式**。

## 核心原则

### 1. 说意图，不说做法

**好**：

> 用户填写邮箱后，希望第一时间得到反馈，比如"这个邮箱看起来不对"。

**不好**：

> 在 onChange 里加一个 debounce 300ms 的 zod 校验，错误的时候在下方红字显示。

后者强迫 agent 跳过设计层。意图只占一行，agent 会反向确认细节，**让 agent
回译成结构**比你直接给方案，跟范式对齐得更好。

### 2. 拒绝混杂的反馈，但允许混杂的吐槽

review 时人类的反馈天然混杂——视觉、行为、契约、架构都会有。**没关系**，
全部说出来即可。agent 会做 triage 分到 flow / ADR / spec / token 各处。

唯一的边界：**不要提出"顺便重构 X"**。这会污染当前 PR。让 agent 把它列为
单独后续。

### 3. 需要决策时，给原则；不要给"或"

**好**：

> P3 优先，所以默认走慢但可靠的路径。

**不好**：

> 用方案 A 或者方案 B 都可以，你看着办。

LLM 在"看着办"时倾向选最显眼的那个，不一定是最对的。给原则比给开放选择
要稳。

### 4. 接受 agent 的"反向确认"

agent 会在做之前用自己的话复述意图。**不要嫌烦**——那一段对话是你避免做废
的最便宜手段。如果它复述对了，说"对，继续"。如果不对，立刻改。

### 5. 用结构化字眼指认位置

会大幅提升 agent 的定位精度：

- "FLOW-002 第 3 步"
- "P3 跟 P5 在这里冲突，你怎么权衡的？"
- "ADR-0007 是不是已经被这次改动 supersede 了？"
- "shared/schemas/user 里的 email 字段……"

而不是"那个登录页那个输入框那个东西"。这套范式所有的稳定 ID 都是为这种指认
设计的。

### 6. 对生成物只看高层

- 视觉层：看 Storybook + 视觉差异报告
- 行为层：看测试列表 + 失败样本
- 契约层：看 schema diff + impact-analyzer 输出
- 不要逐行审 agent 生成的代码——这是范式的设计，不是省事

逐行审会让你回退到人类时间尺度，agent 一天能做的事被压缩成你能审的量。

### 7. 想暂停时说"存档"

不要让上下文用满才被动。任何时候你想停下来：

> 存档吧，下次接着做。

agent 会跑 `write-handoff`，给你一段 quick-resume prompt。下次新窗口粘贴
即可。

### 8. 想推翻时说"supersede"

不要直接修旧 ADR / flow——那会丢历史。说：

> ADR-0007 我们今天意识到不对了，要 supersede 它，新方向是 X。

agent 会建新 ADR，标 supersedes，把旧的状态改 superseded。审计链就保住了。

### 9. 发现 agent 跳步时立刻打断（关键）

**LLM 倾向把多步 workflow 压成一两步。** 你必须主动打断，否则 bootstrap 的
glossary / conventions / entities 就会被默默跳过。

**早期信号**：

- agent 一次输出里出现两个 ✅（应该一个）
- agent 没问"continue?"就开始下一 stage
- 该调用 sub-agent 的地方没有 `🔧 Calling sub-agent: {name}` 标记
- workflow-state 文件没创建 / 没更新

**这时立刻说**：

```
停。回到 workflow-state，告诉我现在在 step 几、漏掉哪些 step、为什么漏。
```

agent 会读 workflow-state，发现自己跳了，就回到正确位置。**不要让步**——
"先让它把 spec 写完再回头补" 实测有 80% 的概率永远回不来。

### 10. 没看见 sub-agent 输出就让它重做

如果 workflow 说要调 explorer / verifier / impact-analyzer 等 sub-agent，
但你**没看到** `🔧 Calling sub-agent: {name}` + 输入输出三段——意味着 agent
偷偷在主 context 干了。这违反了 `agent-discipline.md` 6.10。

**这时说**：

```
你跳过了 {sub-agent} 的 role-play。回到 workflow，按 6.10 规则可见地走一遍。
```

### 11. 主动提醒 agent 调 sub-agent（关键时刻）

实测：即使有 6.10 规则，agent 也经常在该调 sub-agent 时**自己干**。这是
LLM "省事"倾向。**有几个时刻必须由你提醒**：

| 你看到 / 想做 | 立刻说 |
|---|---|
| agent 要跑 `npm test` / `cargo test` / 任何长测试 | "用 executor sub-agent 跑，不要把日志倒进主 context" |
| agent 要 `npm run build` / `pnpm build` | 同上 |
| agent 要 grep > 10 个文件 / scan 大目录 | "用 explorer sub-agent" |
| agent 要"读一下 X 库怎么用" | "用 researcher sub-agent" |
| agent 要"改 30 个文件的 import" / 批量 rename | "用 fixer sub-agent" |
| agent 改完 UI 要看效果 | "用 visual-reviewer sub-agent" |
| 你要建新 ADR | "建之前先用 impact-analyzer sub-agent 跑一下" |
| 上下文 > 60% 且任务还没完 | "调 scribe 写 handoff，准备开新窗口" |

经验法则：**任何让你觉得"啊这要打很多字 / 跑很久 / 输出很多"的事**——就是
sub-agent 信号。

### 12. 上下文将满时怎么收尾（不要拖到 100%）

**Claude Code / Kiro 在上下文用满时会强制截断**，丢失的部分不可控。所以
**70%** 是动手时机，**80%** 是最后红线。

进度示意（典型 agent IDE 都会显示百分比）：

| 上下文用量 | 你的动作　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　|
| ------------| -----------------------------------------------------------------------------------------------|
| < 60%　　　| 正常工作　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　|
| 60–70%　　 | **预警**：当前 task 是否能在 80% 前结束？不能就准备 handoff　　　　　　　　　　　　　　　　　 |
| 70%　　　　| "调 scribe sub-agent 写 handoff.md，包含决策和 don't-redo 段。然后告诉我 quick-resume prompt" |
| 70–80%　　 | agent 写 handoff，你审一眼第 2、6、7 段（决策、不要重做、续接 prompt）　　　　　　　　　　　　|
| 80%　　　　| **停止任何新工作**。复制 handoff 第 7 段的 prompt → 开新窗口粘贴　　　　　　　　　　　　　　　|
| > 80%　　　| 已迟。当前回答可能不完整。仍要 handoff，标 `partial`，新窗口 resume 时让它先核对状态　　　　　|

**不要做的事**：

- 不要"再撑一下"——超过 80% 之后 agent 的回答质量陡降
- 不要在 100% 时让 IDE 自动 compact——那是 lossy 压缩、不可控、丢决策
- 不要在新窗口"继续上次"而不读 handoff——只贴一句"continue" agent 会瞎猜

## 反模式（人类侧常见错误）

| 反模式 | 后果 | 替代说法 |
|---|---|---|
| "随便弄个登录页" | agent 默认套用最简模式，绕过 philosophy | "登录是 FLOW-001，参考 P3 决定文案克制度" |
| "这里再 polish 一下" | 模糊到无法验证 | "FLOW-002 第 4 步的 success 文案不够克制（违反 P3）" |
| "全部重写" | 一次大爆炸 PR | "供给一个 migration ADR，列受影响清单先" |
| "不用搞那么麻烦的 spec" | 范式被绕过 | "这是个 epoch-0 探索，跑 vibe；稳定后再 retrofit 进 spec" |
| "你看着办" | LLM 选最显眼方案 | "P{n} 优先，默认 X" |
| 直接改 ADR 内容 | 历史丢了 | 用 supersede |
| 直接改 map 文件 | 跟生成器分叉 | 改源、跑 regenerate |

## 沟通节奏（不写时间，只写阶段）

| 阶段 | 你说什么 | agent 做什么 |
|---|---|---|
| 启动 | 给意图 + 几个素材 | 反向确认 + 起草 |
| 设计 | 看 spec / flow 草稿 | 调整、再确认 |
| 实施 | 不打扰 | 主 agent 写代码 + sub-agent 验证 |
| review | 看视觉/行为输出，给混杂反馈 | triage 到对应层 |
| 收尾 | 确认 done 或下一步 | 落 ADR / flow / map / handoff |

## 语言

- 用中文跟 agent 说话即可。
- 引用稳定 ID 时（`ADR-0007`、`FLOW-002`、`P3`、token 名）保留原样不翻译。
- 不需要刻意写得正式或完整——agent 会复述确认。

## 一句话总结

> **你管意图与判断，agent 管结构与执行**。如果发现自己在管结构（写 spec
> 字段、组织目录、命名变量），停下——那是 agent 的活，把决定权用对地方。
