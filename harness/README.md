# harness

One command to put the dev harness (hooks, secret/code scanning, evals, MCP config,
Dependabot, agent context file) onto a new or existing project.

```bash
harness-init ~/Documents/DEV/my-app --php=backend --web=frontend   # new or existing dir
harness-init . --go                                                # current dir, Go at the root
harness-init ~/Documents/DEV/my-app --web --install                # also install Playwright etc.
```

Stacks take an optional subdirectory (`--php=backend`); no value means the project root.

## What it does
- Copies `core/files/` (always) and `modules/<stack>/files|root/` (per stack), filling in paths.
- Assembles `.github/dependabot.yml`, `AGENTS.md` (+ `CLAUDE.md` symlink), `.gitignore` lines.
- Merges servers into `.cursor/mcp.json` (xdebug, playwright) without replacing existing ones.
- `git init` if needed and `lefthook install`.
- Checks that required tools exist and says how to install any that are missing.

## What it never does
- Overwrite a file that already exists and differs (shows a diff, skips; `--force` to replace).
- Touch application code, commit, or push.
- Add dependencies to your project unless you pass `--install`.

Because user-edited files are preserved, re-running is safe — a hand-edited `AGENTS.md` will
show as "SKIP" with a diff each time. That is expected.

## Layout
```
bootstrap.sh            the command (symlinked to /usr/local/bin/harness-init)
core/files/             copied to every project root
core/fragments/         pieces assembled into dependabot.yml / AGENTS.md / .gitignore
modules/{php,go,web}/   per-stack files/ (into the stack dir), root/ (into project root), fragments
fixtures/app/           demo PHP+Go+React app, used only by test.sh
fixtures/history/       the "buggy" TaxResolver used to seed a real fix: commit for eval harvesting
test.sh                 bootstraps the fixture in a temp dir and verifies everything works
```

## Changing the harness
Edit `core/` or `modules/`, then run `./test.sh` (`--with-llm` also exercises the eval run via
`claude -p`). It covers: bootstrap + idempotency, gitleaks blocking a leaked key, Semgrep clean,
PHPUnit/PHPStan/`go test -race`/web build/Playwright, and eval harvesting.

## Manual, once per project
1. Fill in `AGENTS.md` Structure and Rules with real facts; check the Commands.
2. Set `vr/pages.json` to real URLs (web).
3. Push to GitHub; branch protection on `main`; repo secret `ANTHROPIC_API_KEY` for `eval.yml`.
4. Sentry: project, rate limits first, then SDK.
5. After ~2 weeks of real use: `./evals/harvest.sh`, curate ~12 cases (about half clean).

The design rationale lives in `../README.md` (the baseline doc).
