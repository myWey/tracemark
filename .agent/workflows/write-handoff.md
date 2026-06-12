---
id: workflow-write-handoff
status: active
---

# 工作流：write-handoff

> 上下文将满（70%）时**主动**收尾，让新窗口能无损接续。
> 不是要等到 100% IDE 自动 compact——那是 lossy 的、不可控。

## 目的

把当前任务的**决策、状态、踩过的坑、下一步**结构化落到磁盘，让另一个窗口 /
另一个 agent 能从这份 handoff 接续，**不丢决策、不重走死路**。

## 何时跑

- **上下文用到 70%**（主动）
- **上下文用到 80%**（红线，必须立刻停手做这个）
- 用户暂停一个多步任务
- 一个逻辑阶段结束（discovery → design、design → impl、…）
- 用户显式要求"存档"

## 步骤

### Stage 0: 决定 ULID

如果续接既有 session：用 `.agent/sessions/{ulid}/` 现有 ULID。
否则：生成新 ULID（IDE 不提供生成器时用时间戳 + 随机后缀）。

输出：`session_ulid: {ulid}` → 等用户 `y`

### Stage 1: 调 scribe sub-agent（必须可见）

**这是必须 role-play 的 sub-agent 调用**——不允许主 agent 自己写 handoff
（违反 6.10）。

```
🔧 Calling sub-agent: scribe
📥 Input:
    task_id: {当前 spec slug 或任务名}
    session_ulid: {上一步定的 ULID 或 "new"}
    trigger: context-fill | user-pause | phase-end | explicit
    include:
      decisions: true
      files_touched: true
      open_questions: true
      failed_attempts: true
    extra_context:
      current_phase: discovery|design|impl|verify|done
      upcoming_step: <一句话>
      context_used_pct: <百分比>
```

scribe 按 `_template.md` 结构产出 `.agent/sessions/{ulid}/handoff.md`。

> [!NOTE]
> 如果当前会话运行在 Antigravity 中，在 scribe 产出 handoff.md 之后，主 agent **必须**执行以下备份命令以将规划文件备份至仓库：
> `bash scripts/antigravity-sync.sh backup`

```
📤 Sub-agent scribe output:
    written_to: .agent/sessions/{ulid}/handoff.md
    session_ulid: {ulid}
    quick_resume_prompt: |
        续接任务 {task-id}（session {ulid}）。
        
        【Antigravity 恢复说明】若您当前使用的是 Antigravity 且开启了 Planning 模式，请批准直接执行以下一键恢复命令以自动匹配并还原规划状态：
        bash scripts/antigravity-sync.sh restore
```
        
        按顺序读：
          1. .agent/skills/agent-discipline.md
          2. .agent/sessions/{ulid}/handoff.md
          3. {相关 spec 与 flow}
          4. {第 4 节列出的关键文件}
        然后说："已续接到阶段 X。下一步：Y。继续？"
    warnings: [...]
```

### Stage 2: 用户 review handoff（不可跳过）

主 agent 立刻读回 handoff，给用户看以下三段（截图或贴文本均可）：

- **第 2 节决策**：是否齐全？空泛的决策让用户补
- **第 6 节 don't-redo**：踩过的坑都列了吗？
- **第 7 节快速续接 prompt**：是否自包含？

```
✅ Handoff 已写到 {path}
📋 关键内容：
  - 决策数：{N}
  - 文件改动数：{N}
  - 失败方案数：{N}（这是新窗口最值钱的内容）
  - 待用户答的问题：{列表，如有}

🔍 请在新窗口前看一眼 handoff 第 2、6、7 节：
{quick links 或粘贴片段}

Continue? (y / 让我补 / 重写)
```

### Stage 3: 切换指引

确认无误后输出：

```
🪟 新窗口操作：

1. 开新对话窗口（不要 /clear，不要继承当前会话）
2. 复制粘贴下面这段 prompt：

{quick_resume_prompt}

3. 等新 agent 说"已续接到阶段 X，下一步 Y。继续？"——确认后继续工作

⏸ 当前会话保留可读，但不要在这里继续干活——上下文已用尽。
```

### Stage 4: 关闭当前 session

主 agent 在当前会话**只回答"是否还有遗漏"类问题**，不接新工作。如果用户
误在当前窗口提新任务：

```
⚠️ 当前会话已 handoff（{path}）。新工作请到新窗口续接。
   要在这里继续？需要先解释——上下文剩余 {N}%，可能不足以完成。
```

## 输出

- `.agent/sessions/{ulid}/handoff.md`（创建或更新）
- 新窗口的 quick-resume prompt（贴给用户）

## 完成判定

- handoff.md 存在且填了 8 节（不能有空 section）
- 用户**已经看过**第 2、6、7 节
- 新窗口能仅凭 handoff（不读历史对话）接续

## 反模式

- **等到 100% 才 handoff**——IDE 强制 compact 比 handoff 损失大得多
- **不调 scribe 自己写**——违反 6.10，且容易跳过模板段（尤其第 6 段失败方案）
- **handoff 只列文件改动不列决策**——下一个 agent 仍会重新讨论
- **新窗口不贴 quick-resume prompt 直接说 continue**——agent 没有上下文，
  会幻觉
- **同一窗口"再撑一下"**——80% 后回答质量陡降，且 handoff 写到一半被截断

## 上下文使用阈值（决定主动 vs 被动）

| 用量 | 状态 | 动作 |
|---|---|---|
| < 60% | 正常 | 继续工作 |
| 60–70% | 预警 | 评估当前 task 能否在 80% 前完成；不能就准备 handoff |
| 70% | **主动 handoff** | 跑本 workflow |
| 80% | **红线** | 立刻停手跑本 workflow，标 `urgent` |
| > 80% | 迟了 | 仍要跑，标 `partial`；新窗口 resume 时先核对状态 |

agent 看不到自己上下文百分比时，由用户提示。一般规则：**用户提"存档"或类似
词时无条件跑这个 workflow**。
