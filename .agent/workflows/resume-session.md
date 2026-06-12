---
id: workflow-resume-session
status: active
---

# 工作流：resume-session

## 目的

让一个新 agent（可能新窗口或不同 model）冷启动接续既有任务、忠实地继续。
**只读必要的**——不读全 repo。

## 何时跑

- 新窗口，用户说"续上任务 X" 或粘贴一段 quick-resume prompt
- 同一任务里上下文重置

## 输入

- session ULID 或任务 slug
- 可选：用户认为相关的文件清单

## 步骤

### 1. 定位 handoff

- 用户给了 ULID：读 `.agent/sessions/{ulid}/handoff.md`
- 没给：列 `.agent/sessions/`，挑该任务最近 `status: in-progress` 的——确认

没找到 handoff：让用户选"重新跑 `start-feature`"或"提供新 handoff 的素材"。

### 2. 按顺序读

> [!IMPORTANT]
> 如果当前是 Antigravity IDE 运行环境且开启了 Planning 模式，主 agent **必须**在执行文件读取前，自动识别并向用户申请运行恢复命令：
> `bash scripts/antigravity-sync.sh restore`
> 将历史会话的规划文件同步恢复到当前局部目录，然后再继续后续的读取和任务执行。

1. `.agent/core/philosophy.md`
2. `.agent/core/conventions.md`
3. `.agent/core/boundaries.md`
4. handoff 本身
5. handoff 引用的 spec（若在 Antigravity 下，指本地被恢复的 `implementation_plan.md`）
6. handoff 引用的 flow（如有）
7. handoff 第 4 节列出的"触动文件"——只这些、只相关部分
8. handoff 引用的 map 文件（如有）

### 3. Sanity check

- `git status` + `git log -1` 确认工作树与 handoff 的 `based-on-commit` 一致
- 如果偏离：先报告给用户，再决定怎么办
- 检查 map 失配：有任何 source-hash 不对，跑 `regenerate-map`

### 4. 确认理解

按这个固定句式告诉用户：

```
已续接任务 {task-id}（session {ulid}）。
当前阶段：{X}
已完成：{N} 项，最近 commit {sha}
等你回答的问题：{清单，如有}
下一步：{Y}
继续？
```

等"继续"或调整再动手。

### 5. 续接

从 `upcoming_step` 或用户指令开始。**不重做**已完成项，除非被要求。

## 输出

- 已验证的状态
- 简洁的 "我们到哪儿了" 报告
- 经确认后续接

## 完成判定

用户接受"继续？"，你直接动手而不再问 handoff 已经回答过的问题。

## 反模式

- 续接前重读全 codebase。handoff **就是**读单
- 重新讨论 handoff 第 2 节里已定的决策
- 重试 handoff 第 6 节"不要重做"中已失败的方案
