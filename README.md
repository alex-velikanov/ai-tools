This repository contains development tools and practices that I use across different projects.

| What | Where |
|---|---|
| Bootstrap a project with the harness (hooks, secret/code scanning, evals, MCP config, Docker runtime for PHP/Node/DB) | [`harness/`](harness/README.md) — the `harness-init` command |
| Worked example: a new PHP + React app, step by step | [`harness/WALKTHROUGH-php-react.md`](harness/WALKTHROUGH-php-react.md) |
| My skills for Claude Code and Cursor (single source, with installer) | [`skills/`](skills/README.md) |
| The dev flow: which skill at which step, and why | [`skills/dev-flow/DEV-FLOW.md`](skills/dev-flow/DEV-FLOW.md) — or run `/dev-flow` |
| The design these implement | the baseline below |

# AI-First Dev Stack — Baseline

**Owner:** Alexander Velikanov
**Date:** August 2026
**Status:** Agreed baseline. Build from this.
**Scope:** PHP, Go, JS, front end, light DevOps. Solo developer.
**Cost:** Cursor Pro ($20/mo), Claude Pro ($20/mo). Everything else free or token-cost only.

---

## 1. Operating principles

**Generator ≠ verifier.** Never accept "correct" from the session that wrote the code — same distribution, same blind spots, and it will defend its own reasoning. Verification comes from a different model, a fresh context, or a mechanical check.

**Different model for review.** Whatever generated the code, review with something else. A different harness (Cursor → Claude Code) gives fresh context and a different tool loop, but not different weights. Set the model deliberately.

**Review the spec, not the diff.** Agent produces a plan first; you review 20 lines of intent instead of 600 lines of code. Wrong approaches are cheap to kill here and expensive to kill after implementation.

**Tests derived from spec, not implementation.** If the agent writes code then writes tests for it, the tests encode the bug and go green. Order: spec → tests → implementation, or generate tests in a session that never saw the code.

**Force coverage.** An agent told "review this branch" satisfices — it reads 9 of 40 files, finds 3 things, and reports with the same confidence it would have had reading all 40. Make it enumerate every file with a verdict. A missing file is then a visible gap.

**Adversarial pass on risky changes.** Not "review this" — *"find the input that breaks this."* Review prompts produce agreeable output; attack prompts produce failure cases.

**Blast radius over prevention.** You cannot prevent every landmine. Feature flags, small deploys, fast rollback. Deploy ≠ release.

**Evals on repeated workflows.** Any prompt you run weekly — a review template, the visual rubric — needs a handful of fixed cases you re-run when you change it. Otherwise quality drifts invisibly.

---

## 2. The stack

| Layer | Tool | Cost |
|---|---|---|
| **Code** | Cursor Pro + Superpowers | $20/mo |
| | Cursor worktrees, `/best-of-n`, `cursor-agent` CLI | included |
| **Review** | CodeRabbit IDE extension (pre-push) | free |
| | Claude Code + Superpowers (spec compliance) | plan |
| | Semgrep CE | free |
| | PHPStan / golangci-lint / tsc / Biome | free |
| **QA** | Playwright MCP (Cursor) | free |
| | Playwright Agents (Claude Code) | plan |
| | Custom visual fidelity tool | tokens |
| **Debug** | `koriym/xdebug-mcp` (PHP) | free |
| | `mcp-debugger` (Go, JS/Node, +5) | free |
| **Production** | Sentry (free tier) | free |
| | GitHub Actions cron synthetics | free |
| | Grafana + Grafana MCP *(if running Grafana)* | free |
| **Hygiene** | gitleaks, Dependabot, branch protection | free |

---

## 3. Coding

**Cursor Pro + Occasionally Claud Code**  Cursor covers what a separate terminal agent was supposed to add:

- `/worktree` — parallel agents in isolated git checkouts, built in
- `/best-of-n` — same task across multiple models, each in its own worktree, results side by side
- `cursor-agent` CLI — headless, scriptable, works in CI, git hooks, cron

**Superpowers** — installed in Cursor via the native `.cursor-plugin/`. Same skill library as elsewhere; `sessionStart` hook injects the methodology. Enforces RED-GREEN-REFACTOR, subagent dispatch, verification-before-completion, and a two-stage review (spec compliance, then code quality) where critical issues block progress.

*Unverified:* whether Cursor gets full parity on Superpowers' subagent-driven dispatch. Watch it in practice.

**Division of labour:**

| Cursor | Claude Code |
|---|---|
| Tight visual loops, frontend iteration | Delegatable, specifiable work |
| Debugging with breakpoints | Independent review passes |
| Small surgical edits, tab completion | Playwright test planning/generation/healing |
| Exploring unfamiliar code | Long multi-file refactors |

Rule of thumb: **if you can specify it, delegate it; if you have to watch it, do it in Cursor.**

**Cursor Automations** — not yet examined.

---

## 4. Review

Three layers, three failure modes, three vendors.

### 4.1 CodeRabbit IDE extension — free

Runs in VS Code, Cursor, Windsurf. **3 reviews/hour, 150 files/review, free on private repos.**

Three scopes: **all changes**, **committed only**, **uncommitted only** — plus a base-branch selector, so "committed only vs `main`" is a full branch review before a PR exists.

Findings appear inline in the editor. **"Fix with AI"** routes a finding to Claude Code, so detection comes from a corpus-tuned reviewer and remediation from an agent that can actually investigate.

Covers the two weaknesses of a DIY agent review: **corpus-tuned heuristics** (iterated against enormous PR volume — not replicable) and **mechanical coverage** (walks the diff systematically instead of satisficing).

*Caveat:* code is sent to CodeRabbit's servers, not analysed locally.

*Note:* the free tier's **PR** reviews are summary-only — full PR review moved to Pro ($24/dev/mo). The IDE reviewer is the free capability, and it sits earlier in the loop anyway.

### 4.2 Claude Code + Superpowers

The pass no commercial reviewer can do: **spec compliance.** `requesting-code-review` reviews against the *approved plan*, not against general good practice.

CodeRabbit can only ask "is this good code?" It can never ask "is this the code you asked for?" — and in an agentic workflow, plausible code that quietly solved a different problem is the dominant failure mode.

Requirements: different model from the generator, fresh context, diff-scoped, enumerate every file reviewed.

Keep `.review-log.md` in the repo — findings you dismissed and why, fed into each review. Otherwise every session re-litigates the same rejected points forever.

**Two reviews, two jobs.** The requirements above are met by two different reviewers, kept deliberately:

| | Inner loop: `requesting-code-review`, plus the per-task reviews in `subagent-driven-development` | Outer gate: `/review-code` ([`skills/review-code`](skills/review-code/SKILL.md)) |
|---|---|---|
| When | Automatically, after every task | Once, before the PR |
| Context | A fresh subagent with crafted context | A fresh session you start |
| Checks | The work against the plan, and code quality | The branch against the plan or spec, then architecture and quality |
| Different model from the author | No: the subagent can be the same model | Yes: it flags it if it is the author model |
| Every file accounted for | No | Yes: a verdict for each changed file |
| Reads `.review-log.md` | No | Yes |
| Cost | Cheap, repeated | Heavier, run once |

The inner loop catches a wrong turn while it is still cheap to undo. The outer gate supplies the two things the inner loop
structurally can't: independence from the author model and per-file accountability. So the section's requirements are
met by the pair, not by `requesting-code-review` alone.

*Watch this:* `subagent-driven-development` also runs a broad whole-branch review at the end, so the outer gate partly
overlaps it. If `/review-code` finds nothing over several PRs that the inner reviews hadn't already, that is the evidence
to drop it. Measure it with the eval set rather than guessing.

### 4.3 Semgrep CE — free, local

LGPL-2.1, no account, code never leaves your machine.

```bash
brew install semgrep      # or: pip install semgrep
semgrep --config=auto .
```

**Important limitation: CE is single-file analysis only.** Cross-file dataflow is the Pro engine. A vendor benchmark put the Platform at 72% of WebGoat vulns vs 48% for CE — discount for being vendor-run, but the direction is real.

It still earns its slot for one reason: **it is the only layer with zero variance.** LLM reviewers find different things run to run. Semgrep either has the rule or doesn't, deterministically, forever. That's the coverage guarantee agents structurally lack.

*Open:* the free AppSec Platform tier (10 contributors, 10 private repos) may include cross-file analysis and Pro rules — sources conflicted. Worth ten minutes to verify. Trade-off: cloud scanning instead of local.

**Custom rules** are free YAML and an agent can write them. Pairs with AGENTS.md:

> Agent makes the same mistake twice → **AGENTS.md line** so it stops.
> Mistake is pattern-detectable → **Semgrep rule** so you know when it does it anyway.

Instruction plus enforcement. The Semgrep rule doesn't depend on the agent having read or respected anything.

### 4.4 Eval set for the review prompt

The review prompt is software. Without regression tests you cannot tell whether a prompt edit or a model update made it better or worse — and the failure mode is silent: a reviewer that finds nothing looks identical whether the code is clean or it went blind.

**Harvest cases from your own git history.** For each `fix:` commit, take the diff of the commit that introduced the bug. You know it's real and you know exactly what it was.

```bash
#!/usr/bin/env bash
# evals/harvest.sh
set -e
mkdir -p evals/cases

git log --format=%H --grep='^fix' -30 | while read -r fix; do
  files=$(git diff-tree --no-commit-id --name-only -r "$fix")
  for f in $files; do
    intro=$(git log -1 --format=%H "$fix^" -- "$f")
    [ -z "$intro" ] && continue
    dir="evals/cases/$(git log -1 --format=%s "$intro" | tr -cs '[:alnum:]' '-' | cut -c1-40)"
    mkdir -p "$dir"
    git show "$intro" -- "$f" > "$dir/diff.patch"
    git log -1 --format='{"should_find": true, "bug": "fixed by: %s"}' "$fix" \
      > "$dir/expected.json"
  done
done
```

Blame heuristics are imperfect — refine this against your repo with an agent, then hand-edit the `bug` descriptions to be specific enough to grade against and delete the junk. Add negatives (`should_find: false`) from refactors that never got a follow-up fix.

**Aim for 10–15 cases, roughly half clean.** If everything has a bug, a reviewer that always cries wolf scores 100%. The clean cases measure false positives, which is what actually kills a reviewer — one you stop reading has no recall at all.

**Run and grade in two separate passes:**

```bash
#!/usr/bin/env bash
# evals/run.sh
set -e
MODEL=${MODEL:-sonnet}

# Pass 1 — review each case BLIND
for case in evals/cases/*/; do
  claude -p "$(cat evals/review-prompt.md)

Review this diff:
$(cat "$case/diff.patch")" --model "$MODEL" > "$case/actual.json"
done

# Pass 2 — grade everything in one invocation
claude -p 'For every directory under evals/cases/, compare actual.json
against expected.json.

A case PASSES if:
  should_find=true  AND the reviewer identified that specific bug
                    (adjacent commentary about the same file does NOT count)
  should_find=false AND the reviewer reported nothing at severity >= 3

Output a markdown table: case | expected | found | pass.
Then print recall (found/should_find) and false-positive count.
Exit non-zero if recall < 0.7 or false positives > 2.'
```

**The one thing you cannot shortcut:** the reviewer must never see `expected.json`. Two invocations, not one clever prompt — otherwise the grader's knowledge contaminates the review and everything passes.

**Automate the running:**

```yaml
# .github/workflows/eval.yml
on:
  schedule:
    - cron: '0 6 1 * *'              # monthly — catches model drift
  push:
    paths:
      - 'evals/review-prompt.md'     # any prompt edit
  workflow_dispatch:

jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./evals/run.sh
```

The monthly cron is the point — providers update models underneath you without announcement, and this is the only thing that tells you.

**Growth rule — same as AGENTS.md and Semgrep rules:**

> A bug that reaches production and your reviewer missed becomes a new eval case.

Sentry gives you the issue and the release, `git log` gives you the introducing diff, and it drops into `evals/cases/`. The set grows from real failures, in the direction your reviewer is actually weak.

Two numbers to track: **recall** (of the planted bugs, how many found) and **noise** (findings on clean diffs — want zero). Optimising one alone gives you either a reviewer that misses things or one you ignore.

The visual rubric (§7.7) needs the same treatment with its 20 screenshot pairs. Any prompt you run repeatedly and depend on needs an eval set; without one, prompt engineering is guesswork with a good feeling attached.

### 4.5 Deterministic linters

PHPStan (level 8–9), Rector, golangci-lint + `go vet` + `-race`, TypeScript strict, Biome/oxlint. Not AI, and they make the AI dramatically better — they turn "looks right" into pass/fail.

---

## 5. QA

**Playwright MCP** — in Cursor, `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"]
    }
  }
}
```

Works on the **accessibility tree**, not screenshots — structured text, deterministic, no vision model, real selectors. Defaults to headed with a persistent profile (stays logged into your app). Add `--headless --isolated` for CI.

**Keep `--caps` minimal.** 60+ tools exist; most are opt-in. Core only.

Use for ad-hoc questions: "why is this blank on mobile", selector debugging, exploring pages while building the visual tool.

**Playwright Agents** — Claude Code only:

```bash
npx playwright init-agents --loop=claude
```

`--loop=` accepts `vscode`, `claude`, `codex`, `opencode`. No Cursor loop; `--loop=vscode` generates Copilot chatmode files Cursor doesn't read.

- **Planner** → explores the app, writes markdown test plans to `specs/`. Discovers scenarios you wouldn't have specified.
- **Generator** → turns approved specs into `.spec.ts`, validating every selector against the live DOM.
- **Healer** → runs failing tests in debug mode, fixes selectors or waits, and **distinguishes a broken test from a real app bug**.

The planner → generator split is spec-first applied to tests: review markdown, not 400 lines of generated spec.

**MCP is a tool; the agents are a workflow.** Questions → MCP. Suites → agents.

### Token cost (estimates)

Accessibility snapshots dominate; MCP snapshots after nearly every action.

- Node ≈ 12–18 tokens. Rich invoice form ≈ 250 nodes ≈ **3–4k tokens/snapshot**. Login page ≈ 300–800. 50-row list ≈ 5–8k.
- **Planner** on one feature area: 25–35 actions → **~90–120k new tokens**
- **Generator**: 10–20 snapshots + code → **~40–70k**
- **Healer**: **~10–30k**

Context accumulates across turns; prompt caching absorbs most of the repeat cost, so treat the "new tokens" figure as the meaningful one.

**Levers, in order of effect:**

1. **Scope the planner.** "Explore `/invoices/new` including validation paths" — never "explore my app."
2. **Seed the dev DB small.** Three invoices, not five hundred.
3. **Plan once per area.** The spec is the artifact; regenerate tests from it without re-planning.
4. Keep `--caps` minimal.

On a subscription this is rate limits, not dollars. Budget a planner run like a substantial coding session.

---

## 6. Debugging

### 6.1 The principle

Step debugging is a **human** interface — you look, decide, step, look again, because *you* build a mental model incrementally. Agents don't work that way. Stepping an agent through forty breakpoints is slow and burns tokens on state it doesn't need.

What an agent is good at is **reading a complete record of what happened.**

So the pattern is: produce a rich artifact of the execution, hand it over. No `var_dump`, no code modification, no cleanup.

### 6.2 PHP — `koriym/xdebug-mcp`

The most developed of several Xdebug MCP servers, and it states this philosophy explicitly: it deliberately abandons interactive step debugging for one-shot batch execution returning structured JSON, because that's cheaper and better suited to an agent.

> *"No var_dump(). No code modification. No guesswork."*

```bash
composer global require koriym/xdebug-mcp
```

Requires Xdebug 3.x. Wire into `.cursor/mcp.json` like any other stdio server.

| Tool | Gives the agent |
|---|---|
| `xtrace` | Full execution flow — every call, args, return values |
| `xstep` | Variable state at a specific line |
| `xback` | Call stack at a breakpoint |
| `xprofile` | Performance bottlenecks |
| `xcoverage` | What a test actually executed |
| `xcompare` | Variable state across two runs — working vs broken |

`xcompare` has no traditional equivalent and is the one for *"works for most customers, wrong for some."*

**Worked example — "Invoice #4821 totals €240, should be €288":**

Nothing throws, no stack trace, data-dependent, hard to reproduce. Traditional loop is dump → refresh → wrong place → move it → repeat → forget to remove one.

```
→ xtrace(entry: "InvoiceCalculator::total", invoice: 4821)
← lineItems()  → [3 items, subtotal 240.00]
  applyTax()   → returns 240.00      ← unchanged
  taxRate()    → returns null

→ xstep(file: "TaxResolver.php", line: 47)
← $customer->country    = "DE"
  $customer->tax_region = null       ← never backfilled
  $this->rates          = ["DE" => 0.19, ...]
```

The lookup keys on `tax_region`, not `country`, and this customer predates the column. Confirm with `xcompare` against a working invoice. Your code was never touched.

### 6.3 Go, JS/Node, and the rest — `mcp-debugger`

DAP-based, driving real language debuggers. **Seven languages: Go, JavaScript/Node, Python, Ruby, Rust, Java, .NET.**

```bash
npx @debugmcp/mcp-debugger
```

Tools: `set_breakpoint`, `step_over`/`into`/`out`, `continue_execution`, `get_variables`, `get_local_variables`, `get_scopes`, `evaluate_expression`, `get_stack_trace`, `list_threads`, `get_source_context`, plus session management.

*Untested in Cursor* — the docs list Claude Desktop and Claude Code CLI. It's a standard stdio MCP server so it should work anywhere, but verify before relying on it.

More session-oriented than the Xdebug one (create session → breakpoints → step), so it costs more tokens per investigation. Scope it to one function, not a whole request.

**Go note:** Go's own tooling is already excellent and agent-readable via plain shell — `dlv` CLI, `go test -race`, and `pprof` all produce text an agent can read directly. Try `dlv` through the shell before adding an MCP; it may make `mcp-debugger` unnecessary for Go.

### 6.4 Frontend — already covered

Playwright MCP reads console messages (`Runtime.consoleAPICalled`) and network requests. For "why is this page blank on mobile," that's the debugger — no extra server needed.

### 6.5 Production — already covered

Sentry gives local variable values at each stack frame for production errors. Post-mortem state where Xdebug gives live state. Between them both sides of the deploy are covered.

*(Laravel, if applicable: Ray, Telescope, and Laravel Boost's Tinker tool let an agent query real application state without a debugger at all — often faster for "what does this query actually return.")*

### 6.6 What stays manual

Cursor is a VS Code fork, so Xdebug + the PHP Debug extension works normally. Keep classic stepping for when **you** need to *understand* rather than *find* — unfamiliar logic, building a mental model, the "I don't know what question to ask yet" state. That's why "debugging with breakpoints" sits in the Cursor column of §3.

### 6.7 Two warnings

**Trace size is the token trap.** A full PHP request trace is thousands of calls. Unscoped, you dump an enormous artifact into context — the same lesson as scoping the Playwright planner. Trace a specific entry point, never the whole request.

**Security.** These are third-party MCP servers that execute code in your application's context, with your database credentials in scope. **Local dev only, never production.** Read the package before installing — this is not a category where you install the first search result.

---

## 7. Visual fidelity tool

### Why custom

Nothing affordable does semantic comparison. Percy, Argos, Chromatic, BackstopJS all do **pixel diff + ignore regions** — the discount changing 20% → 25% lights up pink, and you hand-maintain masks forever.

Applitools' Layout match level does exactly what's wanted, but its free tier is **50 test units/month** (one page = one unit) — a single 50-page run. Paid is ~$200–500/mo, annual contract. Autonoma is semantic too, cloud from $499/mo.

**The key reframe:** pixel diff answers *what changed*. The rubric answers *does it matter*. You're not using AI to see the difference — `pixelmatch` does that better and free. You're using it to classify the difference against a policy.

### Architecture

Three instruments, three failure classes:

| Layer | Answers | Cost |
|---|---|---|
| Pixel diff | *Where* did anything change? | free — gates everything below |
| DOM text diff | Copy changed? Content missing? | free — catches what vision misses |
| VLM judge | Is the change **broken**? | tokens, only on changed pairs |

Pixel diff typically eliminates ~80% of pages before anything costs money.

### 7.1 `pages.json`

```json
["/", "/pricing", "/blog", "/invoices", "/invoices/new"]
```

### 7.2 `shoot.mjs` — capture

```js
import { chromium } from 'playwright';
import fs from 'fs';

const base  = process.env.BASE_URL;
const out   = process.env.OUT;
const pages = JSON.parse(fs.readFileSync('pages.json'));

const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width: 1440, height: 900 },
  reducedMotion: 'reduce',
});
const page = await ctx.newPage();
fs.mkdirSync(out, { recursive: true });

for (const p of pages) {
  await page.goto(base + p, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);

  const slug  = p.replace(/\W+/g, '_') || 'home';
  const h     = await page.evaluate(() => document.body.scrollHeight);
  const tiles = Math.min(Math.ceil(h / 900), 6);

  for (let i = 0; i < tiles; i++) {
    await page.evaluate(y => window.scrollTo(0, y), i * 900);
    await page.waitForTimeout(300);
    await page.screenshot({ path: `${out}/${slug}__${i}.png` });
  }
}
await browser.close();
```

**Tiling instead of `fullPage` is critical.** A 6,000px screenshot downscales to mush and the model returns a confident `pass` because it literally cannot see anything.

### 7.3 `filter.mjs` — pixel pre-filter

```js
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';
import fs from 'fs';

const all = fs.readdirSync('baseline');
const changed = [];

for (const f of all) {
  if (!fs.existsSync(`current/${f}`)) { changed.push(f); continue; }
  const a = PNG.sync.read(fs.readFileSync(`baseline/${f}`));
  const b = PNG.sync.read(fs.readFileSync(`current/${f}`));
  if (a.width !== b.width || a.height !== b.height) { changed.push(f); continue; }
  const d = pixelmatch(a.data, b.data, null, a.width, a.height, { threshold: 0.1 });
  if (d > a.width * a.height * 0.001) changed.push(f);
}

fs.writeFileSync('changed.json', JSON.stringify(changed, null, 2));
console.log(`${changed.length} changed of ${all.length}`);
```

### 7.4 `rubric.md` — the actual product

```md
Compare BEFORE and AFTER screenshots of the same page across a deploy.
Decide whether AFTER is BROKEN in a way a real user would notice.
Do not list differences — judge them.

IGNORE — expected variation, never a finding:
- Content values: prices, discounts, counts, dates, timestamps, usernames
- Different items in feeds, lists, carousels, "related" blocks
- A/B variants and personalization
- Antialiasing, sub-pixel shifts, minor font rendering differences

FLAG — regressions:
- Layout: overlap, misalignment, elements off-center or off-screen,
  collapsed or exploded containers
- Missing: nav, CTA, footer, images that failed to load, blank regions
- Styling: unstyled text, wrong font, lost background, broken grid
- Wrong content: lorem ipsum, placeholder text, error messages,
  stack traces, debug output, imagery inconsistent with the page
- Text: overflow, truncation, clipping, illegible contrast

SEVERITY:
5 page unusable (blank, error page, total layout collapse)
4 primary function broken (nav gone, CTA missing, form unusable)
3 visible breakage (overlap, off-center, text clipped, image failed)
2 cosmetic (spacing, minor misalignment)
1 trivial, probably rendering noise
0 no meaningful change

If uncertain: include it, confidence "low", severity <= 2.
An empty findings array is a correct answer. Never invent findings.

Return only JSON:
{ "verdict": "pass"|"fail", "severity": 0-5,
  "findings": [{ "what": "...", "where": "...", "confidence": "high"|"low" }] }
```

Two clauses do real work: **"do not list differences — judge them"** and **"never invent findings."** Without the second you get a steady drip of imagined regressions and stop trusting it inside a week.

Keep **two rubrics**: a strict one for local (seeded data, little legitimate variation) and this tolerant one for staging/prod.

### 7.5 `vr.sh` — runner

```bash
#!/usr/bin/env bash
set -e
[ -d current ] && rm -rf baseline && mv current baseline
OUT=current BASE_URL=$1 node shoot.mjs
node filter.mjs
claude -p "Read rubric.md. For each filename in changed.json, compare \
baseline/<file> against current/<file> and apply the rubric. Write \
report.json as [{file, verdict, severity, findings}]. Print a summary \
line. Exit non-zero if any severity >= 3."
```

```bash
./vr.sh https://prod.example.com   # before deploy
# ...deploy...
./vr.sh https://prod.example.com   # after — compares against before
```

Claude Code reads the PNGs with its own Read tool. No API key, no base64, billed against the plan.

### 7.6 Gotchas

- **Resolution** — tile, never `fullPage`. The silent killer.
- **Determinism** — fixed viewport, reduced motion, wait for fonts *and* network, freeze `Date.now()` where possible. Every source of nondeterminism is a pair you pay to look at.
- **Positional imprecision** — ask for regions ("header, right side"), never coordinates.
- **Subtle copy changes** — vision misses these. Run a DOM text diff alongside.
- **Nondeterminism** — temperature 0 narrows run-to-run variance, doesn't close it.

### 7.7 Calibration

Build ~20 labelled pairs: 10 fine (price changed, new blog post, different hero), 10 broken (nav missing, text overflowing, unstyled page, 404 image). Run the rubric, count false positives and negatives, edit, re-run. Two or three iterations gets something usable.

Then when you change models, re-run the same 20 and know immediately whether it got better or worse.

**Smoke test before trusting it:** capture a baseline, delete a CSS file, confirm it catches it. Then run twice with no changes and confirm it returns clean.

### 7.8 Scale-up path

If volume grows: switch to the Anthropic API with base64 images (cents per run, parallelisable, doesn't compete with interactive work), and two-tier the model — cheap vision screens everything, strong model adjudicates flagged pairs.

---

## 8. Production

### Sentry — free tier. Do this early, not "later."

**5,000 errors/month, 1 user, 30-day retention.** Covers more of the post-deploy problem than everything else combined, in about 30 minutes.

**Release tracking is the point.** Tag deploys with a commit SHA and Sentry tells you, per issue, *"first seen in release `a3f9c21`"* — plus suspect commits with `set-commits --auto`. That's the dormant landmine solved: it goes off on day four, and you still know which deploy planted it.

```bash
sentry-cli releases new "$GIT_SHA"
sentry-cli releases set-commits "$GIT_SHA" --auto
sentry-cli releases finalize "$GIT_SHA"
```

**Quota trap — configure before pointing production at it.** 5,000 *events*, not issues. One exception in a loop eats it in an hour and you're blind for the month.

- `sample_rate` < 1.0 on high-traffic paths
- `ignore_errors` for known noise (bot 404s, aborted requests, extension errors)
- Per-key rate limit in project settings — the hard backstop
- `traces_sample_rate: 0` unless you want performance data

**Environments:** DSN unset locally (you're already looking at the error, and local noise would eat the quota). **Staging and production only** — staging is the environment nobody watches, which is exactly where errors hide.

**Upload source maps** or frontend traces are minified gibberish:

```bash
sentry-cli sourcemaps upload --release "$GIT_SHA" ./dist
```

**Sentry MCP** — official remote server, OAuth, no Docker:

```json
{ "mcpServers": { "sentry": { "url": "https://mcp.sentry.dev/mcp" } } }
```

Then: *"Read Sentry issue PROJ-4821 and fix it."* That's the free version of Seer — Seer itself is $40/contributor as an add-on to Business ($80/mo), ~$120/mo floor. Not worth it when you have an agent that can investigate.

*Verify the MCP works on the free plan before relying on it.*

### Post-deploy smoke tests — free

A critical-path Playwright subset run against staging after deploy, then prod after promotion. Fail → automatic rollback. A CI step, not a product.

### Scheduled synthetics — free

Smoke tests run once; the dormant landmine needs something that keeps checking.

```yaml
on:
  schedule:
    - cron: '0 * * * *'   # hourly
jobs:
  synthetic:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npx playwright test --grep @smoke
        env:
          PLAYWRIGHT_BASE_URL: https://example.com
```

**Actions minutes math (private repos):** 2,000 free/month. A 2-minute suite hourly ≈ 1,440 min — fits. Every 15 minutes ≈ 5,800 — doesn't. Hourly is the free ceiling.

Checkly is the purpose-built alternative (~$80/mo Team; free tier is evaluation-only). Revisit only if you need sub-minute detection.

### Grafana + Grafana MCP

**Only if you actually run Grafana.** Error rate and latency percentiles by endpoint, alerting on symptoms rather than up/down. Catches degradation that never throws — the class Sentry can't see. The MCP lets an agent query real metrics while debugging.

### Blast radius

Feature flags, small deploys, canary or percentage rollout, instant rollback. Costs nothing but discipline, and it's the only thing that makes landmines survivable rather than merely detectable.

### Staging with production-shaped data

An anonymized prod snapshot. Most "works locally" bugs are data bugs — this converts a whole failure class into something existing tests catch.

---

## 9. Hygiene

**Secrets scanning.** `gitleaks` or Semgrep secret rules in a pre-commit hook. Ten minutes. Agents commit `.env` files and paste keys into fixtures — worst blast radius of any mistake on this list.

**Dependabot or Renovate.** Free on GitHub. Your stack reviews the code *you* write while dependencies rot independently. Also feeds the review layer useful low-stakes work.

**Branch protection on `main`.** Two minutes. Require PR, require checks, disallow force-push. The only guardrail that doesn't depend on your config discipline or an agent's cooperation — server-side rules can't be talked around.

**Agent permissions.** Decide what you auto-approve for shell access. Not a product, a config decision. Still open.

---

## 10. Context files

### Global — `~/.claude/CLAUDE.md`, Cursor global rules

Things true of **you**, never of a project. Under 25 lines; it loads every session in every project.

```md
# Working preferences
Terse. No preamble. Show the diff, not a description of it.
Explain only when I ask or when the approach is non-obvious.

# Before acting
Plan before any refactor touching >3 files. I approve the plan, then you build.
Never commit or push unless I ask.
Never add a dependency without asking.
Never run destructive commands (drop, force-push, rm -rf) without confirming.

# Verification
Don't claim something works until you've run it and seen it pass.
"Should work" is not done. If you can't verify, say so.

# Code review
When reviewing code, use a different model than the one that wrote it.
Report only correctness, security, and performance. Not style.
Finding nothing is a valid result — don't manufacture findings.
```

### Per-project — `AGENTS.md`

Not part of general setup; goes on the **new-project checklist**. Symlink so every tool finds it:

```bash
ln -s AGENTS.md CLAUDE.md
```

Superpowers supplies *methodology*; AGENTS.md supplies *project facts* — it can't know your test command, your architecture, or that `legacy/` is off-limits.

Start minimal and grow from observed failures:

```md
# Commands
Test:  vendor/bin/pest
Lint:  vendor/bin/pint
Serve: php artisan serve

# Structure
Domain logic in src/Domain — no framework imports there.
HTTP layer in src/Http. Never put business logic in controllers.

# Rules
Never edit files in legacy/ — deprecated, being removed.
Migrations must be expand-contract; we deploy before migrating.

# CI
Check CI with `gh pr checks <n>`, then `gh run view <id> --log-failed`.
Never fetch full logs — 30k+ lines of setup noise.
```

**Growth rule:** when an agent makes the same mistake twice, that's a new line. Every entry derived from an observed failure, so the file stays short and every line is load-bearing. Keep under ~150 lines — it competes with your code for context.

**A stale AGENTS.md is worse than none.** An agent that trusts a wrong test command burns more time than one that asks.

---

## 11. Rejected, with reasons

| Rejected | Why |
|---|---|
| **Second paid agent** (Claude Code sub, Codex) | Cursor's `/worktree`, `/best-of-n`, and `cursor-agent` CLI already cover parallelism, delegation, and headless scripting. Revisit only on a specific trigger: consistently hitting quota, or a named task class Cursor's harness underperforms on. |
| **GitHub MCP** | `gh` covers CI logs and PR diffs, costs **zero context tokens until used**, and composes with grep/jq. The MCP's default toolset is ~26 tools / ~4.2k tokens **every turn**. Three lines in AGENTS.md buy most of the value. Add later only for inline review comments, a `--read-only` surface for unattended agents, or shell-less cloud agents. |
| **Greptile** | Moved to **$30 + $1/review after 50**. ~42 PRs/dev before overage; ~$339/seat at 300 PRs. Per-review pricing directly taxes an agentic workflow that increases PR count. Its zero-false-positive precision is real and irrelevant under that model. |
| **Cursor Bugbot** | Usage-based since May 2026, billing **from your included Pro usage at ~$1.00–1.50/run**. 15 PRs/month ≈ your whole $20 balance. The real cost is opportunity cost — every review is an agent task you didn't run. Prose-only findings when you already have an agent that can fix things. Reconsider for a team, or if you'd genuinely skip the pre-push review. |
| **Sentry Seer** | $40/active contributor, add-on to **Business** ($80/mo) → ~$120/mo floor. Sentry free + MCP + Claude Code gives the same loop manually. |
| **Percy / Argos as primary** | Pixel diff with ignore regions. Every price, date, and feed item lights up. Percy also multiplies cost by browser × viewport (1 page × 3 × 3 = 9 billed) and re-renders serialized DOM in their cloud, which can diverge from what your test displayed. Argos free (5k/mo, local capture, agent-readable CLI) is the better of the two if used at all. Percy still uniquely offers **cross-browser rendering from one call** and a **no-code CLI path** (`percy snapshot ./dist` or a sitemap). Optional scaffold to learn your noise profile. |
| **Applitools / Autonoma** | Correct category — semantic comparison. Applitools free = 50 test units/month = one 50-page run. Paid ~$200–500/mo annual, or $499/mo. Priced for enterprise QA teams. |
| **Checkly** | Right tool for synthetics; free tier is evaluation-only, Team ~$80/mo, browser checks are the expensive kind. GitHub Actions cron does it free at hourly resolution. |

---

## 12. Open questions

**Blocking a decision already made:**

- **Public or private repos?** CodeRabbit's **Open Source plan is free Pro+** for qualifying public projects — full reviews, test generation, planning. If any repo is public, the review layer changes materially.

**Affects tool selection:**

- **Laravel, or plain PHP / Symfony?** Decides whether **Laravel Boost** is the single best MCP available (version-correct docs, your schema, Tinker access) or irrelevant.
- **Do you already run Grafana?** Grafana MCP earns its slot only if yes.

**To verify:**

- Does the **free Semgrep AppSec Platform tier** (10 contributors, 10 private repos) include cross-file analysis and Pro rules? Sources conflicted.
- Does **Sentry MCP** work on the free plan?
- Does **Superpowers' subagent-driven dispatch** reach parity in Cursor?
- **Cursor Automations** — not examined at all.

---

## 13. Setup order

**Week 1 — free, fast, high leverage**

1. Global rules file (`~/.claude/CLAUDE.md`, Cursor global rules) — 20 min
2. Semgrep CE + a pre-commit hook — 20 min
3. gitleaks in the same hook — 10 min
4. Branch protection on `main` — 2 min
5. Dependabot — 5 min
6. CodeRabbit IDE extension — 10 min
7. Sentry: project, SDK, **rate limits first**, release tagging — 30 min

**Week 2 — the workflow**

8. Playwright MCP in `.cursor/mcp.json`
9. `npx playwright init-agents --loop=claude` on one project
10. Run the planner on **one** feature area; review the spec; generate
11. First Claude Code review pass with an explicitly different model
12. Start `.review-log.md`
13. Eval set: `evals/harvest.sh`, curate ~12 cases, wire the monthly CI job
14. Debug MCPs — `koriym/xdebug-mcp` for PHP; try `dlv` via shell for Go before adding `mcp-debugger`

**Week 3 — the visual tool**

13. Scaffold `pages.json`, `shoot.mjs`, `filter.mjs`, `rubric.md`, `vr.sh`
14. Build the 20-pair calibration set
15. Tune the rubric until false positives and negatives are acceptable
16. Wire into the deploy script
17. *(Optional)* Percy free on 10 pages for a week to learn the noise profile

**Later**

18. Post-deploy smoke suite + auto-rollback
19. GitHub Actions cron synthetics (hourly)
20. Feature flags
21. Prod-shaped staging data
22. Grafana + MCP, if applicable

**Per new project**

- `AGENTS.md` + `CLAUDE.md` symlink
- Project-scoped `.cursor/mcp.json`
- Linter config (PHPStan / golangci-lint / tsc / Biome)
- Semgrep custom rules as failures accumulate