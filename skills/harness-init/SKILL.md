---
name: harness-init
description: Bootstrap the dev harness (lefthook, gitleaks, semgrep, evals, MCP config, Dependabot, AGENTS.md) onto a new or existing project directory.
---

Run `harness-init` (from ~/Documents/DEV/TOOLS/harness) for the project the user names.

1. Work out the target dir and which stacks apply (`--php[=dir]`, `--go[=dir]`, `--web[=dir]`) from the repo contents or the user's request. If unclear, ask once.
2. Run `harness-init <dir> <stack flags> --dry-run` first and show the user the file list.
3. On their OK, run it for real. Add `--install` only if the user asked for installs — it adds dependencies to their project.
4. Never use `--force` without asking. If files were SKIPped, show the diffs and let the user decide.
5. Do not commit or push. End by printing the "Still manual" checklist from the output.
