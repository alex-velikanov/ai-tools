---
name: dev-flow
description: Navigator for the dev workflow — inspect the repo, say which step I'm on, and name the next skill to run and why. Read-only. Invoke explicitly with /dev-flow.
disable-model-invocation: true
---

Tell me where I am in the dev flow and what to do next. **Read-only: do not edit files, commit, or run the next skill yourself** unless I ask.

1. Read `DEV-FLOW.md` in this skill's directory (the same folder as this file). It is the source of truth for the steps and the reasons. Do not rely on memory of it.

2. Inspect the repo, and say what you could not check:
   - `git branch --show-current`, `git status --short`, and the diff against the merge base (is there code yet?)
   - latest file in `docs/superpowers/specs/` and `docs/superpowers/plans/` (is there an approved spec? a plan? are its steps checked off?)
   - `lefthook.yml` and `AGENTS.md` (is the harness applied? does `AGENTS.md` still contain `TODO`?)
   - `.review-log.md` (any dismissed findings?)

3. If I described a task, classify it as a feature, a small change, or a bug, and use the matching path from `DEV-FLOW.md`.

4. Answer in this shape, briefly:
   - **You are at step N: <name>.** The evidence for that, one line each.
   - **Next:** the exact skill or command, and the one-sentence reason from the doc.
   - **Skip or shortcut:** only if the doc's path for this kind of task allows it.
   - **Not verifiable from the repo:** anything you had to assume (for example whether tests last passed).

If the state is ambiguous, say what is ambiguous and ask one question instead of guessing.
