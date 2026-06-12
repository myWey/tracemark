---
id: skill-frontend-patterns
relevance: Building UI in Layer 1–4; componentizing; refactoring UI
---

# Skill: Frontend Layered Patterns

> Practical patterns for the 5-layer onion (tokens → primitives →
> composites → features → pages). Pair with `boundaries.md`.

## Layer 0 — Tokens

See [`design-tokens.md`](./design-tokens.md).

## Layer 1 — Primitives

- **Headless** (no styling assumptions) + token-driven.
- One component does one thing. `Button`, `Input`, `Card` — not
  `LoginButton`.
- All interaction states (hover, focus, active, disabled, loading) defined.
- Storybook story per primitive × per state.
- No business logic. No API calls. No domain types.

## Layer 2 — Composites

- Combine primitives. `FormField`, `DataTable`, `Toast`.
- Still domain-agnostic. A composite doesn't know about your `User`.
- Accepts behavior via props/render-props/slots.
- Storybook story per composite × per shape.

## Layer 3 — Features

- Domain-aware. Imports from `shared/schemas`, `shared/events`,
  `shared/api-contracts`.
- Hooks for data: `useResetPasswordMutation`, `useUserProfileQuery`.
- State machines live here for non-trivial flows
  ([`state-machines.md`](./state-machines.md)).
- Composes Layer 1–2; renders for Layer 4.

## Layer 4 — Pages / Routes

- The orchestrator. URL ↔ data ↔ feature wiring.
- No reusable components defined here. If a page invents UI, lift it down
  to Layer 1–3.
- Loading/error/empty handled by the route or the feature, never duplicated.

## State sources (clarify per feature)

- **Server state**: cache layer (TanStack Query, RTK Query, SWR). Owns
  remote data lifecycle.
- **URL state**: route + query params. Owns shareable UI position.
- **Form state**: ephemeral input. Owns validation.
- **Local UI state**: toggles, hovers, modal-open.
- **Cross-feature state**: rare — extract via shared events, not a global
  store, unless ADR justifies it.

## Common mistakes (and the fix)

- Putting fetch in a primitive → lift it to Layer 3 hook.
- Importing a feature into a primitive → it's a hint that the primitive
  needs slots/render-props.
- Duplicating loading skeletons across pages → composite it.
- Inventing a new route helper per page → it belongs in Layer 4 utility.

## Sub-agent integration

- `visual-reviewer` enforces the state matrix: each component × all its
  declared interaction states.
- `explorer` is your friend before adding a new component — search for
  similar.
