---
name: skill-creator
description: Meta-skill for creating new skills. Use when the user wants to create, add, or modify a skill. Ensures new skills follow the SKILL.md format, have proper frontmatter, clear descriptions, and progressive disclosure. Prevents skill bloat by enforcing the "will I need this more than once?" test.
---

# Skill Creator

## When to Invoke

- The user says "create a skill", "make a skill for…", "add a skill".
- The user has entered the same prompt 3+ times (a signal it should be a
  skill).
- The user wants to encode domain expertise as a reusable capability.
- The user wants to import a community skill and customize it.

## When NOT to Invoke

- The user wants a rule (always-on constraint) → use `.trae/rules/`.
- The user wants a command (slash trigger) → use `.trae/commands/`.
- The user wants a subagent (isolated worker) → use a subagent definition.
- One-off tasks that will not recur.

## The "Will I Need This More Than Once?" Test

Before creating a skill, ask:

1. **Will I use it more than once?** If not, it is a prompt, not a skill.
2. **Is it better as a structured instruction?** If it is just a
   preference ("use 2-space indentation"), it is a rule.
3. **Is it a multi-step workflow?** If yes, a skill is appropriate.
4. **Does it encode domain expertise?** If yes, a skill is appropriate.

## SKILL.md Format

```markdown
---
name: [kebab-case-name]
description: [When to use this skill. This is what the agent sees at
  startup, used to decide whether to load the full body. Must be specific
  enough to match relevant tasks, but not so broad it matches everything.
  2-4 sentences.]
---

# [Skill Name]

## When to Invoke
- [specific trigger 1]
- [specific trigger 2]

## When NOT to Invoke
- [exclusion 1]
- [exclusion 2]

## [Core Method Section]
[Actual instructions. Be specific. Include templates, checklists,
decision trees. Vague skills get ignored.]

## Workflow
1. [step 1]
2. [step 2]
3. ...

## Principles
- [principle 1]
- [principle 2]

## Anti-Patterns
- [what not to do 1]
- [what not to do 2]
```

## Workflow

1. **Understand the requirement**: What problem does this skill solve?
   What triggers should load it? If unclear, use `AskUserQuestion`.

2. **Check existing skills**: Search `.trae/skills/` to avoid duplication.
   If a similar skill exists, suggest extending it rather than creating
   a new one.

3. **Draft the skill**:
   - Write a **specific** `description` (this is the matching key).
   - Include clear "When to Invoke" / "When NOT to Invoke" sections.
   - Provide concrete templates, checklists, or decision trees.
   - Include anti-patterns to prevent misuse.

4. **Create the skill directory and file**:
   ```
   .trae/skills/[skill-name]/
   └── SKILL.md
   ```

5. **Optional resources**: If the skill needs templates, examples, or
   reference files, add them to the skill directory:
   ```
   .trae/skills/[skill-name]/
   ├── SKILL.md
   ├── templates/
   │   └── [template-file]
   └── examples/
       └── [example-file]
   ```

6. **Verify**: Confirm the skill loads correctly, checking:
   - `name` is kebab-case and unique.
   - `description` is specific and will match the right tasks.
   - The body is executable, not vague.

## Principles

- **Be specific in the description.** The `description` field is the
  matching key. "Help with code" matches everything. "Review code for
  security vulnerabilities using the OWASP Top 10" matches the right
  task.
- **Progressive disclosure.** At startup only `name` + `description`
  load. The full body loads on demand. So the description must be good
  enough to trigger loading when relevant.
- **The body must be executable.** "Be careful about security" is
  useless. "Check for SQL injection: look for string concatenation in
  queries, verify parameterized queries are used" is executable.
- **Include anti-patterns.** Telling the agent what not to do is as
  important as telling it what to do.
- **One skill, one purpose.** If a skill does three unrelated things,
  split it into three skills.

## Anti-Patterns

- A vague description that matches too broadly (skill loads when it
  should not).
- A vague description that matches too narrowly (skill never loads).
- A skill that duplicates rule content (always-on constraints belong in
  rules).
- A skill with a vague body ("be careful", "do good work").
- A skill with no "When NOT to Invoke" section (leads to over-triggering).
- Skill bloat: creating a skill for a one-off task.
