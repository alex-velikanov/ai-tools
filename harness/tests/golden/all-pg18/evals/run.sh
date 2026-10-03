#!/usr/bin/env bash
# evals/run.sh
set -e
MODEL=${MODEL:-sonnet}

# Pass 1 — review each case BLIND
for case in evals/cases/*/; do
  claude -p "$(cat evals/review-prompt.md)

Review this diff:
$(cat "$case/diff.patch")" --model "$MODEL" > "$case/actual.json"
done

# Pass 2 — grade everything in one invocation
claude -p 'For every directory under evals/cases/, compare actual.json
against expected.json.

A case PASSES if:
  should_find=true  AND the reviewer identified that specific bug
                    (adjacent commentary about the same file does NOT count)
  should_find=false AND the reviewer reported nothing at severity >= 3

Output a markdown table: case | expected | found | pass.
Then print recall (found/should_find) and false-positive count.
Exit non-zero if recall < 0.7 or false positives > 2.'
