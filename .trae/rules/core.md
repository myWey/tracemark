# Trae — Core Rules (shim)

Canonical truth lives under `.agent/`. Trae loads this file at session
start; treat the references below as required reading.

See:
- `AGENTS.md`
- `.agent/core/philosophy.md`
- `.agent/core/conventions.md`
- `.agent/core/boundaries.md`
- `.agent/core/glossary.md`
- `.agent/sub-agents/_index.md`
- `.agent/workflows/_index.md`
- `.agent/skills/_index.md`

## Hard rules (mirror of AGENTS.md)

- Decisions → ADR.
- Architecture changes → `.agent/workflows/architecture-change.md`.
- Logical time only (ADR IDs, ULID, epoch tags, commit hashes).
- Sub-agents stateless; persistence via files in `.agent/`.
