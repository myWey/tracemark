---
name: project-onboarding
description: Project onboarding workflow for embedding a concrete project into agentOS. Use when a new project is added, or when an existing project needs to be made "agent-ready". Drives a 7-stage human-agent co-creation process that generates strategic and execution-layer project assets.
---

# Project Onboarding

## When to Invoke

- A new project is added to the agentOS workspace.
- An existing project needs to be made "agent-ready".
- A project is being built from scratch and needs a global view first.
- The user says "embed project", "initialize project", "onboarding".

## When NOT to Invoke

- Just modifying a small feature of an existing project (use `/spec` directly).
- The project already has complete PHILOSOPHY/TERMS/ARCHITECTURE/etc. assets (skip completed stages).

## Core Philosophy

Project onboarding is **human-agent co-creation**:
- The agent scans, analyzes, and drafts.
- The human decides, confirms, and contributes domain knowledge.
- The outputs are the project's "constitution" — all subsequent spec/plan/execute work is constrained by them.

Every document must be **short, structured, and verifiable**. If a template section cannot be filled with concrete content, mark it explicitly rather than leaving placeholder text.

## 7-Stage Workflow

### Stage 1: Project Scan

Use an `explorer` subagent to scan the project. Report:
- Tech stack (language, framework, build/test/lint tools, package manager)
- Directory structure and module boundaries
- Existing conventions (naming, imports, error handling)
- Test framework and coverage
- CI/CD configuration
- Dependencies and versions
- Git history and branching strategy

**Output**: In-conversation summary (no file generated).
**Human confirmation**: Confirm accuracy and supplement missing context.

### Stage 2: Product Philosophy (docs/PHILOSOPHY.md)

Generate a concise philosophy document:

```markdown
# Product Philosophy

One-sentence vision: [what problem this product solves for whom]

## Core Principles
1. [concrete principle that shapes decisions]
2. [principle]
3. [principle]

## What We Do Not Do
- [out-of-scope direction and why]

## Decision Framework
When principles conflict, resolve in this order:
1. [highest priority]
2. [second priority]
3. [third priority]
```

Target: ≤80 lines.

### Stage 3: Terms & Naming (docs/TERMS.md)

Generate:

```markdown
# Terms & Naming

## Domain Terms
| Term | Definition | Notes |
|------|------------|-------|
| [term] | [precise definition] | [usage note] |

## Naming Conventions
| Scope | Convention | Example |
|-------|------------|---------|
| Variables | [e.g., camelCase] | [example] |

## Forbidden Terms
- [ambiguous word] — use [precise alternative] instead.
```

### Stage 4: Architecture (docs/ARCHITECTURE.md + docs/adr/ADR-001-*.md)

Generate:

```markdown
# Architecture

## Summary
[3 sentences: what the system is, its main parts, and how they interact.]

## Module Boundaries
| Module | Responsibility | Public Interface | Depends On |
|--------|---------------|------------------|------------|
| [name] | [one-line] | [API/events] | [modules] |

## Interface Contracts
| Interface | Format | Owner | Stability |
|-----------|--------|-------|-----------|
| [API/event/schema] | [format] | [owner] | [stable/experimental] |

## Technology Choices
| Area | Choice | Rationale | ADR |
|------|--------|-----------|-----|
| [area] | [tool] | [why] | ADR-001 |

## Constraints
- [architectural rule]

## ADR Index
- [ADR-001: initial-tech-stack](docs/adr/ADR-001-initial-tech-stack.md)
```

Also create the first ADR using the MADR-style template in `docs/adr/README.md`.

### Stage 5: UI/UX Spec (docs/UI-UX-SPEC.md)

Generate if the project has a UI. Include Design Tokens, Component Usage, and an Accessibility Checklist.
Skip if no UI.

### Stage 6: Roadmap (docs/ROADMAP.md)

Use Now/Next/Later format. Every initiative must have a verifiable exit criterion.

```markdown
# Roadmap

## Vision
[one sentence aligned with PHILOSOPHY.md]

## Now
| Initiative | Goal | Exit Criteria | Owner |
|------------|------|---------------|-------|
| [name] | [goal] | [verifiable condition] | [owner] |

## Next
...

## Later
...

## Not This Quarter
- [direction and why]

## Success Metrics
| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| [name] | | | |
```

### Stage 7: Configure AGENTS.md + Create ADR-001

Fill the scanned commands into `AGENTS.md`:

```bash
# install: [command]
# build: [command]
# test: [command]
# lint: [command]
# typecheck: [command]
```

## Completion Criteria

After onboarding, these files must exist and be human-confirmed:

- [ ] `docs/PHILOSOPHY.md`
- [ ] `docs/TERMS.md`
- [ ] `docs/ARCHITECTURE.md`
- [ ] `docs/UI-UX-SPEC.md` (if UI)
- [ ] `docs/ROADMAP.md`
- [ ] `docs/adr/ADR-001-*.md`
- [ ] `AGENTS.md` (build commands filled in)

Note: `docs/FEATURES.md` is auto-created by `/ship`. `docs/rfc/` is created on-demand when an RFC trigger condition is met.

## Principles

- **Human-agent co-creation**: The agent drafts; the human decides.
- **Scan-based**: Specifications reflect the project's current state.
- **Living documents**: Assets are continuously updated as the project evolves.
- **Verifiable**: Every acceptance criterion and exit condition must map to a runnable check.
- **Surgical fixes**: With a global view, problems can be precisely located and minimized.

## Anti-Patterns

- The agent unilaterally generates all assets and the human just signs off.
- Assets are generated and never updated again (stale documentation).
- Skipping the scan stage and writing philosophy directly.
- PHILOSOPHY written as marketing copy.
- TERMS lists only technical terms and omits domain terms.
- Acceptance criteria without verification commands.
