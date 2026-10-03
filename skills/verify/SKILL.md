---
name: verify
description: Phase-gate check — run the scoped tests and builds, record one line of evidence per check, and stop if anything fails or can't be verified. Invoke explicitly with /verify.
disable-model-invocation: true
---

Verify the current change. **You run every command. Do not hand verification back to me.**

This builds on `superpowers:verification-before-completion` (no claim without fresh evidence). That rule always applies. This skill adds the gate and the report below.

## What this adds

- **Scope:** run the tests and builds for **this change**, not the full suite.
- **Read the output.** A zero exit code is not a pass. A run with skipped, risky or incomplete tests is **not** a pass. Say so.
- **Unverifiable things:** if something cannot be verified automatically, say that explicitly rather than assuming it works.

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

If anything failed or could not be verified, say so plainly and **stop**. Do not proceed and mention it in passing.
