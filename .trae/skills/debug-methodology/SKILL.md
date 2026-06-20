---
name: debug-methodology
description: Use when diagnosing a bug or unexpected behavior. Follow a systematic hypothesis-driven debugging loop.
---

# Debug Methodology

## When to Use

- A test fails and the cause is not obvious.
- Production or runtime behavior differs from expectations.
- A previous fix did not resolve the issue.

## When NOT to Use

- The error message already points to an obvious typo.
- The fix is a one-line change with no risk.

## Workflow

1. **Form a hypothesis**: What do you think is causing the bug? Be specific.
2. **Instrument**: Add minimal logging, breakpoints, or test cases to confirm or reject the hypothesis.
3. **Reproduce**: Make the bug happen reliably. Capture inputs, state, and outputs.
4. **Analyze**: Compare expected vs actual behavior. Narrow the failure surface.
5. **Fix**: Apply the smallest change that resolves the bug.
6. **Verify**: Run the failing test and any related tests. Add a regression test if none exists.

## Checklist

- [ ] I can reproduce the bug consistently.
- [ ] I have a specific hypothesis before changing code.
- [ ] I instrumented only what is needed to validate the hypothesis.
- [ ] The fix is minimal and targets the root cause, not a symptom.
- [ ] A regression test prevents the bug from returning.

## Anti-Patterns

- Changing code randomly until something works.
- Adding defensive checks everywhere instead of fixing the root cause.
- Ignoring the reproduction step and guessing.
- Leaving debug logging or temporary instrumentation in the final code.
