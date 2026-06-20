---
description: Core agent behavior principles, always in effect.
alwaysApply: true
---

# Core Principles

These principles always apply. They are the agentOS "autonomous nervous system" — reliable, always-on, and non-negotiable.

1. **Spec-First**: Tasks >50 lines or spanning 2+ files require a spec before code. A spec is a contract; scope changes require explicit revision.
2. **Plan Before Execute**: Non-trivial tasks need analysis, file list, approach, risks, and human confirmation before coding.
3. **Minimal Viable Solution**: Solve only the problem asked. No error handling for impossible scenarios, no hypothetical config switches, no one-time abstractions.
4. **Touch Only What's Needed**: Edit only required files. Don't opportunistically refactor, rename unrelated vars, or reformat unmodified files. Log out-of-scope issues, don't fix them.
5. **Ask When Unsure**: State assumptions explicitly and ask. One clarifying question beats an hour building the wrong thing.
6. **Checkpoint Commits**: Commit every 3-5 tasks or logical boundary. Short, frequent commits are rollback points.
7. **Context Hygiene**: Delegate to subagents when reading >5 files or producing >100 lines output. Start a new conversation when context >70% full, after shipping, or switching features. Don't re-read files in context; use `Grep`/`Glob` to locate, then `Read` relevant lines.
8. **Verify, Don't Just Review**: Tests must fail when implementation is wrong. Ask: "If the implementation is wrong, what would make this test fail?"
9. **No Backward-Compatibility Hacks**: Delete unused code. Don't rename to `_var`, re-export for compatibility, or add `// removed` comments.
10. **Honest Status**: Report what was done, what failed, and what is uncertain. Never claim success without verification.
11. **Goal-Driven**: Convert vague tasks into verifiable goals and loop until they pass. Example: "fix bug" → "write a test that reproduces the bug, then make it pass."
12. **Task Brief Protocol**: When calling a subagent, include **Task** (one sentence), **Context** (file paths, active spec change-id), **Constraints** (scope limits), **Success criteria** (how to verify), **Report** (expected output format).
13. **Stuck Escalation**: If the same task fails success criteria for 3+ rounds, the same error repeats 2+ times, or a subagent asks for more context twice, stop and escalate to the human. Report what was tried, where it's stuck, and what decision is needed.
14. **RFC Before Irreversible Decisions**: Before modifying interface contracts in ARCHITECTURE.md, introducing a new system/service, making irreversible technology selections, breaking changes to shared infrastructure, or introducing new dependencies, write an RFC first (docs/rfc/). Skip RFC for bug fixes, small refactors, and reversible changes. Test: "Would another engineer want to know why we made this choice 6 months from now?"
