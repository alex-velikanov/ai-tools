# Walkthrough: a new PHP + React app, with the harness

A start-to-finish example. The app is called **shop**: a PHP backend in `backend/` and a
React (Vite) frontend in `frontend/`. Everything marked ✅ was run on a scratch project while
writing this; steps marked ⚠️ were not run here and are described from the docs.

The harness gives the project: git hooks (gitleaks + Semgrep), a PHPStan config, PHPUnit
config, Playwright config and MCP servers, an eval harness for your review prompt, a visual
regression tool, Dependabot, and an `AGENTS.md` for agents. It never commits or pushes, and
never overwrites a file you've edited.

---

## 0. One-time machine prerequisites

Already installed on this machine. To check on another one:

```bash
semgrep --version && gitleaks version && lefthook version      # brew install semgrep gitleaks lefthook
php -v && composer --version                                   # brew install php composer
composer global config bin-dir --absolute                      # xdebug-mcp lives here
ls "$(composer global config bin-dir --absolute)/xdebug-mcp"   # composer global require koriym/xdebug-mcp
node -v && npm -v && claude --version && command -v harness-init
```

`harness-init` prints this same check (the "Tools" block) on every run, with the install
command for anything missing.

Skills are a per-machine install too, not per project (they're used from step 5 on):

```bash
~/Documents/DEV/TOOLS/skills/install.sh     # links my skills into ~/.claude/skills (Claude Code and Cursor both read it)
```

---

## 1. Create the two apps ✅

The harness adds tooling around your code; it doesn't generate the app. Make the skeleton
first (or use your existing repo and skip to step 2).

```bash
mkdir -p ~/Documents/DEV/shop/backend && cd ~/Documents/DEV/shop/backend

composer init --name=acme/shop --type=project --autoload=src/ --no-interaction
composer require --dev phpunit/phpunit
mkdir -p src tests

cd ..
npm create vite@latest frontend -- --template react-ts
cd frontend && npm install && cd ..
```

PHP tests that live in a namespace need `autoload-dev`. Add this to `backend/composer.json`
and run `composer dump-autoload` (skip if your tests aren't namespaced):

```json
"autoload-dev": { "psr-4": { "Acme\\Shop\\Tests\\": "tests/" } }
```

Add a first class and a test so there's something to run:

```php
// backend/src/Cart.php
<?php
declare(strict_types=1);
namespace Acme\Shop;

final class Cart
{
    /** @var list<float> */
    private array $prices = [];
    public function add(float $price): void { $this->prices[] = $price; }
    public function total(): float { return array_sum($this->prices); }
}
```

```php
// backend/tests/CartTest.php
<?php
declare(strict_types=1);
namespace Acme\Shop\Tests;

use Acme\Shop\Cart;
use PHPUnit\Framework\TestCase;

final class CartTest extends TestCase
{
    public function testTotalSumsPrices(): void
    {
        $cart = new Cart();
        $cart->add(10.0);
        $cart->add(5.5);
        $this->assertEqualsWithDelta(15.5, $cart->total(), 0.001);
    }
}
```

---

## 2. Apply the harness ✅

Always look before you write:

```bash
cd ~/Documents/DEV/shop
harness-init . --php=backend --web=frontend --dry-run
```

The `--php=backend` / `--web=frontend` flags say *where each stack lives*. Leave the value off
(`--php`) if the stack is at the project root. The dry run lists every file it would create,
and writes nothing. Then for real:

```bash
harness-init . --php=backend --web=frontend --install
```

`--install` is the only part that adds dependencies to your project. It runs:
`composer require --dev phpstan/phpstan` (in `backend/`), `npm i -D @playwright/test` plus the
Chromium browsers, `npx playwright init-agents --loop=claude`, and `npm install` in `vr/`.
Drop the flag to get just the files, and run those commands yourself later (they're printed).

### What you now have

| Path | What it is |
|---|---|
| `lefthook.yml` | pre-commit: gitleaks on staged changes + Semgrep on staged PHP/JS/TS/Go. Semgrep retries once if it segfaults. pre-push: CodeRabbit reminder |
| `.semgrepignore` | skips `vendor/`, `node_modules/`, `dist/`, `build/` |
| `backend/phpstan.neon.dist` | PHPStan level 6 over `src/` |
| `backend/phpunit.xml.dist` | bootstraps `vendor/autoload.php`, runs `tests/` |
| `frontend/playwright.config.ts` | base URL `http://localhost:5173`, auto-starts `npm run dev` |
| `frontend/.claude/agents/`, `frontend/seed.spec.ts`, `frontend/specs/` | Playwright planner / generator / healer agents, from `init-agents` |
| `.cursor/mcp.json` | `xdebug` (traces PHP) and `playwright` (drives a browser) MCP servers |
| `evals/` | `harvest.sh`, `run.sh`, `review-prompt.md`, empty `cases/` |
| `.github/workflows/eval.yml` | runs the evals monthly and when `review-prompt.md` changes |
| `.github/dependabot.yml` | composer (`/backend`), npm (`/frontend`), github-actions; 7-day cooldown |
| `vr/` | visual regression tool: `pages.json`, `rubric.md`, `shoot.mjs`, `filter.mjs`, `vr.sh` |
| `AGENTS.md` + `CLAUDE.md` | project facts for agents; `CLAUDE.md` is a symlink |
| `.review-log.md` | where dismissed review findings get recorded |
| `.gitignore` | harness lines appended (vendor, node_modules, vr output, ...) |

It also ran `git init -b main` and `lefthook install`. **Nothing is committed.**

---

## 3. Check each piece works ✅

```bash
cd backend
vendor/bin/phpunit                                   # OK (1 test, 1 assertion)
vendor/bin/phpstan analyse -c phpstan.neon.dist      # [OK] No errors
cd ../frontend
npx playwright test                                  # seed test passes
cd ..
```

Prove the secret hook blocks a real-looking key. (Don't use `AKIAIOSFODNN7EXAMPLE` — it's
AWS's published docs placeholder and gitleaks deliberately ignores it.)

```bash
printf 'AWS_SECRET_ACCESS_KEY="AKIA%s"\n' ZZQ3DG7KL2MN9XPQ > leak.txt   # a made-up key, built at runtime
git add leak.txt && git commit -m "should fail"       # blocked by gitleaks, exit 1
git reset leak.txt && rm leak.txt
```

Then the first real commit. Hooks run on it (about 6 seconds for Semgrep):

```bash
git add -A
git commit -m "chore: initial commit with harness"
```

If Semgrep reports a finding, that's the hook doing its job: fix it, or suppress a deliberate
one inline with a reason, e.g. `// nosemgrep: <rule-id>` **on the same line** as the finding.

---

## 4. Write the real `AGENTS.md`

The harness generated the **Commands** section from your stacks. The **Structure** and
**Rules** sections are `TODO`, because only you know them. Fill in facts, not wishes:

```md
# Commands
PHP test:  cd backend && vendor/bin/phpunit
PHP lint:  cd backend && vendor/bin/phpstan analyse -c phpstan.neon.dist
...

# Structure
Domain logic in backend/src/Domain — no framework imports there.
HTTP layer in backend/src/Http. No business logic in controllers.
Frontend talks to the backend only through frontend/src/api/.

# Rules
Never edit files in backend/legacy/ — being removed.
Migrations must be expand-contract; we deploy before migrating.
```

Rule of thumb: **add a line only after an agent makes the same mistake twice.** Keep it under
~150 lines; a stale `AGENTS.md` is worse than none. Re-running `harness-init` later will show
`SKIP AGENTS.md` and a diff, because you've edited it. That's expected, not an error.

---

## 5. Daily workflow

This is the short version. The full flow, with the reason for each step and when to skip one, is in
[`../skills/dev-flow/DEV-FLOW.md`](../skills/dev-flow/DEV-FLOW.md); run `/dev-flow` in the project to see which
step you're on and what to run next.

The split from the baseline doc: **if you can specify it, delegate it (Claude Code); if you
have to watch it, do it in Cursor.**

**Plan first, in Claude Code or Cursor.** Describe the feature and get a plan before any code
(Superpowers' `brainstorming` and `writing-plans` do this). Then attack the plan:

```
/critique-plan
```

It argues *against* the plan. Fix the plan, not the code, while that's cheap.

**Build.** Tight UI loops, small edits and anything you want to watch: Cursor. Specifiable
chunks and long multi-file refactors: Claude Code. For PHP bugs that don't throw, ask the
Xdebug MCP (Cursor) to trace one entry point:

> Trace `Cart::total` using the unit test `testTotalSumsPrices`.

It runs `xtrace` and returns a structured record of the call flow, with no `var_dump` and no
code changes. ✅ (The tools are `xtrace`, `xstep`, `xback`, `xprofile`, `xcoverage`,
`xcompare`.) Always trace a specific entry point, never a whole request, and use it on local
dev only, never production.

**Review before pushing (three different reviewers):**

1. Cursor → CodeRabbit sidebar → **committed only**, base `main`. Free tier: 3 reviews/hour.
   The `pre-push` hook reminds you. Code is sent to CodeRabbit's servers.
2. Claude Code, fresh session, **a different model from the one that wrote the code**:
   ```
   /review-code
   ```
   Report-only. It checks the branch against the plan or spec (`docs/superpowers/`), gives a verdict for every changed
   file, and reads `.review-log.md` so dismissed findings aren't raised again. It runs only when you type it.
3. Semgrep already ran on every commit. That's the zero-variance layer.

Anything you review and *dismiss* goes in `.review-log.md` with a reason, so the next review
doesn't re-raise it.

**Prove it's done:**

```
/verify
```

Then `/cleanup` for a style pass over just the branch's changes.

**Playwright.** Two tools, different jobs:

- *Questions* ("why is this blank on mobile?") → the Playwright MCP in Cursor. Ask in plain
  words; it reads the accessibility tree, not screenshots.
- *Test suites* → the agents, in Claude Code. ⚠️ Start Claude Code from `frontend/`, since
  that's where `init-agents` wrote `.claude/agents/` and `.mcp.json`. **Scope the planner
  tightly** (it is the token-heavy step):
  > Explore /checkout including validation errors and the empty-cart case. Produce a test plan.

  Not "explore my app". Seed your dev database small first (3 records, not 500). Review the
  markdown in `frontend/specs/`, edit it, *then* run the generator. The healer fixes tests that
  broke on selectors, and tells real app bugs apart from broken tests.

---

## 6. Put it on GitHub ⚠️ (not run here)

The harness stops short of this on purpose.

```bash
gh repo create shop --private --source=. --push    # or create it in the browser and add the remote
gh secret set ANTHROPIC_API_KEY                    # for eval.yml; paste the key when prompted
```

Then in the browser: **Settings → Branches → add rule for `main`**: require a pull request,
require status checks to pass, disallow force-pushes. It's the one guardrail that doesn't
depend on your config or an agent behaving. Dependabot starts working once the repo is on
GitHub.

---

## 7. After about two weeks of real use: the eval set

```bash
./evals/harvest.sh        # builds cases from your fix: commits
ls evals/cases
```

The harvest is rough. Spend the time curating: delete cases that make no sense, rewrite each
`bug` in its `expected.json` so it's specific enough to grade against, and add
`{"should_find": false, ...}` negatives from refactors that never needed a follow-up fix.
**Aim for about 12 cases, roughly half clean**, or a reviewer that always cries wolf scores
100%. Then:

```bash
MODEL=sonnet ./evals/run.sh     # blind review pass, then a separate grading pass
```

It exits non-zero if recall is under 0.7 or there are more than 2 false positives. After that
the monthly GitHub workflow watches for model drift. Whenever a bug reaches production that
the reviewer missed, add it as a new case.

---

## 8. Visual regression, before and after a deploy

Edit `vr/pages.json` to your real URLs, e.g. `["/", "/cart", "/checkout"]`, then:

```bash
vr/vr.sh https://staging.example.com     # before deploy: captures the baseline
# ...deploy...
vr/vr.sh https://staging.example.com     # after: compares against the baseline
```

Unchanged pages are dropped by a pixel check first, so the model only judges pages that
changed. It exits non-zero at severity 3 or above. Calibrate `vr/rubric.md` against about 20
labelled before/after pairs before you trust it, and re-run them when you switch models.
It needs a running site (locally, `npm run dev` in `frontend/`).

---

## 9. Sentry (when you deploy) ⚠️

Staging and production only; leave `SENTRY_DSN` unset locally. **Set the per-key rate limit in
Sentry before pointing production at it.** The free tier's 5,000 events can disappear in an
hour of one looping exception. Tag releases with the commit SHA in your deploy script
(`sentry-cli releases new/set-commits/finalize`, plus source-map upload for the frontend).
`sentry-cli` is already installed.

---

## 10. Pulling in later harness improvements ✅

When `~/Documents/DEV/TOOLS/harness` changes, re-run the same command in the project:

```bash
harness-init . --php=backend --web=frontend
```

New files are created, files you haven't touched stay `same`, files you've edited are `SKIP`ped
with a diff you can merge by hand. `--force` overwrites, so use it only when you mean it.
Re-running it once on this example added `phpunit.xml.dist` and left the other 21 files alone.

---

## Gotchas seen while building this

- **A bare `vendor/bin/phpunit` needs `phpunit.xml`.** The harness now ships a
  `phpunit.xml.dist`, so the command in `AGENTS.md` is accurate.
- **Namespaced tests need `autoload-dev`** in `composer.json` (step 1).
- **Semgrep's engine segfaults now and then on this machine.** The hook retries once; a real
  finding or a second crash still blocks the commit. Skip a hook deliberately with
  `LEFTHOOK_EXCLUDE=semgrep git commit ...`.
- **GitHub Actions pinned to a tag get flagged by Semgrep.** The harness pins by commit SHA
  with the version in a comment; Dependabot keeps it current.
- **The Xdebug and Playwright MCP servers are written to `.cursor/mcp.json`**, so they're
  Cursor's. The Playwright *agents* are Claude Code's, via `frontend/.claude/`.
