---
description: Python-specific naming and import conventions.
alwaysApply: false
globs: "**/*.py"
---

# Python Conventions

Applies to `**/*.py` files.

## Naming

| Context | Convention | Example |
|---------|-----------|---------|
| Variables / functions | snake_case | `user_name`, `fetch_data()` |
| Classes | PascalCase | `UserProfile` |
| Constants | UPPER_SNAKE | `MAX_RETRY_COUNT` |
| Private members | prefix `_` | `_internal_state` |
| Filenames | snake_case | `user_profile.py` |

## Imports

- Group imports: standard library → third-party → local.
- Delete unused imports.
- Prefer absolute imports over relative imports for top-level modules.
