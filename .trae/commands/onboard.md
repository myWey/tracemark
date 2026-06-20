---
description: Launch the project onboarding workflow to embed a concrete project into agentOS and generate all project assets
---

# /onboard — Project Onboarding Workflow

Launches a human-agent co-creation process that generates project assets through 7 stages.

## Invocation

```
/onboard [project description or path]
```

## Workflow

This command triggers the `project-onboarding` skill, which executes:

1. **Project scan**: explorer subagent scans tech stack, structure, and conventions.
2. **PHILOSOPHY.md**: product philosophy (vision + principles + non-goals + decision framework).
3. **TERMS.md**: glossary, naming conventions, forbidden terms.
4. **ARCHITECTURE.md**: architecture doc + first ADR (ADR-001).
5. **UI-UX-SPEC.md**: design system (skip if no UI).
6. **ROADMAP.md**: Now/Next/Later roadmap with verifiable exit criteria.
7. **Configure AGENTS.md + Create ADR-001**: fill in build/test/lint/typecheck commands.

## Execution Rules

- Pause and wait for human confirmation after each stage.
- Delegate the scan phase to an explorer subagent.
- Asset files primarily use English; terms stay in English.
- Skip a stage if its file already exists (supports incremental onboarding).
- On completion, output an onboarding report listing all generated files.

## Completion Criteria

All of the following files exist and have been confirmed by a human:
- `docs/PHILOSOPHY.md`
- `docs/TERMS.md`
- `docs/ARCHITECTURE.md`
- `docs/UI-UX-SPEC.md` (if there is a UI)
- `docs/ROADMAP.md`
- `docs/adr/ADR-001-*.md`
- `AGENTS.md` (with build commands filled in)

See project-onboarding SKILL.md for the canonical Completion Criteria.
