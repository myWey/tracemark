---
id: skill-design-tokens
relevance: Editing or proposing changes under shared/tokens/; visual contract changes
---

# Skill: Design Tokens

> The visual single-source-of-truth. Format: DTCG (W3C Design Tokens
> Community Group) v1.

## Token categories (typical)

- **Color**: brand, surface, text, border, status (success/warning/error/info).
- **Spacing**: scale (e.g. 4px base, multipliers).
- **Typography**: family, size, weight, line-height, letter-spacing.
- **Radius**: scale.
- **Shadow**: elevation levels.
- **Motion**: duration, easing curves.
- **Z-index**: layer scale.

## Naming

- Two-tier: **base** (raw values) and **semantic** (intent-based).
- Components reference *semantic*, never base.
- Example:
  - Base: `color.gray.900`
  - Semantic: `color.text.primary` → `{color.gray.900}`
  - Component: `button.fg` → `{color.text.primary}`

## File layout

```
shared/tokens/
  base/
    color.json
    spacing.json
    ...
  semantic/
    color.json
    ...
  themes/
    light.json
    dark.json
```

Build step transforms to the formats consumed by the stack: CSS variables,
TS constants, native platform formats.

## Editing rules

1. NEVER inline a hex/px in code. Reference a token.
2. Adding a base value: ADR optional, but document the *role* in the JSON.
3. Adding/changing a semantic name: requires ADR (it's a contract).
4. Renaming a semantic token: full rename via codemod; never leave half-
   migrated state.

## Visual review

`visual-reviewer` flags:

- Components rendering colors not present in the token set.
- Spacing values that don't snap to the spacing scale.
- Typography combinations not in the token set.

## Anti-patterns

- "Just this once" inline values.
- Semantic tokens with implementation-specific names (`color.headerBlue`).
- Multiple semantic tokens pointing to the same base "by accident" — that's
  a duplicated decision; consolidate.
