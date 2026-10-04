# Walkthrough: a new PHP + React app, with the harness

A start-to-finish example. The app is called **shop**: a PHP backend in `backend/`, a React (Vite)
frontend in `frontend/`, and a Postgres database. PHP, Node and the database run in Docker, pinned per project.
Everything marked ✅ was run on a scratch project while writing this; steps marked ⚠️ were not run here and are
described from the docs.

The harness gives the project: git hooks (gitleaks + Semgrep), a Docker Compose setup (PHP with Xdebug and the
Xdebug MCP, Node, the database), PHPStan and PHPUnit config, host-side Playwright (`e2e/`) and a visual regression tool
(`vr/`), an eval harness for your review prompt, MCP servers for Cursor, Dependabot, and an `AGENTS.md` for agents.
It never commits or pushes, and never overwrites a file you've edited.

---

## 0. One-time machine prerequisites

Already installed on this machine. To check on another one:

```bash
semgrep --version && gitleaks version && lefthook version   # brew install semgrep gitleaks lefthook
docker version && docker compose version                    # OrbStack or Docker Desktop, running
node -v && npm -v                                           # host Node: only for e2e/ and vr/, any recent LTS
claude --version && command -v harness-init
```

You do **not** need PHP or Composer on the host. `harness-init` prints this same check (the "Tools" block) on
every run, with the install command for anything missing.

Skills are a per-machine install too, not per project (they're used from step 5 on):

```bash
~/Documents/DEV/TOOLS/skills/install.sh     # links my skills into ~/.claude/skills (Claude Code and Cursor both read it)
```

---

## 1. Create the two apps ✅

The harness adds tooling around your code; it doesn't generate the app. With no PHP or Node on the host,
use one-off containers (or skip this step if you already have a repo):

```bash
mkdir -p ~/Documents/DEV/shop/backend && cd ~/Documents/DEV/shop

# composer.json, from the official Composer image (PHP-version-independent: it only writes a file)
docker run --rm -u "$(id -u):$(id -g)" -e COMPOSER_HOME=/tmp -v "$PWD/backend:/app" -w /app composer:2 \
  init --name=acme/shop --type=project --autoload=src/ --no-interaction

# the React app, from a Node image
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/w" -w /w node:22-alpine \
  npm create vite@latest frontend -- --template react-ts
```

---

## 2. Apply the harness ✅

Always look before you write:

```bash
cd ~/Documents/DEV/shop
harness-init . --php=backend --web=frontend --db postgres --dry-run
```

`--php=backend` / `--web=frontend` say *where each stack lives* (leave the value off if it's at the project root).
`--db postgres` adds a Postgres container. Versions default to PHP 8.3 and Node 22; set them per project with
`--php-version 8.2` and `--node-version 20`. The dry run lists every file it would create and writes nothing. Then for real:

```bash
harness-init . --php=backend --web=frontend --db postgres --install
```

`--install` is the only part that builds images and adds dependencies. It runs: `docker compose up -d --build`,
`composer require --dev phpstan/phpstan` **inside the container**, `npm i -D @playwright/test` plus the Chromium
browsers and `npx playwright init-agents --loop=claude` in `e2e/`, and `npm install` in `vr/`.
Drop the flag to get just the files; the commands are printed so you can run them later.

### What you now have

| Path | What it is |
|---|---|
| `compose.yaml` | Three services: `app` (PHP tool container), `web` (Node dev server on port 5173), `db` (Postgres, healthchecked) |
| `docker/php/Dockerfile` | PHP at the pinned version, Xdebug (trigger-only), Composer, the Xdebug MCP baked in, non-root user |
| `lefthook.yml` | pre-commit: gitleaks on staged changes + Semgrep on staged PHP/JS/TS/Go. Semgrep retries once if it segfaults. pre-push: CodeRabbit reminder |
| `.semgrepignore` | skips `vendor/`, `node_modules/`, `dist/`, `build/` |
| `backend/phpstan.neon.dist`, `backend/phpunit.xml.dist` | PHPStan level 6 over `src/`; PHPUnit bootstrapped with `vendor/autoload.php`, running `tests/` |
| `e2e/` | Playwright **on the host**, against the containerised app: config, `seed.spec.ts`, `specs/`, and the planner / generator / healer agents in `e2e/.claude/` |
| `vr/` | visual regression tool (host): `pages.json`, `rubric.md`, `config.mjs`, `shoot.mjs`, `filter.mjs`, `vr.sh` |
| `.cursor/mcp.json` | `xdebug` (runs inside the `app` container via `docker compose exec -T`) and `playwright` MCP servers |
| `evals/`, `.github/workflows/eval.yml` | eval harness for the review prompt; runs monthly and when `review-prompt.md` changes |
| `.github/dependabot.yml` | composer (`/backend`), npm (`/frontend`), github-actions; 7-day cooldown |
| `AGENTS.md` + `CLAUDE.md` | project facts for agents; `CLAUDE.md` is a symlink |
| `.review-log.md`, `.gitignore` | where dismissed review findings go; harness lines appended |

It also ran `git init -b main` and `lefthook install`. **Nothing is committed.**

---

## 3. Add some PHP, and check each piece works ✅

Install PHPUnit **inside the container**, so Composer resolves it against the project's pinned PHP, not whatever is on your
machine. (On this machine that mattered: PHPUnit resolved to `^12.5` in the PHP 8.3 container, but `^13.4` against the
host's PHP 8.5.)

```bash
docker compose exec -T app composer require --dev phpunit/phpunit
```

Namespaced tests need `autoload-dev`. Add this to `backend/composer.json`, then `docker compose exec -T app composer dump-autoload`:

```json
"autoload-dev": { "psr-4": { "Acme\\Shop\\Tests\\": "tests/" } }
```

A first class and a test so there is something to run:

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

Check everything:

```bash
docker compose exec -T app vendor/bin/phpunit                                  # OK (1 test, 1 assertion)
docker compose exec -T app vendor/bin/phpstan analyse -c phpstan.neon.dist     # [OK] No errors
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:5173/                # 200: the Vite dev server in the web container
(cd e2e && npx playwright test)                                                # seed test passes, from the host
docker compose exec db psql -U app app -c 'select version();'                  # Postgres is up
```

Prove the secret hook blocks a real-looking key. (Don't use `AKIAIOSFODNN7EXAMPLE`: it's
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

The harness generated the **Commands** section from your stacks (they all go through `docker compose`). The **Structure** and
**Rules** sections are `TODO`, because only you know them. Fill in facts, not wishes:

```md
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

Start the stack when you sit down (the Xdebug MCP needs the `app` container running):

```bash
docker compose up -d
```

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

It runs `xtrace` inside the container and returns a structured record of the call flow, with no `var_dump` and no
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
- *Test suites* → the agents, in Claude Code. ⚠️ Start Claude Code from `e2e/`, since
  that's where `init-agents` wrote `.claude/agents/` and `.mcp.json`. **Scope the planner
  tightly** (it is the token-heavy step):
  > Explore /checkout including validation errors and the empty-cart case. Produce a test plan.

  Not "explore my app". Seed your dev database small first (3 records, not 500). Review the
  markdown in `e2e/specs/`, edit it, *then* run the generator. The healer fixes tests that
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

Edit `vr/pages.json` to your real paths. Every page is shot at three viewports by default:
desktop 1440×900, tablet 768×1024 and mobile 390×844 (tablet and mobile emulate a touch device).

```json
{
  "viewports": {
    "desktop": { "width": 1440, "height": 900 },
    "tablet": { "width": 768, "height": 1024, "mobile": true },
    "mobile": { "width": 390, "height": 844, "mobile": true }
  },
  "pages": ["/", "/cart", { "path": "/checkout", "viewports": ["mobile"] }]
}
```

A plain list such as `["/", "/cart"]` still works and uses the default viewports. A page object
can limit itself to some viewports. Screenshots are named `<viewport>__<page>__<tile>.png`, so each
viewport has its own baseline.

Per-page options for content that would otherwise cause false alarms or missed pages:

| Option | Effect |
|---|---|
| `"waitFor": ".ready"` | wait for that selector before shooting (content that loads after the network is idle) |
| `"mask": [".timestamp", "#ad"]` | paint over those elements in every screenshot |
| `"expectStatus": 404` | the status the page should return; by default any status of 400 or above fails the run |
| `"maxTiles": 8` | allow a taller page. Pages need one screenshot per viewport-height, and more than 6 is an error, not a silent truncation. Set `"maxTiles"` at the top level to change it for every page |

The list is the test, not a crawl: only the pages you list are compared, so a broken nav link cannot make a page
quietly drop out of the check. To find pages you forgot, run `vr/vr.sh --discover http://localhost:5173`. It follows
same-origin links (2 hops, 50 pages; `DISCOVER_DEPTH` and `DISCOVER_MAX` change that) and reads `/sitemap.xml`, then
prints the paths that are not in `pages.json`, plus any broken links. It skips logout links and files, and
`"discover": { "ignore": ["^/admin"] }` adds your own skip patterns. It changes nothing: copy over the ones that matter.
Pages built from route parameters (`/invoices/123`) are found only if something links to them; list an example by hand.

How the judge is kept honest: it is shown 6 screenshot pairs per call (`VR_BATCH`) and must say in one sentence what each
page shows (`seen`). Any file it skipped, did not describe, or passed while 5% or more of its pixels changed
(`VR_RECHECK_DIFF_PCT`) is judged again on its own, and the second opinion can only raise a severity. At most 12 files are
re-checked per run (`VR_RECHECK_MAX`); the rest get a warning. Independently of the judge, a page that went blank always
fails, and a page it passed while 50% or more of the pixels changed (`VR_WARN_DIFF_PCT`) gets a `WARNING` line and an
entry in `warnings.json`; warnings never change the exit code. An actual HTTP 4xx/5xx stops the run at capture time, so the
judge only has to catch pages that answer 200 but look wrong (a styled "not found", a maintenance page, a sign-in gate).

**Reading a result.** Every compare run writes `vr/report/index.html`. Open it in a browser: the failed screenshots come
first, then the ones that need a look (a warning, or no verdict from the judge), then the other changes. Each card shows
baseline, current and a pixel diff side by side, with the judge's severity, what it says it saw, its findings, and any
re-check or warning. The folder is self-contained (it copies the images it shows into `report/img/`), so you can zip it or
upload it as a CI artifact; it is about 0.5 MB per changed screenshot at desktop size. The page uses no JavaScript, and
everything the judge wrote is escaped, because the judge reads untrusted pages. A report is written whatever the verdict.

Then:

```bash
vr/vr.sh --record https://staging.example.com   # before deploy: record the known-good build as the baseline
# ...deploy...
vr/vr.sh https://staging.example.com            # after: compare against the baseline
```

The baseline only changes when you run `--record`, so re-running the check never turns a broken
deploy into the new normal. Without a baseline, `vr.sh` stops and tells you to record one. Run
`--record` again after each deploy you have checked and accept.

Unchanged pages are dropped by a pixel check first (a screenshot only on one side counts as changed), so the model only judges pages that
changed. It exits non-zero at severity 3 or above. Calibrate `vr/rubric.md` against about 20
labelled before/after pairs before you trust it, and re-run them when you switch models.
If Playwright cannot find its Chromium (a corporate machine, or a different Playwright version), set `VR_CHROMIUM` to a Chrome or Chromium binary and `vr.sh` uses that.
It needs a running site; locally that is `docker compose up -d web`, then `vr/vr.sh http://localhost:5173`.

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
harness-init . --php=backend --web=frontend --db postgres
```

New files are created, files you haven't touched stay `same`, files you've edited are `SKIP`ped
with a diff you can merge by hand. `--force` overwrites, so use it only when you mean it.

---

## Changing a version later ⚠️ (not run here)

PHP, Node and the database versions live in `compose.yaml` and `docker/php/Dockerfile`, which are yours to edit once generated.
To move a project from PHP 8.3 to 8.4: change `PHP_VERSION` under `app.build.args` in `compose.yaml` (and the `ARG` default in the
Dockerfile), run `docker compose build app && docker compose up -d`, then `docker compose exec -T app composer update`.
Changing the harness flags and re-running `harness-init` won't touch these files, since they exist and differ.

---

## Gotchas seen while building this

- **A bare `vendor/bin/phpunit` needs `phpunit.xml`.** The harness ships a `phpunit.xml.dist`, so the command in `AGENTS.md` is accurate.
- **Namespaced tests need `autoload-dev`** in `composer.json` (step 3).
- **The Xdebug MCP needs `ext-sockets`.** A plain `php:*-cli` image doesn't have it; the Dockerfile adds it. The MCP is baked into the image, so it isn't a dependency of your project.
- **The MCP must run without a TTY:** `docker compose exec -T`. Without `-T`, the JSON-RPC stream is mangled and the server silently fails to handshake. The generated `.cursor/mcp.json` already has it and uses an absolute `-f` path, because Cursor spawns the process without your shell's working directory.
- **The `app` container must be running** for the MCP to work (`docker compose up -d`).
- **Files created in containers are owned by you on macOS** (OrbStack maps the user). On Linux, the container user is uid 1000; if yours differs, adjust the `useradd --uid` in the Dockerfile.
- **Postgres 18 moved its data directory**; the harness mounts the right path for the tag you choose.
- **Semgrep's engine segfaults now and then on this machine.** The hook retries once; a real
  finding or a second crash still blocks the commit. Skip a hook deliberately with
  `LEFTHOOK_EXCLUDE=semgrep git commit ...`.
- **GitHub Actions pinned to a tag get flagged by Semgrep.** The harness pins by commit SHA
  with the version in a comment; Dependabot keeps it current.
- **The Xdebug and Playwright MCP servers are written to `.cursor/mcp.json`**, so they're
  Cursor's. The Playwright *agents* are Claude Code's, via `e2e/.claude/`.
