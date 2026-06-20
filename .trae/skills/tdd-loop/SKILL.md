---
name: tdd-loop
description: Use when implementing behavior that can be defined by tests. Follow red-green-refactor: write a failing test first, make it pass, then refactor.
---

# TDD Loop

## When to Use

- Implementing new features with clear inputs/outputs.
- Fixing bugs (reproduce first, fix second).
- Adding validation, parsing, calculation, or state-transition logic.

## When NOT to Use

- Exploratory spikes where the API is unknown.
- Pure configuration or documentation tasks.
- One-off scripts that won't be maintained.

## Workflow

1. **Red**: Write a failing test for the smallest meaningful behavior.
   - The test must fail for the right reason (not because of setup errors).
2. **Green**: Write the minimum implementation to make the test pass.
   - Do not refactor yet. Do not add speculative features.
3. **Refactor**: Clean up duplication and improve names while keeping tests green.
   - Run tests after each refactoring step.
4. **Repeat** until the feature is complete.

## Checklist

- [ ] The first test fails before any implementation exists.
- [ ] Each cycle adds one small behavior.
- [ ] Implementation stays minimal until tests demand more.
- [ ] Refactoring never changes behavior (tests stay green).
- [ ] Commit after each green bar or completed feature slice.

## Anti-Patterns

- Writing all tests up front before any implementation.
- Writing implementation first and tests as an afterthought.
- Refactoring while a test is still failing.
- Skipping the red step because "it's obvious".
