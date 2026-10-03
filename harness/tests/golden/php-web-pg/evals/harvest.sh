#!/usr/bin/env bash
# evals/harvest.sh
set -e
mkdir -p evals/cases

git log --format=%H --grep='^fix' -30 | while read -r fix; do
  files=$(git diff-tree --no-commit-id --name-only -r "$fix")
  for f in $files; do
    intro=$(git log -1 --format=%H "$fix^" -- "$f")
    [ -z "$intro" ] && continue
    dir="evals/cases/$(git log -1 --format=%s "$intro" | tr -cs '[:alnum:]' '-' | cut -c1-40)"
    mkdir -p "$dir"
    git show "$intro" -- "$f" > "$dir/diff.patch"
    git log -1 --format='{"should_find": true, "bug": "fixed by: %s"}' "$fix" \
      > "$dir/expected.json"
  done
done
