---
name: cleanup
description: Style and clean-up pass over branch changes only, then runs the scoped tests.
---

Clean up the code added or changed **on this branch**, via `git diff` against its merge base.
If you cannot produce a diff, **stop and tell me**.

**Scope: only what ships.** Do not refactor unrelated legacy code. Ignore git-ignored helpers and throwaway test directories unless I say otherwise.

## Checklist — new and changed code only

- Imports instead of fully-qualified names; imports sorted
- **No descriptive comments** unless the code is genuinely non-obvious — and then *why*, not *what*
- Docblocks/type annotations accurate where present; match the file's existing strictness
- Remove unused parameters and variables
- Magic numbers and strings → named constants, where it aids clarity
- Extract duplicated logic where it clearly helps — not for its own sake
- Remove redundant null / isset / empty checks
- Tests: up to date, no redundant assertions, scoped to what this feature needs
- Format to the project's standard

## After cleanup

Run **only the tests for this feature**, not the whole suite.

Read the output — do not trust the exit code alone. A green exit with skipped, risky, or incomplete tests is not a pass.

Iterate until clean. You run the commands; do not hand them back to me.

## Finish

Short summary of the most significant changes. Flag anything you were unsure about or deliberately left alone.
