# skills

The single source of truth for my own skills. Edit them **here**; both Claude Code and Cursor
pick them up from `~/.claude/skills/`, which holds symlinks back to this folder.

## The skills

| Skill | What it does | Overlaps with |
|---|---|---|
| `critique-plan` | Argues *against* a plan before implementation: failure modes, bad assumptions, unverifiable "done" conditions | nothing (Superpowers writes plans; none attack them) |
| `review-code` | Interactive branch review, report-only. Checks the reviewer isn't the author model, enumerates every changed file, separate backend/frontend passes | `superpowers:requesting-code-review` (mine is stricter: independence check, per-file verdicts) |
| `verify` | Runs the relevant checks and records one line of evidence each; a zero exit code is not a pass | `superpowers:verification-before-completion` (mine adds the evidence format and plan tracking) |
| `cleanup` | Style/cleanup pass over branch changes only, then runs just the feature's tests | nothing |
| `harness-init` | Wraps the `harness-init` command: dry run first, then apply, never `--force` unasked | nothing (a tool wrapper, not a methodology) |

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
| The skills above | this folder | Claude Code (verified: its startup log reports 5 user skills) and Cursor via `~/.claude/skills` |
| Superpowers (14 skills) | a plugin, installed separately in each tool | each tool keeps its own copy: `~/.claude/plugins/cache/` and `~/.cursor/plugins/cache/`. Not in this repo |
| Cursor built-in skills | `~/.cursor/skills-cursor/`, managed by Cursor | Cursor. Don't edit |
| `harness/core/files/evals/review-prompt.md` | harness template | copied into each project, then tuned there. It's the prompt the evals test, not a skill |
| `harness/modules/web/root/vr/rubric.md` | harness template | copied into each project, then calibrated there |
| Global working rules | `~/.claude/CLAUDE.md` | Claude Code. Cursor has its own copy in Settings → Rules (a UI field that can't be symlinked), so the two are kept in step by hand |
