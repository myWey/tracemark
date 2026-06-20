---
description: Coding conventions and safety red lines, always in effect.
alwaysApply: true
---

# Conventions & Safety

## Naming

Language-specific naming rules live in `02-python-conventions.md` and `03-ts-conventions.md` (globs-triggered). This file covers cross-language conventions:

- Constants: `UPPER_SNAKE` (e.g., `MAX_RETRY_COUNT`).
- Private members: prefix `_` (e.g., `_internalState`).
- Filenames: kebab-case for general files; Python files use snake_case.

## Code Style

- Prefer path aliases (`@/`) when configured; otherwise relative imports.
- Group imports: stdlib → third-party → local. Delete unused imports.
- One function, one responsibility. Max ~40 lines, max 4 parameters.
- Early returns over nested conditionals.
- Validate at system boundaries (user input, external APIs). Trust internal code.
- Test behavior, not implementation. One conceptual assertion per test.
- Comments explain WHY, not WHAT. Include context in TODOs.

## Subagent Project Asset Check

All subagents: before starting a task, check whether `docs/PHILOSOPHY.md`,
`docs/TERMS.md`, and `docs/ARCHITECTURE.md` exist and are initialized (no
"Template" status banner). If present, use them as context to align with
the project's global vision — the glossary for vocabulary, the architecture
for module boundaries, the philosophy for tradeoff weighing.

## Git Commits

- Use Conventional Commits: `type(scope): subject`.
- Imperative mood, max 72 chars, no period.
- One logical change per commit.

## Safety Red Lines

- Never run `git push --force`, `git reset --hard`, `git checkout .`, `git clean -f`, or `git branch -D` unless explicitly requested.
- Never commit unless explicitly asked. Prefer `git add <file>` over `git add -A`.
- Never delete files outside the project directory or files you didn't create.
- Never overwrite a file without reading it first.
- Never run destructive system commands (`rm -rf /`, `dd`, `mkfs`, `chmod -R 777`, `sudo`).
- Never run database migrations or schema changes without confirmation.
- Never hardcode secrets, API keys, tokens, or passwords.
- Never commit `.env`, `credentials.json`, `*.pem`, `*.key`.
- Never upgrade a dependency's major version or remove a dependency without checking dependents.
- Never modify files outside the project working directory or inside `.git/`.
- Never directly modify lockfiles; use the package manager.
- Never make outbound network requests in production code without review.
- Never run commands with `-i` (interactive) flag — they hang the agent because there is no human at the terminal.
- Avoid `--no-edit` with `git rebase` — it is not a valid rebase option and will fail.
- Never run `git rebase` in non-interactive mode unless the plan explicitly requires rewriting history.
- Never leave debug-capture hooks enabled in production — they write raw input to disk and may capture sensitive data.
