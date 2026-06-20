---
name: context-engineering
description: Context window management methodology. Use when the conversation is getting long, when exploring unfamiliar code, or when planning multi-phase work. Preserves the finite context window by delegating exploration to subagents, using progressive disclosure, and resetting context at boundaries. Prevents context drift where hour 3 contradicts hour 1.
---

# Context Engineering

## When to Invoke

- Before exploring an unfamiliar module (delegate to a subagent).
- When the conversation exceeds ~70% of the context window.
- When switching to a different feature or module.
- When the agent starts contradicting earlier statements (context drift).
- Before any task that will read > 5 files.

## When NOT to Invoke

- Quick lookups (1-3 known files — just read them).
- Tasks fully contained in the current context.
- When the user explicitly wants inline exploration.

## Core Principle

The context window is a finite and precious resource. Spend it on signal,
not noise. Every file read, every search result, every log line consumes
tokens that are then unavailable for reasoning.

## Progressive Disclosure Layers

```
Always Loaded (loaded every turn):
├── Rules (.trae/rules/*.md)     ← keep lean. every line costs tokens.
│   ├── 00-core-principles.md    ← alwaysApply: true
│   ├── 01-conventions-and-safety.md ← alwaysApply: true
│   ├── 02-python-conventions.md ← globs: **/*.py
│   └── 03-ts-conventions.md     ← globs: **/*.{ts,tsx,js,jsx}
└── AGENTS.md                     ← project entry point.

On-Demand (loaded only when relevant):
├── Skills (.trae/skills/)        ← at startup only name+description load.
│                                    full body loads when a task matches.
├── Commands (.trae/commands/)    ← loaded only when triggered by /name.
└── Memory (.trae/memory/)        ← guidance from prior runs, loaded on demand.

Isolated (own independent context window):
└── Subagents                     ← run in a separate context.
                                     only return summaries to the main thread.
                                     what they read does not pollute the main thread.
```

## SessionStart Hook Auto-Injects Project State

To avoid manually rebuilding project awareness at every new session, Trae
auto-injects a project state summary at session start via the
**SessionStart hook**. This is the first line of defense in context
engineering: let the agent start with the right context, rather than
feeling its way from zero.

### How the Hook Works

```
[Session start]
    │
    ▼
SessionStart hook fires
    │
    ├── reads persisted guidance under .trae/memory/
    ├── reads the current spec/plan under .trae/specs/<active-change-id>/
    ├── scans git state (current branch, uncommitted changes, recent commits)
    └── generates a project state summary
    │
    ▼
[summary injected into the main context]
    │
    ▼
[Agent starts working with project state already in hand]
```

### Injected Content

The SessionStart hook injects the following structured summary (kept lean,
typically < 50 lines):

```markdown
# Project State (auto-injected)

## Active Change
- change-id: <currently active change-id>
- branch: <current git branch>
- spec: .trae/specs/<change-id>/spec.md (approved / draft)

## Recent Commits
- <hash> <message>
- <hash> <message>

## Uncommitted Changes
- <file list and change summary>

## Memory Highlights
- <key conventions or decisions from .trae/memory/>

## Open Checkpoints
- <list of unfinished checkpoints>
```

### Hook Design Constraints

- **Read-only**: the hook only reads state; it does not modify any files.
- **Lean**: injected content must be < 50 lines to avoid consuming too
  much of the context window.
- **Idempotent**: repeated triggers produce the same result with no side
  effects.
- **Fail-safe**: if the hook fails, the session still starts normally,
  only the state summary is missing.

### Cooperation with Progressive Disclosure

The SessionStart hook injects a **high-level summary**, not full files.
When the agent needs detail, it loads on demand following progressive
disclosure:

| Need | Loading Method |
|------|----------------|
| Project state overview | Auto-injected by SessionStart hook |
| Specific requirements spec | On-demand Read `.trae/specs/<id>/spec.md` |
| Task list | On-demand Read `.trae/specs/<id>/tasks.md` |
| Acceptance checklist | On-demand Read `.trae/specs/<id>/checklist.md` |
| Prior experience | On-demand Grep `.trae/memory/` |
| Capability methods | Load the matching Skill body when a task matches |

## Subagent Delegation Rules

**Delegate to a subagent when the task will:**

1. Read > 5 files that will not be referenced again in the main thread.
2. Produce > 100 lines of intermediate output (logs, search results).
3. Explore an unfamiliar module, with the goal of understanding rather
   than editing.
4. Run a long command whose output is only needed as a pass/fail signal.

**Do NOT delegate when:**

- The task requires frequent back-and-forth with the human.
- Multiple phases share a lot of context (plan → implement → test).
- The result is small enough to inline without clutter.
- The human explicitly wants to see the full exploration process.

## Context Reset Triggers

Open a new conversation when any of the following occurs:

| Trigger | Reason |
|---------|--------|
| Switching to a different feature | Old context is irrelevant and distracting |
| After shipping a checkpoint | Work is done; start fresh for the next task |
| Agent contradicts itself | Context drift has occurred; reset fixes it |
| Conversation > 70% of window | Reasoning space is about to run out |
| After a long debug session | Debug context is noise for the next task |

## File Reading Discipline

- **Locate before reading**: use `Grep`/`Glob` to find, then `Read` only
  the relevant lines (using `offset` and `limit`).
- **Semantic search for "how"**: use `SearchCodebase` to ask "how does
  authentication work?".
- **Exact search for "where"**: use `Grep` to ask "where is `AuthService`
  defined?".
- **Never read an entire large file** when you only need one function.
- **Avoid re-reading** files already in context — just scroll up.

## What Should NOT Go Into Context

- Reading an entire file when only one function is needed.
- Pasting an entire error log when one line locates the problem.
- Documentation that can be fetched on demand via `WebSearch`/`WebFetch`.
- Code from other projects as "reference" — describe the pattern instead.
- Hypothetical scenarios or "what if" explorations.

## Memory Hygiene

The `.trae/memory/` folder stores guidance from prior runs.

**Store in memory:**
- Project conventions discovered through experience.
- Prior architectural decisions and their rationale.
- Lessons learned from past mistakes.
- User preferences that persist across sessions.

**Do NOT store in memory:**
- Temporary task state (use plan files instead).
- One-off fixes that will not recur.
- Large code snippets (reference files instead).
- Sensitive information (secrets, credentials).

## Workflow

1. **Before starting a task**: The SessionStart hook has already
   auto-injected the project state summary. Additionally check whether
   memory has relevant prior context — do a quick `Grep` over the memory
   folder.

2. **During exploration**: Delegate to subagents. Keep the main context
   clean.

3. **At a checkpoint**: Commit the work, then assess context usage. If
   > 70%, open a new conversation with a summary of the completed work
   attached.

4. **After shipping**: Update memory with new conventions or lessons.
   Start fresh for the next feature.

## Anti-Patterns

- Pasting 30 file reads into the main thread (use a subagent instead).
- Reading an entire file when only one function is needed (use
  offset/limit).
- Never resetting context (leads to drift and contradictions).
- Stuffing everything into Rules (makes every turn expensive — use
  Skills instead).
- Using memory for temporary state (use plan/spec files instead).
- Re-reading files already in context (scroll up).
- Expecting the agent to know project state out of thin air without the
  SessionStart hook summary.
- Hook-injected content so long it wastes the context window instead.
