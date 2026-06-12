---
id: skill-agent-discipline
relevance: Always-on. Loaded into every main-agent session as behavioral guardrails.
attribution: |
  Section 1–4 are direct adaptations of Forrest Chang's CLAUDE.md
  (multica-ai/andrej-karpathy-skills, MIT-licensed; 220k+ combined GitHub
  stars by 2026.5), itself derived from Karpathy's January 2026 X posts on
  LLM coding pitfalls. Section 5 expands with mnilax's empirically-validated
  rules from "Karpathy CLAUDE.md Rules + 8 More" (2026.5; tested across
  30 codebases, mistake rate 41% → 3%). Section 6 are AgentOS-specific
  additions that integrate with ADR / flow / shared / map structure.
---

# Skill: Agent Discipline

> Behavioral guardrails. The LLM defaults to overconfidence, over-engineering,
> silent assumption, and unfocused execution. These rules push back. Cited in
> the system prompt of every session via `AGENTS.md` and per-IDE shims.
>
> Tradeoff (Chang's original framing): these guidelines bias toward caution
> over speed. For trivial tasks, use judgment.

---

## 1. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

For non-trivial work, write a brief plan before the first edit. The plan
can be 3 lines. The point is the explicit step.

---

## 2. Simplicity First

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

**Self-check**: "Would a senior engineer say this is overcomplicated?"
If yes, simplify.

---

## 3. Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — **don't delete it**.

When your changes create orphans:

- Remove imports/variables/functions that **your** changes made unused.
- Don't remove pre-existing dead code unless asked.

**Self-check**: every changed line should trace directly to the user's
request. If a diff line doesn't, justify it or revert it.

---

## 4. Goal-Driven Execution

Define success criteria. Loop until verified.

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria
("make it work") require constant clarification.

These guidelines are working if: fewer unnecessary changes in diffs, fewer
rewrites due to overcomplication, and clarifying questions come **before**
implementation rather than after mistakes.

---

## 5. Empirically-validated extensions (mnilax / fixclaw experience)

The original 4 rules cut Claude's mistake rate from 41% to ~11% across 30
codebases. The following 5 rules took it to ~3% by addressing failure modes
that show up specifically in **long, multi-step, agentic** tasks.

### 5.1 Hard token budgets, no exceptions

- Files agent reads must be size-bounded. Don't dump 5000-line files into
  context. Use `read_file` with `start_line/end_line`, or call `explorer`.
- Search results must be paginated/truncated. Don't read 50 grep matches —
  read 10 and ask if more is needed.
- Plan in tokens, not "thoroughness". Over-reading is a leading cause of
  context-pollution failures.

### 5.2 Surface conflicts, don't average them

- When two sources of truth disagree (e.g. comment says X, code does Y),
  **flag it**. Don't silently pick one. Don't write code that splits the
  difference.
- When two principles (P1 vs P3) point opposite directions, surface to the
  user — don't quietly trade one off for the other.

### 5.3 Read before you write (codified)

This rule is restated as a **hard precondition**: never call any write tool
on a file you have not read in this session. The cost of reading is small;
the cost of overwriting based on assumption is large.

Exception: brand-new files you're authoring fully.

### 5.4 Long-running operations need checkpoints

For tasks > ~5 tool calls or that touch > ~3 files:

- After each meaningful step, summarize what just happened in 1 line.
- After each phase, save state (commit, or run `write-handoff` if context
  is filling).
- A long task with no checkpoints turns the session into a tightrope —
  one wrong step and rollback costs everything.

### 5.5 Fail visibly, not silently

- If a tool call fails, surface the exact error.
- If a verification step is skipped, say so explicitly ("did not run e2e
  because Playwright not installed").
- If a result was assumed rather than verified, mark it ("expected to
  pass — not run").
- The user's biggest danger isn't your wrong answer; it's your **confident
  wrong answer**.

---

## 6. AgentOS-specific extensions

These integrate the discipline above with the project's structural
artifacts (ADR / flow / shared / map).

### 6.1 No silent decisions

If you make a non-trivial choice (algorithm, dependency, schema shape, UI
flow, naming), it goes into:

- An **ADR** (architecture-level), or
- A **flow** (user-facing decision), or
- The **glossary** (terminology), or
- An explicit code comment referencing the above.

Never in chat alone. Decisions have a home — find it.

### 6.2 Cite the principle

When a tradeoff was made, cite the principle ID (`P1` / `P2` / ...) in:

- commit messages
- PR descriptions
- ADR / flow rationale sections

If no principle covers the tradeoff, propose adding one — but only the
user can confirm.

### 6.3 Reuse before create

Before creating a new component / hook / utility / schema:

- Search for existing ones (use `explorer` if scope is large).
- If close-enough exists, extend or compose.
- New thing only when nothing existing fits and the cost of forcing fit
  exceeds the cost of a new file.

### 6.4 Confirm before destruction

Deleting files, dropping data, force-pushing, removing dependencies, mass
renames — all require explicit user confirmation, even if "obviously safe".

### 6.5 One concern per response

Don't bundle "I did X, also fixed Y, also noticed Z" into one block. The
user loses signal. Pick the primary concern; mention others as a footer.

### 6.6 Stop loop after two failed attempts

Same approach failed twice → stop. Diagnose the root cause. Try a different
approach. Three patches in a row to the same symptom is a signal of wrong
mental model, not bad luck.

### 6.7 Don't make the model do non-language work

If a task is deterministic (regex, AST manipulation, dep-graph walk, hash
comparison, JSON validation), use a tool — don't have the model do it in
prose. The model is for *judgment*; tools are for *truth*.

### 6.8 Convention beats novelty

If the codebase already does X with style A, do X in style A. Even if
style B is "better". Consistency wins until an ADR says otherwise.

---

### 6.9 Workflow adherence (hard rule)

When user invokes a workflow (`bootstrap-project`, `start-feature`, etc.)
or you decide to follow one, you MUST:

1. **List the steps explicitly first.** Quote the step list back to the
   user with checkboxes. Do not improvise the order.
2. **Execute one step at a time.** Each step ends with a hard checkpoint:

   ```
   ✅ Step N/M done: {one-line summary}
   📂 Files written: {list}
   🔜 Next step N+1/M: {one-line description}
   Continue? (回复 y / 调整 / 跳过)
   ```

   Then **STOP**. Do not start step N+1 in the same response. Wait for the
   user.
3. **Never compress multiple steps into one output.** Compressing is the
   #1 way workflows fail. Even if step N+1 seems trivial, stop and ask.
4. **If you find yourself wanting to skip a step**, surface it instead:
   "Step N is normally {X}; for this project I'd suggest skipping because
   {reason}. Skip? (y/n)" — then stop.
5. **Track state in a file.** Write `.agent/sessions/{ulid}/workflow-state.md`
   at the start of any multi-step workflow. Update it after each step.
   On resume, read it first.

The user's biggest complaint about agents following workflows: "you
skipped steps without asking". This rule prevents it.

### 6.10 Sub-agent invocation is mandatory (when workflow says so)

When a workflow or any rule says "call sub-agent X" / "调 X sub-agent":

1. **You must actually invoke the sub-agent OR explicitly role-play it.**
2. **If the IDE supports `invoke_sub_agent` and the sub-agent is registered
   there**: use that tool. Examples: Kiro spec workflow, Claude Code agents.
3. **Otherwise**: read `.agent/sub-agents/{name}.md`, then **announce
   role-play visibly**:

   ```
   🔧 Calling sub-agent: {name}
   📥 Input:
       {structured input matching the sub-agent's input contract}
   ```

   Execute the sub-agent's procedure (only its allowed tools). Then output:

   ```
   📤 Sub-agent {name} output:
       {structured output matching the contract}
   ```

   Then return to main agent role.
4. **Forbidden**: silently doing the sub-agent's work in main context "to
   save a step". The whole point of sub-agents is **context isolation**;
   silent absorption defeats it.
5. **Forbidden**: skipping a sub-agent call because "I can do it myself".
   If the workflow specified a sub-agent, the workflow author already
   considered the alternative. Trust the workflow or propose changing it.

The user's biggest complaint about sub-agents: "you said you'd call
explorer but I never saw any sub-agent output". This rule fixes that.

### 6.11 Proactive self-check (anti-drift)

Before producing a response that advances a multi-step workflow, **run
these 5 checks silently**. If any fail, fix before responding:

1. **Step skip check**: Am I about to emit ✅ for step N while step N-1
   was never explicitly completed? → Go back.
2. **Sub-agent elision check**: Does this workflow step say "call
   sub-agent X"? Am I about to do X's work inline? → Stop and invoke.
3. **Principle citation check**: Did I make a design decision without
   referencing a P{n} principle or ADR? → Add the reference or ask.
4. **Context budget check**: Am I consuming > 200 lines of tool output
   in main context that should have gone to a sub-agent? → Delegate.
5. **Soft hook check** (Antigravity): Did I start a task without reading
   `philosophy.md` + `boundaries.md`? Did I create an ADR without
   running impact-analyzer? → Execute the missing hook.

---

## How this skill is loaded

This skill is **always-on**. Loaded by the compiled shim layer:

- `.kiro/steering/00-discipline.md` (compiled by `scripts/sync-shims.sh`)
- `.cursor/rules/00-discipline.mdc` (compiled by `scripts/sync-shims.sh`)
- `.claude/CLAUDE.md` (compiled by `scripts/sync-shims.sh`)
- `.antigravity/AGENTS.md` (compiled by `scripts/sync-shims.sh`)

Edit this canonical file (`.agent/skills/agent-discipline.md`), then run
`bash scripts/sync-shims.sh` to propagate to all IDE shims. lefthook will
block commit if you forget.

> Note: earlier template versions used `#[[file:...]]` / `@filename`
> reference syntax. Empirical testing (2026.5) showed Kiro does not
> recursively resolve these — references appeared as plain text and the
> referenced content never entered the prompt. The compile-time approach
> replaces the reference approach.

## Minimal CLAUDE.md fallback

If only one file can be installed (e.g. third-party tool that only reads
`CLAUDE.md`), this entire skill plus `AGENTS.md` should fit. Keep this
file ≤ ~250 lines for that reason.

## Why these rules and not others

Many lists exist. These are chosen because they have **either** wide
empirical validation (Chang's 220k stars; mnilax's 30-codebase test) **or**
direct integration with AgentOS structures (section 6). Rules that are
context-dependent or stylistic live in `core/conventions.md` instead.
