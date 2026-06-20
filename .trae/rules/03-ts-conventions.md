---
description: TypeScript/JavaScript-specific naming and import conventions.
alwaysApply: false
globs: "**/*.{ts,tsx,js,jsx}"
---

# TypeScript / JavaScript Conventions

Applies to `**/*.{ts,tsx,js,jsx}` files.

## Naming

| Context | Convention | Example |
|---------|-----------|---------|
| Variables / functions | camelCase | `userName`, `fetchData()` |
| Components / types / interfaces | PascalCase | `UserProfile`, `UserConfig` |
| Constants | UPPER_SNAKE | `MAX_RETRY_COUNT` |
| Private members | prefix `_` | `_internalState` |
| Filenames | kebab-case | `user-profile.tsx` |

## Imports

- Prefer path aliases (`@/`) when project config defines one.
- Otherwise use relative imports.
- Group imports: standard library → third-party → local.
- Delete unused imports.
