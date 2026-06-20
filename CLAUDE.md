# CLAUDE.md for agentOS

This project uses `AGENTS.md` as the single source of truth for agent behavior.
The `@import` directive below loads the full AGENTS.md content in Claude Code.

@import AGENTS.md

---

## Fallback Rules (if @import is not supported)

If the `@import` above did not load AGENTS.md content, follow these rules.
These are a condensed safety net — always defer to the full AGENTS.md when available.

### Workflow (Strict Mode)

Every non-trivial task follows: `Research → Spec → Plan → Execute → Review → Ship`.

1. **No code without a spec**: tasks >50 lines or spanning 2+ files must run `/spec` first.
2. **No plan without research**: tasks touching unfamiliar modules must be researched first.
3. **No ship without review**: nothing ships without passing `/review` checklist.
4. **Checkpoint commits**: commit every 3-5 tasks or at logical boundaries.
5. **Ask when unsure**: never silently assume. State the assumption and ask.
6. **Goal-driven**: convert vague tasks into verifiable goals, loop until they pass.

### Safety Red Lines

Safety red lines are defined in `.trae/rules/01-conventions-and-safety.md` (always loaded by Trae rules system). Key points: never force-push/reset-hard/checkout-clean/branch-D; never commit secrets; never run destructive commands; never commit without being asked.

### Context Hygiene

- Delegate exploration to subagents when reading >5 files or producing >100 lines output.
- Start a new conversation when context >70% full, after shipping, or switching features.
- Use `Grep`/`Glob` to locate, then `Read` only relevant lines.
- Don't re-read files already in context.

### Build Commands

See `AGENTS.md` section "Build and Test Commands" or `scripts/` directory.

### Project Assets

Project-level documents live in `docs/`: `PHILOSOPHY.md`, `TERMS.md`, `ARCHITECTURE.md`, `UI-UX-SPEC.md`, `ROADMAP.md`, and `docs/adr/`. Read relevant ones before starting a task.

### Specs Location

Trae native `/spec` outputs to `.trae/specs/<change-id>/` (spec.md + tasks.md + checklist.md).
