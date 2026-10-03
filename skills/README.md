# skills

The single source of truth for my own skills. Edit them **here**; both Claude Code and Cursor
pick them up from `~/.claude/skills/`, which holds symlinks back to this folder.

## The skills

| Skill | What it does | Overlaps with |
|---|---|---|
| `critique-plan` | Argues *against* a plan before implementation: failure modes, bad assumptions, unverifiable "done" conditions | nothing (Superpowers writes plans; none attack them) |
| `review-code` | The final independent pre-PR review: spec compliance against the plan, architecture and quality, a verdict for every file, reads `.review-log.md`, flags if the reviewer is the author model. Report-only | `superpowers:requesting-code-review` and the per-task reviews in `subagent-driven-development` (those are the cheap, automatic inner loop; this is the outer gate) |
| `verify` | Phase gate: scoped tests and builds, one line of evidence per check, skipped tests are not a pass, stops if anything is red or unverifiable | `superpowers:verification-before-completion` (that is the always-on rule; this is the explicit gate and report) |
| `cleanup` | Style/cleanup pass over branch changes only, then runs just the feature's tests | nothing |
| `harness-init` | Wraps the `harness-init` command: dry run first, then apply, never `--force` unasked | nothing (a tool wrapper, not a methodology) |
| `dev-flow` | Navigator: reads the repo, says which dev-flow step you're on and which skill to run next and why. Read-only. The full flow and reasoning are in `dev-flow/DEV-FLOW.md` | nothing |

`review-code`, `verify` and `dev-flow` set `disable-model-invocation: true`, so they only run when you type the
slash command; the model won't pick them on its own. That keeps them from competing with the Superpowers skills
that auto-trigger on similar situations. Both tools document this field (Claude Code and Cursor).

## Install (any machine)

```bash
git clone https://github.com/alex-velikanov/ai-tools.git ~/Documents/DEV/TOOLS
~/Documents/DEV/TOOLS/skills/install.sh           # links each skill into ~/.claude/skills
```

- Each skill is linked individually, so skills other tools put in `~/.claude/skills` are left alone.
- A skill that already exists and **differs** is skipped with a diff, never overwritten. `--force` replaces it
  and moves the old one to `~/.claude/skills-backup-<timestamp>/` (outside the skills folder, so it isn't loaded).
- `--copy` copies instead of linking. Use it if a tool turns out not to follow symlinks.
- `--dry-run` shows what would happen. Re-running is safe.

## Add or change a skill

1. Create or edit `skills/<name>/SKILL.md` (frontmatter needs `name` and `description`).
2. New skill only: run `./install.sh`. Edits to existing skills apply on the next session, because the links point here.
3. Commit and push.

## Where everything else lives

| Asset | Source of truth | Seen by |
|---|---|---|
| The skills above | this folder | Claude Code (verified: startup log counts the user skills) and Cursor (verified live: its skill count rose when they were linked; cold-restart behaviour is the one thing not yet confirmed) via `~/.claude/skills` |
| Superpowers (14 skills) | a plugin, installed separately in each tool | each tool keeps its own copy: `~/.claude/plugins/cache/` and `~/.cursor/plugins/cache/`. Not in this repo |
| Cursor built-in skills | `~/.cursor/skills-cursor/`, managed by Cursor | Cursor. Don't edit |
| `harness/core/files/evals/review-prompt.md` | harness template | copied into each project, then tuned there. It's the prompt the evals test, not a skill |
| `harness/modules/web/root/vr/rubric.md` | harness template | copied into each project, then calibrated there |
| Global working rules | `~/.claude/CLAUDE.md` | Claude Code. Cursor has its own copy in Settings → Rules (a UI field that can't be symlinked), so the two are kept in step by hand |
