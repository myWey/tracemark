---
name: memory-management
description: Manage cross-session memory in .trae/memory/. Use when deciding whether to persist a convention, decision, lesson, or milestone.
---

# Memory Management

## When to Use

Invoke this skill when:
- You discover a project-wide convention that isn't obvious from code or rules.
- You make an architecture decision with rationale worth preserving.
- You learn from a mistake (e.g., "after X, must Y, otherwise Z").
- A user expresses a persistent preference.
- You complete an important milestone and need to update `topics.md`.

Do NOT use memory for:
- Temporary task state (use spec/plan files).
- One-off bug fixes (use the git commit message).
- Large code blocks (reference file paths instead).
- Secrets or credentials.

## How to Write

1. **project_memory.md**: Append concise entries under `## Conventions`, `## Architecture Decisions`, or `## Lessons`.
   - One-line summary + key detail.
   - Reference files/paths, don't paste code.
2. **topics.md**: Add a dated topic entry summarizing the session's work.
3. **Check first**: Read `.trae/memory/project_memory.md` to avoid duplicate entries.

## File Locations

- `.trae/memory/project_memory.md`
- `.trae/memory/topics.md`
- Session-level granular records may be added as `.trae/memory/session_memory_*.jsonl` if tooling supports it.

## Example

```markdown
## Conventions
- All API responses use `{code, data, message}` shape (see `src/api/types.ts`).
```

## Maturation Checkpoint

> Teaching is the external harness helping the internal harness mature. Memory is the internal harness; the spec/plan/review/ship loop is the external harness.

After completing each spec's Ship phase, perform a maturation checkpoint:

1. **Reflect**: What did this spec cycle teach? Did I discover a new convention, make an architectural decision, or learn from a mistake?
2. **Write**: If yes, write it to `project_memory.md` under the appropriate section (Conventions / Architecture Decisions / Lessons).
3. **Update**: Review existing memory entries — are any now outdated or contradicted by this cycle? Update them.
4. **Prune**: Are there memory entries that haven't been referenced in a long time and are no longer accurate? Consider removing them.

### Maturation Checkpoint Template

```
## Maturation Checkpoint — [spec change-id] — [date]

**New conventions discovered**: [list or "none"]
**Decisions made**: [list or "none"]
**Lessons learned**: [list or "none"]
**Memory entries updated**: [list or "none"]
**Memory entries pruned**: [list or "none"]
```

### When to Skip

- The spec was trivial (typo fix, small text change) — no learning expected.
- The spec didn't touch unfamiliar code — no new conventions likely.

### Anti-Pattern

- Skipping maturation checkpoint after every spec — memory stagnates, internal harness doesn't mature.
- Writing verbose entries — memory should be concise (one line per convention/decision/lesson).
- Never pruning — stale memory is worse than no memory.
