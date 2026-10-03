#!/usr/bin/env bash
# Integration test: bootstrap the harness onto the demo app in a temp dir and
# prove the pieces actually work. Run this after changing anything in core/ or modules/.
#   ./test.sh            fast + local checks
#   ./test.sh --with-llm also run evals/run.sh (calls `claude -p`, uses plan tokens)
#   ./test.sh --keep     keep the temp project for inspection
set -uo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
WITH_LLM=0; KEEP=0
for a in "$@"; do case "$a" in --with-llm) WITH_LLM=1 ;; --keep) KEEP=1 ;; esac; done

P="$(mktemp -d)/proj"; mkdir -p "$P"
FAILS=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILS=$((FAILS+1)); }
check() { local name="$1"; shift; if "$@" >"$P/../last.log" 2>&1; then pass "$name"; else fail "$name"; tail -12 "$P/../last.log" | sed 's/^/        /'; fi; }
gitc() { git -C "$P" -c user.name=harness-test -c user.email=test@example.com "$@"; }

echo "temp project: $P"
rsync -a "$HARNESS/fixtures/app/" "$P/"
cp "$HARNESS/fixtures/history/TaxResolver.buggy.php" "$P/app-php/src/Domain/TaxResolver.php"
git -C "$P" init -q -b main
gitc add -A && gitc commit -q -m "feat: add PHP invoicing domain model" --no-verify

echo; echo "== bootstrap (--install) =="
check "bootstrap runs"            "$HARNESS/bootstrap.sh" "$P" --php=app-php --go=go-api --web=web --install
check "bootstrap is idempotent"   bash -c "'$HARNESS/bootstrap.sh' '$P' --php=app-php --go=go-api --web=web | grep -q 'Summary: 0 created, 0 merged'"

echo; echo "== hooks =="
printf 'AWS_SECRET_ACCESS_KEY="AKIA%s"\n' ZZQ3DG7KL2MN9XPQ > "$P/leak.txt"; git -C "$P" add leak.txt
if gitc commit -q -m "should be blocked" >/dev/null 2>&1; then fail "gitleaks blocks a leaked secret"; gitc reset -q --hard HEAD~1; else pass "gitleaks blocks a leaked secret"; fi
git -C "$P" reset -q leak.txt; rm -f "$P/leak.txt"
gitc add -A
check "harness files pass pre-commit (gitleaks + semgrep)" gitc commit -q -m "chore: add harness"

echo; echo "== app checks =="
check "composer install"          bash -c "cd '$P/app-php' && composer install -q --no-interaction"
cp "$HARNESS/fixtures/app/app-php/src/Domain/TaxResolver.php" "$P/app-php/src/Domain/TaxResolver.php"
check "phpunit"                   bash -c "cd '$P/app-php' && vendor/bin/phpunit tests"
check "phpstan (module config)"   bash -c "cd '$P/app-php' && vendor/bin/phpstan analyse -c phpstan.neon.dist --no-progress"
check "go test -race"             bash -c "cd '$P/go-api' && go test -race ./..."
check "npm ci"                    bash -c "cd '$P/web' && npm ci --silent"
check "web build"                 bash -c "cd '$P/web' && npm run build --silent"
check "playwright seed tests"     bash -c "cd '$P/web' && npx playwright test"
gitc add -A; check "bug-fix commit passes hooks" gitc commit -q -m "fix: TaxResolver looks up tax rate by country, not unbackfilled tax_region"
rm -rf "$P/web/dist" "$P/web/test-results"

echo; echo "== evals =="
check "harvest finds the seeded bug" bash -c "cd '$P' && ./evals/harvest.sh && [ \"\$(find evals/cases -name diff.patch | wc -l)\" -ge 1 ]"
if [ "$WITH_LLM" = 1 ]; then
  check "evals/run.sh end to end (claude -p)" bash -c "cd '$P' && MODEL=sonnet ./evals/run.sh"
fi

echo; echo "== semgrep (full repo) =="
check "semgrep clean" bash -c "cd '$P' && semgrep --config=auto --error --quiet ."

echo
if [ "$KEEP" = 1 ]; then echo "kept: $P"; else rm -rf "$(dirname "$P")"; fi
if [ "$FAILS" -eq 0 ]; then echo "ALL PASSED"; else echo "$FAILS FAILED"; exit 1; fi
