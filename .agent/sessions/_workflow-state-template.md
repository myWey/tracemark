---
id: workflow-state-{ulid}
workflow: {workflow-id, e.g. bootstrap-project}
status: in-progress | paused | done
started-at: {ISO timestamp，仅审计}
based-on-commit: {git sha}
---

# Workflow State: {workflow}

> 任何多步 workflow 启动时由主 agent 创建此文件。每完成一步必须更新。
> resume-session 读这份。

## Step list (locked at start)

> 完整步骤列表。一旦确定**不再调整**——如果想换路径，结束当前 workflow，
> 启动新的。

- [ ] 1. {step name}
- [ ] 2. {step name}
- [ ] 3. ...

## Current

- **At step**: N / M
- **Step name**: ...
- **Sub-step / phase**: ...
- **Awaiting**: user-confirm | sub-agent-output | nothing

## Decisions made so far

> 跟 handoff 第 2 节一致格式。每完成一个 step 时 append 关键决策。

- D1: ...

## Files written so far

- {path}: {one-line intent}

## Sub-agent calls made

- {sub-agent-name} at step N: {one-line summary of result}

## Skipped / deferred

- {step}: reason

## Next checkpoint

What the user needs to confirm before step N+1.
