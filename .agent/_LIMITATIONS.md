---
id: limitations
status: active
audience: human (decision makers, evaluators)
purpose: 诚实清单——这套范式做不到什么，何时不该用，单人项目的取舍
---

# 本范式的局限（诚实清单）

> 这份文件不是免责声明。是为了避免读到 `_meta.md` 后产生过高期望——**理解了局限再用，
> 才用得对**。

## 1. 文档代谢的承诺脆弱

`doc-syncer` 在 hook 里跑得自动，但前提是 IDE 支持那种 hook。Kiro 完整支持；
Cursor 没有原生 hook 系统；Trae、Antigravity 几乎没有。**跨 IDE 一致性靠的是
`lefthook.yml` 兜底**，但 git hook 时机是"提交前后"，不是"实时"。

实际意味着：在 Cursor / 没有 Kiro 的环境里，map 可能比预期更慢更新。**接受这一点，
别指望模板能消除它**。

## 1bis. 跨 IDE 引用语法不递归（实测踩坑）

> **重要**：模板早期版本依赖 `#[[file:...]]` (Kiro) 和 `@filename` (Cursor /
> Claude Code) 引用语法递归解析 SSOT。**实测（2026.5）发现 Kiro 不递归解析**——
> steering 文件内的 `#[[file:...]]` 只被当作纯文本，被引用的 `.agent/core/*`
> 等内容**不会进入主 prompt**。
>
> 修法：放弃引用机制，改为**编译时 SSOT**——`scripts/sync-shims.sh` 把 `.agent/`
> 内容**内联展开**到各 IDE 的 shim 文件，文件头标 `AUTO-GENERATED`。`lefthook`
> 校验源改了必须重编译。
>
> 经验教训：**任何"声明的加载机制"都必须用 `verify-loading.md` 实测**，不要
> 假设引用语法能跨 IDE 工作。换 IDE 时第一件事就是跑这个验证。

## 2. 视觉层最终瓶颈在人

`visual-reviewer` 输出的是"差异报告 + 分类"，最终 judgment 还是人。它降低了
review 的成本，但没消除。**没有 Storybook / 视觉回归基础设施的项目**，这套整体退化。

如果项目不投入这一层基础设施，前端"对齐"会回退到"agent 写完，人看截图"的老路子。

## 3. inner-onion 进 cache 的策略 IDE 支持不一

模板假设稳定层（philosophy、conventions、glossary）能进 prompt cache 常驻。
**Claude Code 显式控制 KV cache 边界**；Cursor / Kiro 是黑盒，行不行只能猜。
模板能描述意图，**保证不了实现**。

## 4. 角色 agent 模式没被完全替代

模板反对"前端 agent / 后端 agent"是因为他们之间会漂移。但承认：
- 多人并行开发、不同 PR 节奏时，**多窗口 agent + shared/ 契约**仍然实际。
- 模板默认单主 agent，没真正解决"多人各自跑各自 agent"的协作场景。

如果你的团队就是几个人各自开窗口，请把 `shared/` 当成**协议层**严格用，
比模板默认的更严格。

## 5. 对小团队是负担

ADR / flow / spec 三件套对：
- 2 人内、生命周期 < 3 个月的项目 → **过度**
- 一次性 demo / 周末项目 → **vibe code 更好**
- 3+ 人或长生命周期 → **模板真正发力**

**不要无条件套用**。判断你的项目是否适合，再决定是否启用全套。

## 6. agent 写的 ADR / flow 容易"看起来全面其实没用"

模板有结构，**没有质量校验**。常见失败：
- ADR 决策段落空泛（"我们决定用 X，因为它合适"）
- flow 步骤只是把页面顺序写一遍，没有交互态、没有边界条件
- 引用了原则但没真正运用判断

**人 review 这一步绕不开**。模板能让 agent 产出更结构化的文档，但产不出更深的判断。

## 6bis. LLM 倾向"压缩多步过程"——workflow 经常被跳步

实测发现：bootstrap-project 之类的多 stage workflow，agent 经常**跳过中间
stage**（比如 philosophy → ADR → spec，跳了 conventions/boundaries 调整、
glossary、entities）。这不是配置 bug，是 LLM 默认行为：**想往前推、不想停下来
核对**。

减害措施：
1. `agent-discipline.md` 6.9 强制每 stage 必停 + 用户确认
2. workflows 重写为"step list 锁定 + 强制输出格式"，让跳步可被发现
3. workflow-state 文件追踪当前进度，resume-session 读它就知道哪里中断
4. **对人**：在 `dialog-rules.md` 里告诉用户——agent 跳步时立刻打断，让它回到
   workflow-state 同步状态

但**不能根除**。即使有上述措施，复杂 workflow 仍可能在某 stage 被简化。
解法是：把 workflow 拆短、把 stage 数控制 ≤ 10、用 ⚠️ 让 deferred 显式化。

## 6ter. Sub-agent 在普通 chat 里"调"不出来——主 agent 自己干了

实测发现：workflow 里写"调 explorer sub-agent"，但 main agent 经常直接在主
context 里 grep / read，**从不输出 "🔧 Calling sub-agent: explorer" 的可见过程**。

为什么：
- Kiro 的 `invoke_sub_agent` 工具只在 spec workflow 里自动暴露，普通 chat 没有
- Cursor / Claude Code 的 sub-agent 机制更弱
- 即使工具可用，主 agent 倾向"我自己就能搜，省事"

减害措施：
1. `agent-discipline.md` 6.10 强制：要么 invoke_sub_agent，要么**可见地 role-play**
   （输出 `🔧 Calling sub-agent: {name}` + 输入 + 输出三段）
2. **对人**：sub-agent 没出现就让 agent 重做。这是 dialog-rules 里的关键提示

仍然减害不根除。Kiro 计划支持普通 chat 的 sub-agent invocation 后会改善。

## 7. 跨 IDE shim 是 best-effort

每家 IDE 的 reference 语法、加载行为有差异：
- Kiro 用 `#[[file:...]]`，**实测不递归解析**——必须用 `sync-shims.sh` 编译
- Cursor 用 `@`——**实测在 .mdc 文件内的 `@` 引用行为不一致**，同样用编译
- Claude Code 用 `@`——CLAUDE.md 单文件全内联即可
- Windsurf / Trae 行为不稳定——可能只是把内容当文本拼

**不要假设跨 IDE 完全等价**。换 IDE 后第一件事：跑 `verify-loading.md`，
让 agent 复述具体内容（不是文件路径），验证它确实读到了。

模板的解决方案：**编译时 SSOT**。源在 `.agent/`，shim 是 `sync-shims.sh` 编译
出来的派生物。文件头有 `AUTO-GENERATED` 标记，lefthook 在 `.agent/` 改了但 shim
没重编译时阻止 commit。

## 8. ADR 编号 / ULID / epoch 是逻辑时间，但仍依赖人维护

- ADR 编号靠人/agent 不写错（双开 PR 时容易撞号）
- ULID 靠生成器（如果 IDE 不提供，要 agent 自己造）
- epoch tag 靠人在合适时机打

**逻辑时间不会自己产生**。如果团队不内化这套约定，最终还是会回退到日期。

## 9. retrofit 不是无痛的

把 AgentOS 嵌入既有项目时，**追认 ADR** 听起来轻巧，实际上：
- 老人会说"这事当时不是这么决定的"
- 现实代码经常违背了设想中的"决策"
- 人对追认有抗拒（"我们以前就是没决策"）

retrofit workflow 提供流程，**但解决不了组织/政治阻力**。

## 10. 主 agent 单线程的代价

主 agent 单线程做所有 write 操作——这是规约 sub-agent 不漂移的代价，但也意味着：
- 大型重构时主 agent 的窗口压力陡增
- 一旦主 agent 决策错了，所有 sub-agent 跟着错（没有交叉校验）

**handoff 机制和主 agent 频繁的 sanity check 是减害手段，不是消除**。

## 何时不要用 AgentOS

- 一次性脚本 / 实验
- 学习项目（学的就是从乱中找秩序）
- 团队还在探索 PMF，产品方向每周翻
- 没有任何 CI / 测试基础设施且不打算引入

## 何时 AgentOS 真正发力

- 3+ 人协作
- 生命周期 > 6 个月
- 有真实用户、不能频繁回归
- 团队认可"决策应该有家"且愿意维护
- 至少一种 IDE（Kiro / Claude Code）做实时 hook，git hook 兜底

## 单人项目（团队规模 = 1）的取舍

> 模板默认按 3+ 人 / 长生命周期设计。**单人模式**仍然有用，但需要松弛某些
> 规则；以下是建议。

**仍然保留**（单人项目的最大收益区）：

- `agent-discipline`——单人比团队更需要护栏，因为没人 review
- `philosophy.md`——给自己定方向，自己今天给自己明天的承诺
- ADR / flow——单人项目里更可能"昨天为什么这么做忘了"
- `handoff.md`——单人项目里 **handoff 是给未来的自己看**，价值最高
- `regenerate-map`——给未来的自己看一眼项目长啥样

**可以松弛**：

- 哲学对齐会议（retrofit Round 1B.2）——跳过，跟自己对齐即可
- ADR / flow 的颗粒可以粗一些（不需要 ratification 流程）
- prune 阈值放宽（单人不存在撞号 / 跨 PR 冲突问题）
- multi-IDE shim 只装一个（你用什么装什么）
- `core/dialog-rules.md` 知道存在即可，不强制每次读

**单人项目的危险**（注意）：

- 容易把 chat 当 ADR——后果是几个月后忘了为什么。**仍然要写 ADR**。
- 容易跳过 verifier sub-agent 自己看——疲劳时眼睛会骗人。**仍然要让 verifier 跑**。
- 容易认为"我自己知道"而不写 glossary——三个月后命名飘忽。**仍然要写关键术语**。

> 一句话：单人项目里，**ADR/flow/handoff/glossary 是给"未来失忆的自己"的礼物**，
> 不是给"现在记得的自己"的负担。

## 总结

| 局限 | 可减害手段 | 是否注定 |
|---|---|---|
| 1 文档代谢承诺脆弱 | `lefthook.yml` 兜底；用 Kiro/Claude Code 时获满福利 | 部分注定（IDE 差异） |
| 2 视觉层瓶颈 | 投入 Storybook + 视觉回归基础设施 | 是（人是最终判断） |
| 3 cache 策略不一 | Claude Code 显式控制；其它环境监控质量 | 部分注定 |
| 4 角色 agent 漂移 | 多窗口时严格用 `shared/` 协议；新增 conflict-detector | 部分可解 |
| 5 小团队负担 | wizard 提供精简模式（路径 C） | 不需要克服 |
| 6 ADR/flow 看起来全面其实没用 | `agent-discipline` skill + 人 review 不可省 | 部分可解 |
| 7 跨 IDE shim 不等价 | wizard Round 2 验证；接受 best-effort | 是 |
| 8 编号/ULID 依赖人维护 | lefthook 校验 ID 唯一；agent 自动补 | 部分可解 |
| 9 retrofit 政治阻力 | `wizard` Round 1B 哲学对齐会议 | 组织问题，工具解不了 |
| 10 主 agent 单线程代价 | handoff + sub-agent 减害；将来可加交叉校验 | 部分可解 |

新增的减害措施已落到模板：

- `.agent/skills/agent-discipline.md`——always-on，治第 6 条
- `.agent/core/dialog-rules.md`——给人，治"用户提问质量"上游问题
- `.agent/workflows/prune.md`——治文档膨胀，间接治 6 与 8
- `.agent/workflows/wizard.md`——降低初次接入摩擦，部分治第 5、9 条
- `lefthook.yml`——治 1、8

## Antigravity 特有的局限

> 以下仅在 Antigravity IDE 环境中成立。

### A1. 终端沙箱对 dot-prefixed 目录的限制

Antigravity 的终端沙箱**阻止 shell 命令直接读写以 `.` 开头的目录**（如 `.agent/`、
`.antigravity/`）。`cp`、`mv`、`rm`、`cat` 等命令都会被拦截。

**影响**：`sync-shims.sh` 无法直接运行。必须用 Python 原生文件 IO（`sync-shims.py`）
或 agent 的 `write_to_file` / `view_file` 工具绕过。

### A2. 无原生 Hook 系统

Antigravity 不支持类似 Kiro 的 `.kiro/hooks/` 目录或 IDE 级别的事件监听。5 个
Kiro Hook 的替代方案是「Antigravity 软 Hook 协议」——**依赖 agent 自觉**在相应
时机执行检查（任务前读 philosophy、ADR 后调 impact-analyzer、任务后跑 verify）。

**影响**：如果 agent 不遵守软 Hook，没有硬件兜底。`agent-discipline.md` §6.11
的 proactive self-check 是唯一的防线。`lefthook` 在 commit 时兜底，但覆盖不了
实时场景。

### A3. AGENTS.md 行数敏感

Antigravity 通过 `user_rules` 注入 `AGENTS.md` 全文。**行数过长（>800）时
可能被截断或被 IDE 内部 context 管理压缩**。当前甜点区 600–800 行。

**影响**：编译产物膨胀会导致尾部内容（boundaries、conventions）丢失。每次增改
always-on 内容后需验证行数。

### A4. 不支持 invoke_subagent 工具级调用

Antigravity 原生子代理（`research` / `browser` / `self`）不等于 AgentOS 的
9 个自定义 sub-agent。原生子代理有自己的能力边界：

- `research`：适合 explorer / researcher 类任务（代码搜索 + 文档获取）
- `browser`：适合 visual-reviewer（需 `/browser` 激活）
- `self`：适合 fixer / scribe / doc-syncer（克隆体并行）

其余（verifier / impact-analyzer / executor）仍需 **role-play 模式**，遵从
率和质量受限于 `_LIMITATIONS.md` 第 6 条描述的基线。

## 总结

> 这是**比 vibe coding 更适合长生命周期项目**的范式，**不是终极答案**。它降低
> 漂移和熵增的速率，但没把它们降到零；它把视觉层的瓶颈从"代码 review"挪到
> "视觉 review"，但仍是人来兜底。

读完局限再决定要不要用。
