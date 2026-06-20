---
description: Auto-dispatch a task to the right specialist subagent via the orchestrator.
---

# /autopilot

`/autopilot <task description>`

Let the orchestrator analyze the task and dispatch it to the appropriate specialist (explorer, planner, executor, reviewer, debugger, or security-auditor).

## Workflow

1. The orchestrator classifies the request.
2. It checks for active spec/memory context.
3. It delegates to the right specialist subagent.
4. The specialist's result is returned to you.

## When to Use

- You are unsure which specialist fits best.
- The task mixes exploration, planning, and implementation.
- You want a single entry point for ad-hoc requests.

## Rules

- `/autopilot` does not replace `/review` or `/ship`. Implementation outputs still need review before shipping.
- For critical or large changes, prefer explicit `/plan` or `/review` instead.

**Risk Notice**: This mode reduces human oversight. Only use for low-risk, batch, or well-understood tasks. For critical changes, use explicit /spec → /plan → execute → /review → /ship instead.
