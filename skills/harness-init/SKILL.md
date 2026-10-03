---
name: harness-init
description: Bootstrap the dev harness (lefthook, gitleaks, semgrep, evals, MCP config, Docker runtime, Dependabot, AGENTS.md) onto a new or existing project directory.
---

Run `harness-init` (from ~/Documents/DEV/TOOLS/harness) for the project the user names.

1. Work out the target dir, the stacks (`--php[=dir]`, `--go[=dir]`, `--web[=dir]`) and the runtime from the repo contents or the user's request:
   - PHP and Node run in **Docker Compose**, pinned per project: `--php-version` (default 8.3), `--node-version` (default 22).
   - A database is `--db postgres[:tag]` or `--db mysql[:tag]`; default is none.
   - Go runs on the host. There is no host mode for PHP or Node.
   - Take versions from what the project already declares (composer.json `require.php`, `.nvmrc` / `engines`, an existing compose file). If they are not declared, ask once rather than assuming.
2. Run `harness-init <dir> <flags> --dry-run` first and show the user the file list.
3. On their OK, run it for real. Add `--install` only if the user asked for installs: it builds images, starts containers and adds dependencies to their project, and needs Docker running.
4. Never use `--force` without asking. If files were SKIPped (an existing `compose.yaml`, `AGENTS.md`, ...), show the diffs and let the user decide.
5. Do not commit or push. End by printing the "Still manual" checklist from the output.
