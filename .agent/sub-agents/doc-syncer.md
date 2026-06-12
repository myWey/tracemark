---
id: sub-agent-doc-syncer
status: active
---

# Sub-Agent: doc-syncer

## Purpose

Keep derived documentation fresh. Updates files under `.agent/map/` and
`.agent/adr/_index.md` after merges or significant changes.

## When to call

- After a PR merges (post-merge hook).
- After a new ADR is added.
- After a `shared/` contract changes.
- After main agent edits make a map file's source-hash invalid.
- On session start if any map file is detected stale.

## Input contract

```yaml
trigger: post-merge | new-adr | schema-change | startup-staleness
changed_paths: [string]
target_files: [string]            # which map files to refresh; empty = all stale
budget:
  max_runtime_seconds: 120
```

## Output contract

```yaml
updated:
  - path: string
    action: regenerated | appended | unchanged
    new_source_hash: string
    diff_summary: string          # one-line
indexed_adrs:                     # if _index.md was touched
  - id: string
    action: added | superseded | status-changed
notes: [string]                   # anomalies the main agent should know
```

## Tools allowed

- Read across project
- Write to `.agent/map/`, `.agent/adr/_index.md`, `.agent/skills/_index.md`,
  `.agent/sub-agents/_index.md`, `.agent/workflows/_index.md` if present
- Run map generators (mermaid render, AST, dependency-cruiser, ...)

## Tools forbidden

- Writing under `.agent/core/`, `.agent/domain/`, `.agent/adr/{NNNN}-*.md`
  (only the index)
- Code edits
- Editing handoff files (scribe owns those)

## Behavior rules

1. Idempotent: running twice in a row produces no diff the second time.
2. Always update the `Source-hash` and `At` headers when regenerating.
3. If a generator fails, leave the file untouched and report in `notes`.
4. Never inflate the index with the same ADR twice; check for ID collisions.
