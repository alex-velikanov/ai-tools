---
name: critique-plan
description: Adversarially review a plan before implementation starts. Argues against the plan rather than affirming it.
---

Review the plan. **Argue against it — do not only affirm it.**

## Per phase

- What is the most likely way this goes wrong?
- What are we assuming that might not be true?
- What edge cases or failure modes are missing?
- Does the verification step name **real commands and files**, or is it hand-wavy?

A phase whose "done condition" cannot be checked mechanically is not a phase.

## Cross-checks

- **Task drift** — does the plan still match the original request, or did scope creep in?
- **Architecture, security, performance** — auth boundaries, input validation, credentials in logs, cache invalidation, anything hard to undo later.
- **Blast radius** — which steps are irreversible, and is that acknowledged?
- **Testing scope** — does it avoid "run all tests" when a feature subset would do?
- **Assumptions about the codebase** — are entry points, class names, and flows verified against source, or guessed?

## Output

Concrete gaps, wrong assumptions, and missing steps. A problem found here is far cheaper than one found during coding.

If the plan is sound, say so briefly — but still name the top residual risks.

Do not fix the plan in this pass. List problems; I decide what changes.
