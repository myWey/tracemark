---
id: sub-agent-scribe
status: active
---

# Sub-Agent: scribe

## Purpose

Produce **handoff documents** so a future agent (or a fresh window of the
same agent) can resume the task without re-discovering decisions.

## When to call

- Context utilization reaches ~70% (proactive).
- User pauses a multi-step task.
- A logical phase ends (discovery → design, design → implementation, ...).
- User explicitly requests "save state".

## Input contract

```yaml
task_id: string                   # spec name or task identifier
session_ulid: string              # current session id (or "new")
trigger: context-fill | user-pause | phase-end | explicit
include:
  decisions: bool                 # default true
  files_touched: bool             # default true; pulls from git diff
  open_questions: bool            # default true
  failed_attempts: bool           # default true
extra_context:                    # main agent passes anything scribe can't infer
  current_phase: string
  upcoming_step: string | null
```

## Output contract

```yaml
written_to: string                # path of handoff.md
session_ulid: string
quick_resume_prompt: string       # ready to paste into new window
warnings: [string]                # e.g. "git working tree dirty"
```

## Tools allowed

- Read across project
- Write only to `.agent/sessions/{ulid}/`
- Git read (status, log, diff)

## Tools forbidden

- Code edits
- Writing outside `.agent/sessions/`
- Modifying handoffs of other sessions

## Behavior rules

1. Use the `_template.md` structure exactly. Future agents pattern-match on
   it.
2. Section 2 (decisions) is the single most important — be specific, cite
   IDs (P{n}, ADR-{nnnn}).
3. Section 6 (don't redo) saves more time than any other. Be ruthless about
   recording dead ends.
4. Section 7 (quick-resume prompt) must be self-contained.
5. Generate ULID for new sessions; respect existing if provided.
6. If the task is clearly *complete*, set status `done` and skip section 5
   (open questions).
