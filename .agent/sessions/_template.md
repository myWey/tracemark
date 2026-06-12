---
id: session-{ulid}
task: {task-id-或-spec-slug}
status: in-progress | paused | done | partial
created: {ISO 时间戳，仅审计用}
agent: {model + IDE}
preceded-by: {上一会话的 ulid，如有}
based-on-commit: {git sha}
context-used-pct-at-handoff: {百分比, e.g. 72}
related-adrs: []
related-flows: []
related-specs: []
---

# Handoff: {任务名}

> 由 `scribe` sub-agent 在以下时刻产出：上下文用到约 70%、用户暂停任务、
> 一个逻辑阶段结束。下一个 agent（可能不同 model / 窗口）读这个来续接。

## 1. 目标

- **用户意图（一句话）**：…
- **Spec**：`.kiro/specs/{name}`（如有）
- **当前阶段**：discovery | design | implementation | verification | done

## 2. 已做的决策（与原因）

> 整份文档**最有价值的一节**。没这一节，下一个 agent 会重新讨论已经定下的事。

- **D1**：选了 **X**，没选 **Y**。原因：{核心原因}。承担的代价：{放弃了什么}。
  引用：P{n}、ADR-{nnnn}、FLOW-{nnn}。
- **D2**：…

## 3. 当前状态

- ✅ 已完成：
  - {item}——commit {sha}
- 🔄 进行中：
  - {item}——已到第 N / M 步
- ⏸ 阻塞 / 等用户：
  - {item}——需要的答复：…

## 4. 触动的文件（带 *为什么*）

> 不是 `git diff`。重点是**为什么改**。

- `path/to/file.ts`——加了 X 以支持 Y
- `path/to/other.ts`——重构以满足不变式 Z

## 5. 待解问题

### 给用户

- Q1：…

### 给下一个 agent

- Q1：…

## 6. 不要重做（dead ends）

> 已探索且失败的方案。下一个 agent 不应再走。**这一节往往是新窗口最值钱的内容。**

- ❌ {方法}——失败原因：{原因}
- ❌ {方法}——按 P{n} 被否决

## 7. 快速续接 prompt（自包含）

> 复制到新窗口可直接续接。

```
续接任务 {task-id}（session {ulid}）。

按顺序读：
  1. .agent/skills/agent-discipline.md   （行为护栏，always-on）
  2. .agent/sessions/{ulid}/handoff.md   （本份 handoff）
  3. {相关 spec 路径，如 .kiro/specs/foo/}
  4. {相关 flow 路径，如 .agent/flows/002-bar.md}
  5. 第 4 节列出的关键文件（仅读相关部分，不读全文）

读完后输出：
"已续接到阶段 {X}。下一步：{Y}。继续？"

等用户确认后再动手。不要重做第 3 节"已完成"的事。
不要重试第 6 节"不要重做"的方案。
```

## 8. 快照

- **Git 工作树**：clean / dirty（分支 {branch-name}）
- **测试状态**：{通过 / N 失败——哪些}
- **Map 新鲜度**：{新鲜 / 失配——哪些 map 文件}
- **未提交改动**：{N 个文件}
- **环境依赖**：{是否需要重启 dev server / 重装依赖}

## 9. Quality Signals (optional)

> 可选但推荐。帮助追踪会话级别的决策质量和范式遵从度。
> 长期积累后可用于 drift-check 和 epoch-end audit。

- **decisions_made**: {N}
- **decisions_with_principle_citation**: {N} / {total}  — 引用了 P{n} 的比例
- **sub_agent_calls**: {N}
- **sub_agent_calls_visible**: {N}  — 有 🔧 标记的比例
- **failed_attempts**: {N}  — 记录在第 6 节的失败方案数
- **context_efficiency**: {used_pct}% at handoff
- **entities_updated**: yes / no  — 本次是否涉及领域实体变更

