# Manual: set up a repo and build a feature

Start to finish: you have a task in a repo that doesn't use `ai-tools` yet. Set the repo up, then build feature X.
Steps marked **(company)** matter when the repo belongs to an employer or client.

**This sequence has not been run end to end.** Try it on a throwaway project before the first repo that matters.

Details live elsewhere: the [harness](harness/README.md), the [dev flow](skills/dev-flow/DEV-FLOW.md), and a
[worked PHP + React example](harness/WALKTHROUGH-php-react.md).

## Phase 0: set up your machine (once)

1. Clone this repo. The `harness-init` skill expects it in `~/Documents/DEV/TOOLS`:
   ```bash
   git clone https://github.com/alex-velikanov/ai-tools.git ~/Documents/DEV/TOOLS
   ```
2. Install the tools: Git, Python 3, lefthook, gitleaks, Semgrep and Claude Code. PHP and web projects also need Docker with
   Compose, running. Web projects need Node and npm on the host. Go projects need Go.
3. Add the Superpowers plugin to Claude Code, Cursor or both.
4. Install the skills:
   ```bash
   ~/Documents/DEV/TOOLS/skills/install.sh
   ```
5. Put `harness-init` on your path (this uses `~/.local/bin`, which must be on your `PATH`):
   ```bash
   ln -s ~/Documents/DEV/TOOLS/harness/bootstrap.sh ~/.local/bin/harness-init
   ```

## Phase 1: get approval (company)

6. Check which outside services may receive code or data: Claude, Cursor and CodeRabbit. Also check Semgrep's `--config=auto`
   (the commit hook uses it, and it contacts Semgrep's service) and the third-party debugging and browser MCP servers.
7. Agree what the team will share: hooks, Docker files, agent instructions and Dependabot. Check the rules for branch names,
   commit author and AI attribution. This repo's own `CLAUDE.md` rules apply to this repo, not to yours.

## Phase 2: set up the repo

Keep this in its own pull request, **separate from feature X**.

8. Clone the repo, set the Git identity it requires, and create a branch:
   ```bash
   git switch -c chore/dev-harness
   ```
9. Check what is already there: Git hooks, Husky or lefthook, Compose, CI and agent files. Setup runs `lefthook install` even
   when it keeps your existing lefthook configuration.
10. Preview. This example is PHP, web and Postgres; change the options and versions to match the repo.
    ```bash
    harness-init . --php=backend --web=frontend --db postgres --dry-run
    ```
    PHP (`--php`), Go (`--go`) and web (`--web`) have their own setup. Other languages get only the common files.
11. Apply it with the same options:
    ```bash
    harness-init . --php=backend --web=frontend --db postgres
    ```
    A file that exists and differs is skipped. Lines are added to `.gitignore`, and servers to `.cursor/mcp.json`. Don't use
    `--force` without reviewing what it would replace.
12. Install what the harness needs. Read the printed commands first: running again with `--install` builds containers and adds
    dependencies, which can change project files.
13. Complete `AGENTS.md`: commands, code layout and project rules. If the repo already has agent instructions, merge what's
    useful. For web projects, set the pages to test in `vr/pages.json`.
14. Check what you are about to commit **(company)**:
    - `.cursor/mcp.json` can hold paths that exist only on your machine (the PHP debugger entry does). Don't commit those.
    - `.github/workflows/eval.yml`: [we run evals locally](harness/README.md#how-we-run-evals-locally-decided-2026-11-26).
      Disable it once it is on GitHub (`gh workflow disable eval.yml`), or, in a shared repo, consider leaving it out of the pull
      request. Running `harness-init` again would recreate a file you left out.
    - Review the Dependabot config, the development database passwords and every changed dependency.
15. Run the existing tests and checks. Fix, or write down, anything that failed before your change. Commit, open the setup pull
    request, and merge it when approved.

## Phase 3: build feature X

Start a feature branch from the updated main branch. If the setup pull request isn't merged yet, agree how to handle that first.
Run `/dev-flow` at any point to see which step you're on.

| Step | What to do | Move on when |
|---|---|---|
| 16. Design | `superpowers:brainstorming` | You've approved what to build |
| 17. Plan | `superpowers:writing-plans` | Tasks name the files and checks |
| 18. Challenge | `/critique-plan`, then update the plan | Important gaps are resolved |
| 19. Build | `superpowers:subagent-driven-development`, tests first | Tasks are done and tests pass |
| 20. Verify | `/verify` | Each check has a result; a skip is not a pass |
| 21. Clean up | `/cleanup`, then verify again | The changes and the feature's tests are clean |
| 22. Review | A fresh session on a **different model**: `/review-code` | Every changed file has a verdict |

Fix the valid findings and repeat the checks they affect. Record each dismissed finding, with the reason, in `.review-log.md`.

- **Small, well-understood change:** a short design you approve, then tests and code. No plan document.
- **Bug:** start with `superpowers:systematic-debugging`.

## Phase 4: pull request and release

23. Commit, push and open a pull request, following the repo's rules.
24. CodeRabbit, if approved: [prefer its review of the pull request](skills/dev-flow/DEV-FLOW.md#coderabbit-how-we-run-it).
    If that isn't available or gives no line-by-line findings, review locally (change `main` if the base branch differs):
    ```bash
    coderabbit review --agent --base main
    ```
    You can also run this before opening the pull request. **It still sends code to CodeRabbit**, so it is not a way around a
    company restriction.
25. Handle the findings. For line comments on a GitHub pull request, the CodeRabbit plugin's `coderabbit:autofix` skill can help:
    your agent proposes each fix and you approve it. It uses your agent's allowance and is not CodeRabbit's cloud Autofix. For
    local findings, have your agent check and fix them. Run the tests again.
26. Merge after the required checks and approvals pass.
27. Check the release. For web projects, record the visual baseline **before** deploying and compare after
    (`vr/vr.sh --record <url>`, then `vr/vr.sh <url>`). Use approved pages and test data: screenshots may go to Claude. Check
    error monitoring, such as Sentry, if the project has it.

## Later: learn from mistakes

28. After some real work, collect about 12 review cases, roughly half with no bug. `./evals/harvest.sh` drafts bug cases from
    `fix:` commits; check them, and add the clean cases yourself. Run `./evals/run.sh` after changing the review prompt or model.
29. When the reviewer misses a bug that reaches production, add it as a case. Add an `AGENTS.md` rule for a mistake an agent makes
    twice, and a Semgrep rule when a code pattern can catch it.
