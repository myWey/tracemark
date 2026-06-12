---
id: domain-entities
status: template
last-confirmed: null
---

# Domain Entities

> The conceptual model — what *exists* in the product world, independent of
> storage or transport. Code shapes (DB tables, API resources, types) derive
> from this; this does not derive from them.

## How to read

- Each entity has: identity, lifecycle states, key attributes, relations,
  invariants.
- Entities reference glossary terms verbatim.
- When an entity's invariants change, write an ADR.

## Entity: {Name}

- **Identity**: {how it is uniquely identified}
- **Lifecycle**:
  - `state-1` → `state-2` (trigger: ...)
  - `state-2` → `state-3` (trigger: ...)
- **Key attributes**: {field — meaning}
- **Relations**:
  - {relation} → {other entity} ({cardinality})
- **Invariants** (always true):
  - I1. ...
  - I2. ...
- **Derived schemas**:
  - `shared/schemas/{name}.ts`
  - `shared/api-contracts/{name}.ts`

## Entity: {Name}

...

## Cross-entity invariants

- X1. ...
- X2. ...
