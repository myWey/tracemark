# Windsurf — Core Rules (shim)

Substance is in `.agent/`. This file is a Windsurf-specific entry.

See:
- `AGENTS.md` (universal entry)
- `.agent/core/philosophy.md`
- `.agent/core/conventions.md`
- `.agent/core/boundaries.md`
- `.agent/core/glossary.md`
- `.agent/sub-agents/_index.md`
- `.agent/workflows/_index.md`
- `.agent/skills/_index.md`

## Cascade workflows

Windsurf workflows under `.windsurf/workflows/` should be thin: each one
calls a workflow defined under `.agent/workflows/`. Keep substance
canonical.
