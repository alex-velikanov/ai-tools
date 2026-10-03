# Dev flow

How a task goes from "I have an idea" to "merged", which skill or tool does each step, and why.
It combines Superpowers (installed as a plugin in both tools) with my own skills and the harness.

Principles it enforces (from the baseline README): the session that wrote the code never
certifies it; review the spec, not the diff; tests come from the spec; a reviewer must account for
every file; anything repeated weekly gets an eval.

## Pick the path first

| Task | Path |
|---|---|
| New app or feature (anything with design choices) | **Full flow** below |
| Small, well-understood change | `brainstorming` still runs, but only as a short design in chat and a yes from you; then TDD. No plan document |
| A bug | `systematic-debugging` (root cause before any fix). For PHP bugs that don't throw, add the Xdebug MCP (`xtrace`) |
| A throwaway spike | `brainstorming` handles it; nothing is kept |

## The full flow

| # | Step | Tool | Why this step exists | Done when |
|---|---|---|---|---|
| 0 | Set up the project (once) | `harness-init` | Hooks, secret scanning, evals and `AGENTS.md` exist before any code does | `lefthook.yml` present; first commit passed the hooks |
| 1 | Brainstorm | `superpowers:brainstorming` | Turns a vague task into an approved design. It asks one question at a time, proposes 2-3 approaches, and refuses to write code until you say yes | A spec in `docs/superpowers/specs/` that you approved |
| 2 | Plan | `superpowers:writing-plans` | Spec becomes ordered tasks with real commands and files, so "done" is checkable | A plan in `docs/superpowers/plans/` |
| 3 | Attack the plan | `/critique-plan` (mine) | A wrong approach is cheap to kill here and expensive after coding. Superpowers writes plans but nothing argues against them | You've decided what changes; the plan is updated |
| 4 | Build | `superpowers:subagent-driven-development` + `test-driven-development` | A fresh agent per task, tests written from the spec first, a spec-and-quality review after each task | Every plan task done, tests green |
| 5 | Gate each phase | `/verify` (mine) | One line of evidence per check. Skipped tests are not a pass. Stops you moving on while something is red or unverifiable | Every check has a quoted result |
| 6 | Tidy | `/cleanup` (mine) | Style pass over this branch only, then just this feature's tests | Clean diff, scoped tests green |
| 7 | Independent review | CodeRabbit, then `/review-code` (mine) | Two different reviewers on top of the one that wrote the code. See "Reviews" below | Every changed file has a verdict; findings triaged |
| 8 | Finish | `superpowers:finishing-a-development-branch` | Presents the options (merge locally, push and open a PR, or keep as-is; discard only on request) and waits for your choice | Your choice is carried out |
| 9 | After deploy | `vr/vr.sh`, Sentry | Catches what review can't: what users actually see, and what throws in production | Visual run clean; no new Sentry issues |

Steps 5 and 6 repeat as needed. Anything that fails sends you back to step 4.

## Who does what: Cursor or Claude Code

From the baseline README: **if you can specify it, delegate it; if you have to watch it, do it in Cursor.**

| Cursor | Claude Code |
|---|---|
| Tight visual loops, frontend iteration | Delegatable, specifiable work (steps 2-4 for a clear plan) |
| Debugging with breakpoints, the Xdebug MCP | Independent review passes (step 7) |
| Small surgical edits, exploring unfamiliar code | Playwright test planning, generation and healing |
| | Long multi-file refactors |

Skills work in both. Steps 1-3 are the same in either tool.

## Reviews: who covers what

Four reviewers exist. They don't duplicate each other:

| Reviewer | When | What it adds |
|---|---|---|
| Semgrep (hook) | Every commit | Zero-variance rules, nothing leaves the machine |
| `requesting-code-review` and the reviews inside `subagent-driven-development` | After each task, automatic | Checks the work against the plan, cheaply, in a fresh subagent. Same model family as the author |
| CodeRabbit (Cursor, "committed only" vs `main`) | Before pushing | A different vendor, tuned on a huge PR corpus. Code goes to its servers |
| `/review-code` | Once, before the PR, in a fresh session on a **different model** | Independence, a verdict for every file, spec compliance, and it reads `.review-log.md` so dismissed findings aren't re-raised |

Anything you review and dismiss goes in `.review-log.md` with a reason.

`/verify` and `superpowers:verification-before-completion` also layer rather than overlap: the Superpowers
one is a standing rule (never claim success without fresh evidence); `/verify` is the explicit gate and
the evidence report.

## Worked example: a PHP invoicing app like the fixture

Task: "PHP domain model for invoices: customers, line items, per-country VAT, an invoice total."
This is illustrative; it shows what each step produces, not a transcript.

0. `harness-init . --php --web --install` in the new repo.
1. `brainstorming` asks about VAT rules, rounding, and customers who predate any new field, offers approaches, and writes
   `docs/superpowers/specs/<date>-invoicing-design.md`. You read it and say yes.
2. `writing-plans` turns the spec into tasks: `Customer`, `LineItem`, `TaxResolver`, `InvoiceCalculator`, each with a test command.
3. `/critique-plan` asks "what are we assuming that might not be true?" The plan assumes every customer has a
   `tax_region`; customers created before that column won't. That is exactly the bug the fixture's history seeds in `TaxResolver`.
   Better to catch it here than in production.
4. `subagent-driven-development` builds each class test-first, with a review after every task.
5. `/verify`: `PHPUnit OK (n tests), 0 skipped`, `PHPStan clean`. Nothing proceeds on a skipped test.
6. `/cleanup` for the diff only.
7. CodeRabbit on the branch, then a fresh session on a different model: `/review-code`. It reads the spec, reports each
   requirement as met, partial, missing or deviation, and gives a verdict per file.
8. `finishing-a-development-branch` → push and open a PR.
9. Deploy to staging, run `vr/vr.sh` before and after, watch Sentry.

If a bug still reaches production: add it as an eval case, add an `AGENTS.md` line if an agent made the same mistake
twice, and a Semgrep rule if the mistake is detectable by pattern.

## Honest limits

- This sequence has not yet been run end to end on a real task; each skill has been checked on its own.
- Whether Cursor matches Claude Code on Superpowers' subagent dispatch is still an open question from the baseline README.
- CodeRabbit (step 7) and the Sentry and GitHub parts are manual.
