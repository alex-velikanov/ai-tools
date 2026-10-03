# harness

One command to put the dev harness (hooks, secret/code scanning, evals, MCP config, a Docker runtime,
Dependabot, an agent context file) onto a new or existing project.

```bash
harness-init ~/Documents/DEV/shop --php=backend --web=frontend --db postgres
harness-init . --go                                  # current dir, Go at the root
harness-init ~/Documents/DEV/shop --php=backend --php-version 8.2 --node-version 20 --web=ui --db mysql:8.4 --install
```

Stacks take an optional subdirectory (`--php=backend`); no value means the project root.

## Where things run

| Runs in Docker Compose (per project, versions pinned) | Runs on the host (the same for every project) |
|---|---|
| PHP, Composer, PHPUnit, PHPStan, Xdebug, **the Xdebug MCP** (`app` service) | gitleaks, Semgrep, lefthook (they read source text, not your runtime) |
| Node and the dev server (`web` service) | `claude`, `gh`, `sentry-cli` |
| The database: `--db postgres[:tag]` or `mysql[:tag]` (`db` service) | Go (`go.mod` can pin a `toolchain`, so Go needs no container) |
| | Playwright (`e2e/`) and the visual tool (`vr/`): they drive a browser against a URL, so they need a host Node, but any recent LTS, not your project's version |

There is deliberately no "run PHP on the host" mode. Two projects can use different PHP, Node and database versions at the same time
without touching your machine's tooling, and the Xdebug build and the MCP live in the project's own image.

Options: `--php-version` (default 8.3), `--node-version` (default 22), `--db` (default none; postgres 16 or mysql 8.4 unless you give a tag).

## What it does
- Copies `core/files/` (always) and `modules/<stack>/files|root/` (per stack), filling in paths and versions.
- Assembles `compose.yaml`, `.github/dependabot.yml`, `AGENTS.md` (+ `CLAUDE.md` symlink), `.gitignore` lines.
- Merges servers into `.cursor/mcp.json` without replacing existing ones. The Xdebug MCP entry is `docker compose -f <project>/compose.yaml exec -T app xdebug-mcp`.
- `git init` if needed and `lefthook install`.
- Checks the host tools it needs (including Docker) and says how to install any that are missing.

## What it never does
- Overwrite a file that already exists and differs (shows a diff, skips; `--force` to replace).
- Touch application code, commit, or push.
- Build images, start containers or add dependencies unless you pass `--install`.

Because user-edited files are preserved, re-running is safe. A hand-edited `AGENTS.md` shows as "SKIP" with a diff each time. That is expected.

## Layout
```
bootstrap.sh            the command (symlinked to /usr/local/bin/harness-init)
core/files/             copied to every project root
core/fragments/         pieces assembled into dependabot.yml / AGENTS.md / .gitignore
modules/{php,go,web}/   per-stack files/ (into the stack dir), root/ (into the project root), fragments
modules/docker/         compose fragments for the database and the app's DB environment
fixtures/app/           demo PHP+Go+React app, used only by the tests
fixtures/history/       the "buggy" TaxResolver used to seed a real fix: commit for eval harvesting
tests/golden/           snapshots of generated files for five flag combinations
test.sh                 the test suite (below)
```

## Tests: how regressions are caught
```bash
harness/test.sh                  # fast tier, ~10 s, starts no containers
harness/test.sh full             # + real containers, several minutes
harness/test.sh --update-golden  # after an intended template change: regenerate, then review the git diff
```

**Fast tier** (also runs in CI on every push, and as this repo's pre-push hook):
- `bash -n` on every script.
- Golden snapshots: the full generated file tree for five flag combinations (php+web+postgres, php 8.2+mysql, go only, web on Node 20,
  everything with Postgres 18). Any change to what the harness generates shows up as a diff.
- Every generated `compose.yaml` passes `docker compose config`.
- Behaviour: re-running changes nothing, a hand-edited `AGENTS.md` and an existing MCP entry are never overwritten, bad versions, unknown
  databases and unknown options are rejected.
- The skills installer (link, copy, skip diverged, leave foreign skills alone) and the skills' frontmatter.
- Markdown links resolve; gitleaks finds nothing in the repo.

**Full tier** (needs Docker, Semgrep, gitleaks, lefthook, Node, Go; builds real images):
- The demo app end to end: `harness-init --install`, gitleaks blocks a leaked key, hooks pass, the pinned PHP runs as a non-root user,
  `composer install`, PHPUnit, PHPStan, Xdebug loaded, the Xdebug MCP handshake and a real `xtrace` **inside the container**, the exact
  `.cursor/mcp.json` entry works as Cursor would spawn it, a real Postgres connection, `go test -race`, a web build in the container,
  Playwright on the host against the containerised dev server, eval harvesting, Semgrep over the whole project including the Dockerfile.
- **Two projects at once with different versions:** PHP 8.2 + Node 20 + MySQL 8.4 beside PHP 8.4 + Node 22 + Postgres 16, each on its own
  port. It asserts each container runs its own pinned versions, connects to its own database, has a working Xdebug MCP, and serves on its port.
- `--with-llm` also runs the eval harness through `claude -p` (uses plan tokens).

## Manual, once per project
1. Fill in `AGENTS.md` Structure and Rules with real facts; check the Commands.
2. Set `vr/pages.json` to real URLs (web).
3. Push to GitHub; branch protection on `main`; repo secret `ANTHROPIC_API_KEY` for `eval.yml`.
4. Sentry: project, rate limits first, then SDK.
5. After ~2 weeks of real use: `./evals/harvest.sh`, curate ~12 cases (about half clean).

## Related

- **Dev flow** — which skill runs at which step of a task, and why: [`../skills/dev-flow/DEV-FLOW.md`](../skills/dev-flow/DEV-FLOW.md). Run `/dev-flow` in a project to see which step you're on.
- **Skills** (`/critique-plan`, `/verify`, `/review-code`, `/cleanup`, `/harness-init`, `/dev-flow`) live in [`../skills/`](../skills/README.md). They are installed per machine, not per project, so `harness-init` does not copy them.
- **Walkthrough** — a full new-project example: [`WALKTHROUGH-php-react.md`](WALKTHROUGH-php-react.md).

The design rationale lives in `../README.md` (the baseline doc).

## License

MIT — see [LICENSE](../LICENSE).
