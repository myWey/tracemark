# shared/ — Cross-cutting Contracts

Single source for things consumed by every layer. Anything imported from
both front-end and back-end (or from multiple features) lives here.

## Layout

```
shared/
├── tokens/          # Design tokens (DTCG JSON). See .agent/skills/design-tokens.md
├── schemas/         # Runtime validation (zod / valibot / proto)
├── events/          # Event payload contracts (cross-feature, cross-tier)
└── api-contracts/   # API surface (OpenAPI / tRPC router / gRPC)
```

## Rules

- Pure data definitions. No runtime logic that depends on a UI or a server.
- Importable from any layer.
- Breaking change in shared/ → ADR + impact-analyzer + migration spec.
- Naming follows `core/glossary.md` exactly.

## Why split this way

Schemas describe *what data is*. API contracts describe *how it moves*.
Events describe *what happened*. Tokens describe *how it looks*. Same
truth, different lenses; keeping them physically separate makes drift
visible.
