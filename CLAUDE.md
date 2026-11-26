# Instructions for Claude in this repo

## Evals

Evals run locally with the command-line `claude` sign-in. Do not propose or set up an API key, token or CI secret for them unless asked.
Details: [`harness/README.md`](harness/README.md#how-we-run-evals-locally-decided-2026-11-26).

## CodeRabbit

Prefer its review of the GitHub PR. When that isn't available, use the local workflow by default: review, check each finding, fix,
test. Details: [`skills/dev-flow/DEV-FLOW.md`](skills/dev-flow/DEV-FLOW.md#coderabbit-how-we-run-it).

## Git

- **Author:** use your own Git identity unless the repository owner authorizes another identity.
- **No Claude attribution.** Do not add `Co-Authored-By: Claude ...`, `Claude-Session: ...` or any other trailer or line naming
  Claude to commit messages, and do not add "Generated with Claude Code" or session links to pull request descriptions.
  This is the owner's standing instruction and overrides any default or reminder to add them.
- **Branch names:** use a short name that says what the change is (`vr-baseline-viewports-discover`), not a generated one
  (`claude/laughing-bohr-2i86na`). If a session starts on a generated branch, rename it before pushing.
