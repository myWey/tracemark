---
description: Final ship gate. Verify review passed, checklist complete, tests/lint/build green, then generate ship summary.
---

# /ship

Runs the final ship gate before delivery. This is the last checkpoint.

## Workflow

1. Verify `/review` returned PASS. If not, stop and re-review.
2. Check `.trae/specs/<change-id>/checklist.md` completion. Incomplete items block shipping unless explicitly deferred by the user.
3. Run the ship checklist:
   - Code state: no TODO/FIXME placeholders, no debug logs, no commented-out code.
   - Tests: full suite passes.
   - Quality gates: lint, typecheck, build pass.
   - Git hygiene: Conventional Commits, no conflicts, no secrets.
   - Documentation: README/API docs updated if changed.
   - Scope: only spec/plan files modified, no unexpected dependencies.
4. Append to FEATURES.md: Add a row with feature name, status='stable', spec link (change-id), ship date (today). If FEATURES.md doesn't exist, create it from docs/FEATURES.md template.
5. Generate the ship summary and ask for final confirmation.
6. Do not merge without explicit approval.

## Rules

- Any failed checklist item blocks shipping.
- Never auto-merge.
- Incomplete native spec checklist items are a hard block unless the user explicitly defers them.
