---
name: verify
description: Prove the work is done with concrete evidence per check, not claims.
---

Verify the current change. **You run every command. Do not hand verification back to me.**

## Rules

- Run the tests and builds relevant to **this change**, not the full suite.
- **Read the output.** A zero exit code is not a pass.
- A run with skipped, risky, or incomplete tests is **not** a pass. Say so.
- If something cannot be verified automatically, say that explicitly rather than assuming it works.
- "Should work" is not done.

## Evidence

Record **one line of evidence per check**. Concrete and quotable:

```
PHPUnit    OK (12 tests, 42 assertions), 0 skipped
Jest       14 passed, 0 skipped
Build      succeeded, bundle mtime changed
Lint       clean
```

Not: "tests pass", "everything looks good", "the build works".

## Plan tracking

If working from a plan file:

- Check off each completed step
- Note what you did and any decisions you made
- Flag anything you were uncertain about

## Gate

Do not move to the next phase until this one's scoped tests and builds pass under the rules above.

If anything failed or could not be verified, say so plainly and stop. Do not proceed and mention it in passing.
