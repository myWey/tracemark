---
name: subagent-delegation
description: Use when calling a subagent via the Task tool. Defines the Task Brief protocol — what context to pass, how to scope, and how to ensure fidelity. Prevents context waste from vague delegations and fidelity loss from missing context.
---

## When to Invoke
- Any time you are about to call a subagent via the Task tool
- When unsure what context a subagent needs

## When NOT to Invoke
- Simple direct tool calls (Read, Grep, Glob) — no delegation needed
- When the task is small enough to inline

## The Task Brief Protocol

Every subagent call must include a structured brief in the `query` parameter:

### Required Fields

| Field | What | Why |
|-------|------|-----|
| **Task** | One-sentence description of what the subagent should do | Prevents scope ambiguity |
| **Context** | Relevant file paths (NOT contents), active spec change-id, project asset paths | Subagent runs in isolated context — it doesn't know what you know |
| **Constraints** | Scope limits, what NOT to touch, files to avoid | Prevents boundary intrusion |
| **Success criteria** | How to verify the task is done | Enables autonomous looping |
| **Report** | Expected output format (summary, verdict, file list) | Ensures useful return value |

### Template

```
Task: [one sentence]

Context:
- Active spec: .trae/specs/<change-id>/ (if any)
- Relevant files: [paths, not contents]
- Project assets: docs/PHILOSOPHY.md, docs/TERMS.md, docs/ARCHITECTURE.md (read if relevant)

Constraints:
- Only modify: [specific files]
- Do NOT touch: [protected files]
- Stay within: [scope boundary]

Success criteria:
- [verifiable condition 1]
- [verifiable condition 2]

Report: [expected format — e.g., "Return a summary of findings, not full file contents"]
```

## Subagent Context Matrix

Different subagent types need different context:

| Subagent | Must-have context | Nice-to-have |
|----------|------------------|-------------|
| explorer | File/function/module to find, what to understand | Project asset paths for conventions |
| planner | Task description, relevant files, constraints | Active spec change-id, project PHILOSOPHY |
| executor | Approved plan path, file list, success criteria | Active spec change-id for checklist |
| reviewer | Files changed, spec change-id (for checklist.md), review scope | Project ARCHITECTURE for boundary check |
| debugger | Error description, reproduction steps, relevant files | Recent git log, related spec |
| tester | Code to test, test framework, coverage target | Project TERMS for naming conventions |
| security-auditor | Code to audit, threat model, sensitive data locations | OWASP context, project ARCHITECTURE |

## Failure Modes

### Vague Delegation (most common)
**Bad**: "Explore the auth module and tell me how it works"
**Good**: "Task: Explore how authentication works in src/auth/. Context: entry point is src/auth/index.ts. Report: Return a summary of the auth flow, key functions, and dependencies. Do NOT read test files."

**Why bad**: Subagent doesn't know where to start, reads everything, wastes context.

### Missing change-id
**Bad**: "Review the recent changes"
**Good**: "Task: Review changes in feature/user-profile. Context: Active spec change-id is 'user-profile-v2', checklist at .trae/specs/user-profile-v2/checklist.md. Files changed: src/components/Profile.tsx, src/api/user.ts."

**Why bad**: Subagent can't find the checklist to verify against.

### Over-passing context
**Bad**: Pasting 500 lines of file contents into the query
**Good**: "Context: src/auth/index.ts (lines 45-80 contain the token validation logic)"

**Why bad**: Defeats the purpose of context isolation. Pass paths, not contents.

### No success criteria
**Bad**: "Fix the bug in the login flow"
**Good**: "Task: Fix the login redirect bug. Success criteria: 1) Test `should redirect to dashboard after login` passes. 2) No console errors in the auth flow."

**Why bad**: Subagent doesn't know when to stop. Might over-fix or under-fix.

## Anti-Patterns

- Delegating to a subagent what you could do with a single Read/Grep
- Passing file contents instead of file paths
- Omitting the active spec change-id when one exists
- Not specifying the report format (subagent returns 500 lines when you needed 5)
- Delegating multi-phase work to a single subagent call (break it into sequential calls with checkpoints)

## Rule of Thumb

If you can't write a clear Task Brief in under 10 lines, you don't understand the task well enough to delegate it. Ask the human for clarification first.
