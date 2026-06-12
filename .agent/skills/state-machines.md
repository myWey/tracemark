---
id: skill-state-machines
relevance: Non-trivial UI states or async flows; designing Layer 3 components
---

# Skill: UI State Machines

> Make implicit state explicit. The compiler then catches missing branches.

## When to reach for one

A component has *any* of:

- > 2 mutually exclusive view states (loading, error, empty, content).
- A multi-step flow (wizard, multi-stage form, OAuth dance).
- Async with cancellation, retry, or timeout semantics.
- Race conditions (user clicks twice; navigates away mid-load).

If a component has just `default + loading + error`, plain `useReducer` /
union-typed status is fine — don't over-engineer.

## Where it lives

```
packages/features-{name}/state/{flow}.machine.ts
```

Tests next to it: `{flow}.machine.test.ts`.

## Conventions

- States are nouns: `idle`, `submitting`, `success`, `failure`, `awaiting-confirm`.
- Events are SCREAMING_SNAKE: `SUBMIT`, `RETRY`, `CANCEL`.
- Guards are predicates on context: `isValid`, `hasPendingChanges`.
- Side effects (network, navigation) live in actions/services, NOT inside
  guards or assignments.

## Exhaustiveness

The machine MUST exhaust every state × event combination — explicitly or
through a clearly-stated default. Use the framework's `strict` mode.
TypeScript should error if a new state is added but a switch over states
isn't updated.

## Visualizing

State machines have free visualization (XState inspector, mermaid). Wire
into `.agent/map/data-flow.svg` via the regenerator.

## Sub-agent integration

`visual-reviewer` reads the machine to know which states to render in the
visual diff matrix. A state in the machine without a Storybook story is a
finding.

## Anti-patterns

- Putting fetch/navigation calls inside `assign()`.
- Reaching out to global state from inside the machine.
- Implicit "is this the first render?" booleans — make it a state.
