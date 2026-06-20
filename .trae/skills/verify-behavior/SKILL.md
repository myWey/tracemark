---
name: verify-behavior
description: Use after writing code or tests to verify that the implementation is actually tested and the tests would fail if the implementation is wrong.
---

# Verify Behavior

## When to Use

- After implementing a feature or fix.
- After writing tests.
- Before calling `/review` or `/ship`.
- Any time you need to be sure tests test the right thing.

## When NOT to Use

- For pure refactorings with no behavior change (use existing tests).
- When there is no implementation to verify.

## Workflow

1. **Identify the behavior**: Restate the requirement in one sentence.
2. **List the tests**: For each test, write down what it checks.
3. **Ask the critical question** for each test:
   > "If the implementation is wrong, what would make this test fail?"
4. **Classify each test**:
   - **Strong**: fails on a plausible bug.
   - **Weak**: passes even if behavior is wrong.
   - **False positive**: passes regardless of implementation.
5. **Fix weak tests** by making assertions more specific or adding missing scenarios.
6. **Run the tests** and confirm they pass.

## Checklist

- [ ] Every requirement has at least one strong test.
- [ ] Error paths are tested, not only happy paths.
- [ ] No test mocks the wrong abstraction.
- [ ] Each test name describes the scenario, not the implementation.
- [ ] I can explain why each test would fail if the code were wrong.

## Anti-Patterns

- Asserting that a function was called (mocking internals) instead of asserting the outcome.
- Testing only that code "does not crash".
- Using the same data for setup and assertion.
- Writing tests after the fact that mirror the implementation line by line.
