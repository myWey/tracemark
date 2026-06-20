---
description: Run an adversarial code review on recent changes before shipping.
---

# /review

Runs a structured, adversarial review on uncommitted or committed changes.
This is a gate — nothing ships until the review passes.

## Workflow

1. Identify changes: `git diff` / `git diff --staged` / `git diff <base>..HEAD`.
2. Load any active `.trae/specs/<change-id>/checklist.md`.
3. Delegate to the `reviewer` subagent with the change range and spec context.
4. Present the review report. If verdict is NEEDS_CHANGES or FAIL, stop and fix before `/ship`.

## Rules

- The reviewer is read-only. Fixes go through the executor.
- A review that finds nothing is suspicious.
