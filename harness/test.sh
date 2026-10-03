#!/usr/bin/env bash
# Tests for the harness and the skills installer.
#
#   ./test.sh                  fast tier: seconds, starts no containers. Golden snapshots of generated
#                              files, compose validity, error paths, idempotency, skills installer, the vr tool
#                              (pixel filter, baseline rotation, report parsing and exit code), doc links.
#   ./test.sh full             fast tier + real containers: the demo app end to end, and two projects with
#                              different PHP / Node / database versions running side by side.
#   ./test.sh --update-golden  regenerate tests/golden/ (review the git diff before committing it)
#   Flags: --with-llm  also run the eval harness via `claude -p` (full tier, uses plan tokens)
#          --keep      keep the temp directory
#
# Run the fast tier after ANY change to bootstrap.sh, core/, modules/ or skills/. Run full before relying on changes.
set -uo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HARNESS/.." && pwd)"
TIER=fast; WITH_LLM=0; KEEP=0; UPDATE=0
for a in "$@"; do case "$a" in
  fast|full) TIER="$a" ;; --with-llm) WITH_LLM=1 ;; --keep) KEEP=1 ;; --update-golden) UPDATE=1 ;;
  *) echo "unknown argument: $a" >&2; exit 2 ;; esac; done

WORK="$(mktemp -d)"; GOLDEN="$HARNESS/tests/golden"
FAILS=0; PASSES=0; COMPOSE_DIRS=()
pass() { printf '  PASS  %s\n' "$1"; PASSES=$((PASSES+1)); }
fail() { printf '  FAIL  %s\n' "$1"; FAILS=$((FAILS+1)); }
skip() { printf '  SKIP  %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
check() { local name="$1"; shift; if "$@" >"$WORK/last.log" 2>&1; then pass "$name"; else fail "$name"; tail -15 "$WORK/last.log" | sed 's/^/        /'; fi; }
gitc() { git -C "$1" -c user.name=harness-test -c user.email=test@example.com "${@:2}"; }
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }

cleanup() {
  for d in "${COMPOSE_DIRS[@]:-}"; do [ -n "$d" ] && [ -f "$d/compose.yaml" ] && (cd "$d" && WEB_PORT="$(cat "$d/.port" 2>/dev/null || echo 5173)" docker compose down -v --remove-orphans >/dev/null 2>&1); done
  if [ "$KEEP" = 1 ]; then echo "kept: $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

boot() { local dir="$1"; shift; "$HARNESS/bootstrap.sh" "$dir" "$@" >"$WORK/boot.log" 2>&1; }

# ============================================================ FAST TIER
echo "== fast: syntax =="
for f in "$HARNESS/bootstrap.sh" "$HARNESS/test.sh" "$REPO/skills/install.sh" "$HARNESS/core/files/evals/run.sh" "$HARNESS/core/files/evals/harvest.sh" "$HARNESS/modules/web/root/vr/vr.sh"; do
  check "bash -n ${f#$REPO/}" bash -n "$f"
done
if have node; then
  for f in "$HARNESS"/modules/web/root/vr/*.mjs "$HARNESS"/tests/vr/*.mjs; do check "node --check ${f#$REPO/}" node --check "$f"; done
else skip "node not installed: .mjs syntax checks"; fi

echo; echo "== fast: golden snapshots of generated files =="
# Project dir is always named "proj" so paths and the compose project name are stable.
normalize() {  # normalize <src proj dir> <dest dir> <root string>: copy without .git, replace machine-specific strings
  python3 - "$1" "$2" "$3" <<'PY'
import os, shutil, sys
src, dest, root = sys.argv[1], sys.argv[2], sys.argv[3]
docker = shutil.which("docker") or "docker"
for base, dirs, files in os.walk(src):
    dirs[:] = [d for d in dirs if d != ".git"]
    for f in files:
        p = os.path.join(base, f); rel = os.path.relpath(p, src); out = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if os.path.islink(p):
            open(out, "w").write("-> " + os.readlink(p) + "\n"); continue
        data = open(p, "rb").read()
        try:
            open(out, "w").write(data.decode().replace(root, "<ROOT>").replace(docker, "<DOCKER>"))
        except UnicodeDecodeError:
            open(out, "wb").write(data)
        os.chmod(out, os.stat(p).st_mode & 0o777)
PY
}
scenario() {  # scenario <name> <bootstrap args...>
  local name="$1"; shift
  local dir="$WORK/golden/$name/proj" norm="$WORK/norm/$name"
  mkdir -p "$dir"
  if ! boot "$dir" "$@"; then fail "snapshot $name: bootstrap failed"; tail -8 "$WORK/boot.log" | sed 's/^/        /'; return; fi
  rm -rf "$norm"; mkdir -p "$norm"; normalize "$dir" "$norm" "$dir"
  if [ "$UPDATE" = 1 ]; then rm -rf "$GOLDEN/$name"; mkdir -p "$GOLDEN"; cp -R "$norm" "$GOLDEN/$name"; echo "  updated  tests/golden/$name"; return; fi
  if [ ! -d "$GOLDEN/$name" ]; then fail "snapshot $name: no golden (run ./test.sh --update-golden)"; return; fi
  if diff -ru "$GOLDEN/$name" "$norm" >"$WORK/diff.log" 2>&1; then pass "snapshot $name ($*)"; else fail "snapshot $name ($*)"; sed -n '1,30p' "$WORK/diff.log" | sed 's/^/        /'; fi
  if [ -f "$dir/compose.yaml" ]; then check "compose valid: $name" bash -c "cd '$dir' && docker compose config -q"; fi
}
scenario php-web-pg   --php=backend --web=frontend --db postgres
scenario php-mysql82  --php --php-version 8.2 --db mysql:8.4
scenario go-only      --go=svc
scenario web-node20   --web --node-version 20
scenario all-pg18     --php=backend --web=frontend --go=svc --db postgres:18

echo; echo "== fast: behaviour =="
D="$WORK/golden/php-web-pg/proj"
check "re-run is idempotent (nothing created or merged)" bash -c "'$HARNESS/bootstrap.sh' '$D' --php=backend --web=frontend --db postgres | grep -q 'Summary: 0 created, 0 merged'"
echo "# my own notes" > "$D/AGENTS.md"
"$HARNESS/bootstrap.sh" "$D" --php=backend --web=frontend --db postgres >"$WORK/boot.log" 2>&1
check "a hand-edited AGENTS.md is preserved and reported as SKIP" bash -c "[ \"\$(cat '$D/AGENTS.md')\" = '# my own notes' ] && grep -q 'SKIP.*AGENTS.md' '$WORK/boot.log'"
python3 - "$D/.cursor/mcp.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); c["mcpServers"]["xdebug"] = {"command": "custom"}; json.dump(c, open(p, "w"))
PY
"$HARNESS/bootstrap.sh" "$D" --php=backend --web=frontend --db postgres >/dev/null 2>&1
check "an existing MCP server entry is not overwritten" bash -c "python3 -c \"import json; assert json.load(open('$D/.cursor/mcp.json'))['mcpServers']['xdebug']['command']=='custom'\""
expect_fail() {  # expect_fail <label> <expected message fragment> <args...>
  local label="$1" msg="$2"; shift 2
  local out; out="$("$HARNESS/bootstrap.sh" "$WORK/neg" "$@" 2>&1)"; local rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q -- "$msg"; then pass "rejects: $label"; else fail "rejects: $label (exit $rc)"; printf '%s\n' "$out" | tail -3 | sed 's/^/        /'; fi
}
expect_fail "bad PHP version"        "must look like 8.3"       --php --php-version latest
expect_fail "bad Node version"       "must look like 22"        --web --node-version lts
expect_fail "unknown database"       "must be postgres, mysql"  --php --db oracle
expect_fail "database with no stack" "needs --php or --web"     --go --db postgres
expect_fail "unknown option"         "unknown option"           --nonsense
expect_fail "odd database tag"       "odd characters"           --php --db 'postgres:1;rm'

echo; echo "== fast: skills installer =="
ST="$WORK/skills-target"; mkdir -p "$ST/foreign"
echo x > "$ST/foreign/SKILL.md"
cp -R "$REPO/skills/verify" "$ST/verify"                                                   # identical to the repo -> becomes a link
cp -R "$REPO/skills/cleanup" "$ST/cleanup"; echo "local edit" >> "$ST/cleanup/SKILL.md"    # diverged -> skipped
"$REPO/skills/install.sh" --target "$ST" >"$WORK/inst.log" 2>&1
check "installer links new skills"                       bash -c "[ -L '$ST/critique-plan' ] && [ -L '$ST/dev-flow' ]"
check "installer replaces an identical copy with a link" bash -c "[ -L '$ST/verify' ]"
check "installer never overwrites a diverged skill"      bash -c "[ ! -L '$ST/cleanup' ] && grep -q 'local edit' '$ST/cleanup/SKILL.md' && grep -q 'SKIP.*cleanup' '$WORK/inst.log'"
check "installer leaves foreign skills alone"            bash -c "[ ! -L '$ST/foreign' ] && [ \"\$(cat '$ST/foreign/SKILL.md')\" = x ]"
check "installer is idempotent"                          bash -c "'$REPO/skills/install.sh' --target '$ST' | grep -c 'same' | grep -q '^[4-9]'"
"$REPO/skills/install.sh" --target "$WORK/copy-target" --copy >/dev/null 2>&1
check "installer --copy makes real directories"          bash -c "[ -d '$WORK/copy-target/review-code' ] && [ ! -L '$WORK/copy-target/review-code' ]"
check "every skill has matching name + a description"    python3 - "$REPO/skills" <<'PY'
import os, re, sys
bad = []
for d in sorted(os.listdir(sys.argv[1])):
    f = os.path.join(sys.argv[1], d, "SKILL.md")
    if not os.path.isfile(f): continue
    text = open(f).read()
    head = text.split("---")[1] if text.startswith("---") else ""
    if not re.search(r"^name:\s*" + re.escape(d) + r"\s*$", head, re.M): bad.append(d + ": name != folder")
    if not re.search(r"^description:\s*\S", head, re.M): bad.append(d + ": no description")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY

echo; echo "== fast: vr tool (no browser, no model: shoot.mjs and claude are stubbed) =="
VRSRC="$HARNESS/modules/web/root/vr"; VRT="$HARNESS/tests/vr"
if ! have node || ! have npm; then skip "node/npm not installed: vr tests"
else
  check "pages.json: viewports, per-page options, file names, validation (config.mjs)" node "$VRT/config.test.mjs" "$VRSRC"
  check "the shipped pages.json resolves to desktop, tablet and mobile for /" bash -c "cd '$VRSRC' && node -e \"import('./config.mjs').then(m=>{const t=m.resolveTargets(JSON.parse(require('fs').readFileSync('pages.json')));if(t.map(x=>x.viewport).join()!=='desktop,tablet,mobile')process.exit(1)})\""
  VRDEPS="$WORK/vr-deps"; mkdir -p "$VRDEPS"; cp "$VRSRC/package.json" "$VRDEPS/"
  if (cd "$VRDEPS" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-audit --no-fund >"$WORK/npm.log" 2>&1); then
    pass "vr dependencies install (playwright, pixelmatch, pngjs)"
    check "vr dependencies import" bash -c "cd '$VRDEPS' && node -e \"import('pngjs').then(()=>import('pixelmatch')).then(()=>import('playwright'))\""

    vrdir() {  # vrdir <name>: a fresh copy of the vr tool with shoot.mjs and claude stubbed; prints its path
      local d="$WORK/vr-$1"; mkdir -p "$d/shots" "$d/bin"
      cp "$VRSRC"/{vr.sh,filter.mjs,config.mjs,rubric.md,pages.json} "$d/"; cp "$VRT/stub-shoot.mjs" "$d/shoot.mjs"; cp "$VRT/png.mjs" "$d/"
      cp "$VRT/claude" "$d/bin/"; ln -s "$VRDEPS/node_modules" "$d/node_modules"; echo '[]' > "$d/claude.out"
      echo "$d"
    }
    png() { (cd "$1" && node png.mjs "${@:2}"); }   # png <dir> <out> <w> <h> [x,y,w,h]
    changed_of() { (cd "$1" && node filter.mjs >/dev/null 2>&1 && python3 -c "import json; print(' '.join(sorted(json.load(open('changed.json')))))"); }
    vrrun() { (cd "$1" && SHOTS="$1/shots" CLAUDE_STUB_LOG="$1/claude.log" CLAUDE_STUB_OUT="$1/claude.out" PATH="$1/bin:$PATH" ./vr.sh http://stub); }

    echo "-- filter.mjs: which screenshots count as changed (threshold: more than 50 differing pixels)"
    F="$(vrdir filter)"; mkdir -p "$F/baseline" "$F/current"
    for n in same noise tiny big gone resized; do png "$F" "baseline/$n.png" 1000 1000; done
    png "$F" current/same.png    1000 1000
    png "$F" current/noise.png   1000 1000 10,10,5,8        # 40 px differ: under the threshold
    png "$F" current/tiny.png    1000 1000 10,10,10,10      # 100 px differ: a small element gone, on a 1,000,000 px image
    png "$F" current/big.png     1000 1000 100,100,100,100  # 10,000 px differ
    png "$F" current/resized.png 1000 1200                  # page got taller
    png "$F" current/extra.png   1000 1000                  # exists only in current/ (new page or new tile)
    CH=" $(changed_of "$F") "
    check "identical image is unchanged"                     bash -c "! echo '$CH' | grep -q ' same.png '"
    check "a difference of 40 px is ignored as noise"        bash -c "! echo '$CH' | grep -q ' noise.png '"
    check "a small real change (100 px) is caught"           bash -c "echo '$CH' | grep -q ' tiny.png '"
    check "a large difference is changed"                    bash -c "echo '$CH' | grep -q ' big.png '"
    check "an image missing from current/ is changed"        bash -c "echo '$CH' | grep -q ' gone.png '"
    check "an image only in current/ is changed (new page or tile)" bash -c "echo '$CH' | grep -q ' extra.png '"
    check "a size mismatch is changed"                       bash -c "echo '$CH' | grep -q ' resized.png '"
    check "VR_MIN_DIFF_PX overrides the threshold"           bash -c "cd '$F' && VR_MIN_DIFF_PX=10 node filter.mjs >/dev/null && grep -q noise.png changed.json"

    echo "-- vr.sh: record, compare, baseline safety, report parsing, exit code"
    R="$(vrdir run)"
    reset() { rm -rf "$R/baseline" "$R/current" "$R/baseline.new" "$R/baseline.copy" "$R/changed.json" "$R/report.json" "$R/raw_report.txt" "$R/claude.log" "$R/shots"/*; }
    reset; png "$R" shots/home__0.png 1000 1000
    (cd "$R" && SHOTS="$R/shots" PATH="$R/bin:$PATH" ./vr.sh --record http://stub >"$WORK/vr.out" 2>&1)
    check "--record writes the baseline"                     bash -c "test -f '$R/baseline/home__0.png' && grep -q 'baseline recorded: 1' '$WORK/vr.out'"
    check "--record leaves no temp folder behind"            test ! -e "$R/baseline.new"
    check "--record does not call the model"                 test ! -e "$R/claude.log"

    bad_shots() { png "$R" shots/home__0.png 1000 1000 100,100,100,100; }   # the "broken deploy"
    reset; png "$R" shots/home__0.png 1000 1000; (cd "$R" && SHOTS="$R/shots" ./vr.sh --record http://stub >/dev/null 2>&1)
    cp "$R/baseline/home__0.png" "$R/baseline.copy"
    bad_shots; echo '[{"file":"home__0.png","severity":4}]' > "$R/claude.out"
    vrrun "$R" >/dev/null 2>&1; first=$?; vrrun "$R" >/dev/null 2>&1; second=$?
    check "a broken build fails the compare"                 test "$first" = 1
    check "re-running does NOT make the broken build the baseline" test "$second" = 1
    check "the baseline is untouched by compare runs"        bash -c "cmp -s '$R/baseline/home__0.png' '$R/baseline.copy' && ! cmp -s '$R/baseline/home__0.png' '$R/current/home__0.png'"
    check "--record again accepts the new build"             bash -c "cd '$R' && SHOTS='$R/shots' ./vr.sh --record http://stub >/dev/null 2>&1 && cmp -s baseline/home__0.png shots/home__0.png"

    reset
    rc=0; (cd "$R" && SHOTS="$R/shots" PATH="$R/bin:$PATH" ./vr.sh http://stub >"$WORK/vr.out" 2>&1) || rc=$?
    check "with no baseline it exits 2 and says to --record" bash -c "[ $rc = 2 ] && grep -q 'vr.sh --record' '$WORK/vr.out'"
    rc=0; (cd "$R" && ./vr.sh >"$WORK/vr.out" 2>&1) || rc=$?
    check "with no URL it prints usage and exits 2"          bash -c "[ $rc = 2 ] && grep -q usage '$WORK/vr.out'"

    reset; png "$R" shots/home__0.png 1000 1000; (cd "$R" && SHOTS="$R/shots" ./vr.sh --record http://stub >/dev/null 2>&1)
    rc=0; (cd "$R" && SHOTS="$R/nonexistent" ./vr.sh --record http://stub >/dev/null 2>&1) || rc=$?
    check "a failed --record keeps the old baseline"         bash -c "[ $rc != 0 ] && test -f '$R/baseline/home__0.png' && test ! -e '$R/baseline.new'"

    # a baseline exists (home__0 plain); the build under test is given by shots/
    prep() { reset; mkdir -p "$R/baseline"; png "$R" baseline/home__0.png 1000 1000; png "$R" shots/home__0.png 1000 1000 100,100,100,100; }
    run_with() { prep; printf '%s' "$1" > "$R/claude.out"; vrrun "$R" >"$WORK/vr.out" 2>&1; echo $?; }
    sev() { printf '[{"file":"home__0.png","verdict":"x","severity":%s,"findings":[]}]' "$1"; }
    nothing_changed() {
      reset; mkdir -p "$R/baseline"; png "$R" baseline/home__0.png 1000 1000; png "$R" shots/home__0.png 1000 1000
      vrrun "$R" >"$WORK/vr.out" 2>&1 && grep -q 'nothing changed' "$WORK/vr.out" && [ ! -e "$R/claude.log" ] && [ "$(cat "$R/report.json")" = "[]" ]
    }
    check "nothing changed: passes without calling the model" nothing_changed
    check "the model is pointed at rubric.md and changed.json" bash -c "[ \"$(run_with '[]')\" = 0 ] && grep -q 'rubric.md' '$R/claude.log' && grep -q 'changed.json' '$R/claude.log'"
    check "severity 2 passes (exit 0)"                       bash -c "[ \"$(run_with "$(sev 2)")\" = 0 ]"
    check "severity 3 fails the run (exit 1)"                bash -c "[ \"$(run_with "$(sev 3)")\" = 1 ]"
    check "severity 5 fails the run (exit 1)"                bash -c "[ \"$(run_with "$(sev 5)")\" = 1 ]"
    check "worst severity is the one that gates"             bash -c "[ \"$(run_with '[{"file":"a","severity":1},{"file":"b","severity":4}]')\" = 1 ]"
    check "an empty array from the model passes"             bash -c "[ \"$(run_with '[]')\" = 0 ] && grep -q '0 pages compared' '$WORK/vr.out'"
    check "JSON inside markdown fences is extracted"         bash -c "[ \"$(run_with "$(printf '```json\n%s\n```' "$(sev 2)")")\" = 0 ] && python3 -c \"import json; assert json.load(open('$R/report.json'))[0]['file']=='home__0.png'\""
    check "JSON surrounded by prose is extracted"            bash -c "[ \"$(run_with "Here is the report: $(sev 3) Hope that helps.")\" = 1 ]"
    check "output with no JSON array fails and shows the text" bash -c "[ \"$(run_with 'I could not open the images.')\" = 1 ] && grep -q 'No JSON array found' '$WORK/vr.out' && grep -q 'could not open' '$WORK/vr.out'"
    check "a record with no severity counts as 0"            bash -c "[ \"$(run_with '[{"file":"a","verdict":"pass"}]')\" = 0 ]"
    stale_files_removed() { prep; echo stale > "$R/report.json"; echo stale > "$R/raw_report.txt"; printf 'no json' > "$R/claude.out"; vrrun "$R" >/dev/null 2>&1; [ ! -f "$R/report.json" ] && [ "$(cat "$R/raw_report.txt")" = "no json" ]; }
    check "a stale report.json is removed when a run fails to parse" stale_files_removed
  else
    fail "vr dependencies install"; tail -8 "$WORK/npm.log" | sed 's/^/        /'
  fi
fi

echo; echo "== fast: docs =="
check "relative markdown links resolve" python3 - "$REPO" <<'PY'
import os, re, subprocess, sys
root = sys.argv[1]; bad = []
files = subprocess.run(["git", "-C", root, "ls-files", "*.md"], capture_output=True, text=True).stdout.split()
for f in files:
    if "fixtures/app" in f: continue
    for m in re.finditer(r"\]\(([^)#\s]+)(#[^)]*)?\)", open(os.path.join(root, f)).read()):
        t = m.group(1)
        if t.startswith(("http", "mailto:")): continue
        if not os.path.exists(os.path.normpath(os.path.join(root, os.path.dirname(f), t))): bad.append(f"{f} -> {t}")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
if have gitleaks; then check "no secrets in the repo (gitleaks)" bash -c "cd '$REPO' && gitleaks detect --no-git -s . --no-banner -l error"; else skip "gitleaks not installed"; fi

if [ "$UPDATE" = 1 ]; then echo; echo "snapshots regenerated — review: git -C '$REPO' diff --stat harness/tests/golden"; exit 0; fi

# ============================================================ FULL TIER
if [ "$TIER" = full ]; then
  for t in docker semgrep gitleaks lefthook node npm go; do have "$t" || { echo "full tier needs '$t' on the host"; exit 2; }; done
  docker info >/dev/null 2>&1 || { echo "full tier needs a running Docker daemon"; exit 2; }
  dc() { local d="$1"; shift; (cd "$d" && WEB_PORT="$(cat "$d/.port")" docker compose "$@"); }
  wait_http() { for _ in $(seq 1 60); do [ "$(curl -s -o /dev/null -w '%{http_code}' "$1" 2>/dev/null)" = 200 ] && return 0; sleep 2; done; return 1; }
  mcp_handshake() { echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | "$@" 2>/dev/null | grep '^{' | python3 -c "import sys,json; t=[x['name'] for x in json.loads(sys.stdin.readline())['result']['tools']]; assert 'xtrace' in t and 'xstep' in t, t"; }
  export -f dc mcp_handshake

  echo; echo "== full: the demo app end to end (php + go + web + postgres) =="
  P="$WORK/h-main"; mkdir -p "$P"; free_port > "$P/.port"; export WEB_PORT; WEB_PORT="$(cat "$P/.port")"
  rsync -a "$HARNESS/fixtures/app/" "$P/"
  cp "$HARNESS/fixtures/history/TaxResolver.buggy.php" "$P/app-php/src/Domain/TaxResolver.php"
  git -C "$P" init -q -b main; gitc "$P" add -A; gitc "$P" commit -q -m "feat: add PHP invoicing domain model" --no-verify
  COMPOSE_DIRS+=("$P")
  check "bootstrap --install (builds images, starts containers)" "$HARNESS/bootstrap.sh" "$P" --php=app-php --go=go-api --web=web --db postgres --install
  check "re-run after install is idempotent"                      bash -c "'$HARNESS/bootstrap.sh' '$P' --php=app-php --go=go-api --web=web --db postgres | grep -q 'Summary: 0 created, 0 merged'"

  echo "-- hooks"
  printf 'AWS_SECRET_ACCESS_KEY="AKIA%s"\n' ZZQ3DG7KL2MN9XPQ > "$P/leak.txt"; git -C "$P" add leak.txt
  if gitc "$P" commit -q -m "should be blocked" >/dev/null 2>&1; then fail "gitleaks blocks a leaked secret"; gitc "$P" reset -q --hard HEAD~1; else pass "gitleaks blocks a leaked secret"; fi
  git -C "$P" reset -q leak.txt; rm -f "$P/leak.txt"
  git -C "$P" add -A
  check "harness files pass pre-commit (gitleaks + semgrep)" gitc "$P" commit -q -m "chore: add harness"

  echo "-- PHP in the container"
  check "container runs the pinned PHP (8.3)"      dc "$P" exec -T app php -r 'exit(PHP_VERSION_ID >= 80300 && PHP_VERSION_ID < 80400 ? 0 : 1);'
  check "container user is non-root"               dc "$P" exec -T app sh -c '[ "$(id -u)" != 0 ]'
  check "composer install on the bind mount"       dc "$P" exec -T app composer install -q --no-interaction
  cp "$HARNESS/fixtures/app/app-php/src/Domain/TaxResolver.php" "$P/app-php/src/Domain/TaxResolver.php"
  check "phpunit (bare command, harness phpunit.xml.dist)" dc "$P" exec -T app vendor/bin/phpunit
  check "phpstan (harness config)"                 dc "$P" exec -T app vendor/bin/phpstan analyse -c phpstan.neon.dist --no-progress
  check "Xdebug is loaded"                         bash -c "dc '$P' exec -T app php -m | grep -qi '^xdebug'"
  check "Xdebug MCP handshake, no TTY noise"       bash -c "mcp_handshake dc '$P' exec -T app xdebug-mcp"
  check "xtrace through the MCP traces a real run" bash -c "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"xtrace\",\"arguments\":{\"script\":\"vendor/bin/phpunit\"}}}' | dc '$P' exec -T app xdebug-mcp 2>/dev/null | grep -q 'Exit Code\\*\\*: 0'"
  check ".cursor/mcp.json xdebug entry works exactly as Cursor would spawn it" bash -c "cd '$P' && python3 -c \"import json; e=json.load(open('.cursor/mcp.json'))['mcpServers']['xdebug']; print(' '.join([e['command']]+e['args']))\" > '$WORK/mcp.cmd' && mcp_handshake env WEB_PORT=$WEB_PORT bash -c \"\$(cat '$WORK/mcp.cmd')\""
  check "real database connection from the app container (PDO/pgsql)" dc "$P" exec -T app php -r '$p=new PDO("pgsql:host=".getenv("DB_HOST").";dbname=".getenv("DB_NAME"),getenv("DB_USER"),getenv("DB_PASSWORD")); exit($p->query("select 1")->fetchColumn()==1?0:1);'

  echo "-- Go on the host"
  check "go test -race" bash -c "cd '$P/go-api' && go test -race ./..."

  echo "-- Node in the container, Playwright on the host"
  check "dev server answers on the published port" wait_http "http://localhost:$WEB_PORT/"
  check "web build inside the container"           dc "$P" exec -T web npm run build
  check "playwright seed tests (host, against the container)" bash -c "cd '$P/e2e' && BASE_URL=http://localhost:$WEB_PORT npx playwright test"
  rm -rf "$P/web/dist" "$P/e2e/test-results"

  echo "-- evals + whole-repo scan"
  gitc "$P" add -A; check "bug-fix commit passes hooks" gitc "$P" commit -q -m "fix: TaxResolver looks up tax rate by country, not unbackfilled tax_region"
  check "harvest finds the seeded bug" bash -c "cd '$P' && ./evals/harvest.sh && [ \"\$(find evals/cases -name diff.patch | wc -l)\" -ge 1 ]"
  if [ "$WITH_LLM" = 1 ]; then check "evals/run.sh end to end (claude -p)" bash -c "cd '$P' && MODEL=sonnet ./evals/run.sh"; fi
  check "semgrep clean over the whole project (incl. Dockerfile + compose)" bash -c "cd '$P' && semgrep --config=auto --error --quiet ."
  dc "$P" down -v --remove-orphans >/dev/null 2>&1

  echo; echo "== full: two projects, different versions, running side by side =="
  mkver() {  # mkver <name> <php> <node> <db>
    local d="$WORK/$1"; mkdir -p "$d/api" "$d/ui"; free_port > "$d/.port"
    printf '{"name":"ui","private":true,"scripts":{"dev":"node server.js"}}\n' > "$d/ui/package.json"
    printf 'require("http").createServer((q,s)=>s.end("ok")).listen(5173,"0.0.0.0");\n' > "$d/ui/server.js"
    boot "$d" --php=api --web=ui --db "$4" --php-version "$2" --node-version "$3" || return 1
    COMPOSE_DIRS+=("$d")
    dc "$d" up -d --build >"$WORK/up-$1.log" 2>&1
  }
  mkver h-ver-a 8.2 20 mysql:8.4;  UPA=$?
  mkver h-ver-b 8.4 22 postgres:16; UPB=$?
  A="$WORK/h-ver-a"; B="$WORK/h-ver-b"
  running() { dc "$1" ps --status running -q | wc -l | tr -d ' '; }
  export -f running
  check "both projects are up at the same time (3 services each)" bash -c "[ $UPA -eq 0 ] && [ $UPB -eq 0 ] && [ \"\$(running '$A')\" = 3 ] && [ \"\$(running '$B')\" = 3 ]"
  phpv()  { dc "$1" exec -T app php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'; }
  nodev() { dc "$1" exec -T web node -p 'process.versions.node.split(".")[0]'; }
  export -f phpv nodev
  check "project A runs PHP 8.2" bash -c "[ \"\$(phpv '$A')\" = 8.2 ]"
  check "project B runs PHP 8.4" bash -c "[ \"\$(phpv '$B')\" = 8.4 ]"
  check "project A runs Node 20" bash -c "[ \"\$(nodev '$A')\" = 20 ]"
  check "project B runs Node 22" bash -c "[ \"\$(nodev '$B')\" = 22 ]"
  check "A: real MySQL connection (PDO)"    dc "$A" exec -T app php -r '$p=new PDO("mysql:host=".getenv("DB_HOST").";dbname=".getenv("DB_NAME"),getenv("DB_USER"),getenv("DB_PASSWORD")); exit($p->query("select 1")->fetchColumn()==1?0:1);'
  check "B: real Postgres connection (PDO)" dc "$B" exec -T app php -r '$p=new PDO("pgsql:host=".getenv("DB_HOST").";dbname=".getenv("DB_NAME"),getenv("DB_USER"),getenv("DB_PASSWORD")); exit($p->query("select 1")->fetchColumn()==1?0:1);'
  check "A: Xdebug MCP handshake" bash -c "mcp_handshake dc '$A' exec -T app xdebug-mcp"
  check "B: Xdebug MCP handshake" bash -c "mcp_handshake dc '$B' exec -T app xdebug-mcp"
  check "A: web answers on its own port" wait_http "http://localhost:$(cat "$A/.port")/"
  check "B: web answers on its own port" wait_http "http://localhost:$(cat "$B/.port")/"
  dc "$A" down -v --remove-orphans >/dev/null 2>&1; dc "$B" down -v --remove-orphans >/dev/null 2>&1
fi

echo
echo "tier: $TIER   passed: $PASSES   failed: $FAILS"
if [ "$FAILS" -eq 0 ]; then echo "ALL PASSED"; else echo "$FAILS FAILED"; exit 1; fi
