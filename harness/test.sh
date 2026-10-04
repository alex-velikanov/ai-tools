#!/usr/bin/env bash
# Tests for the harness and the skills installer.
#
#   ./test.sh                  fast tier: seconds, starts no containers. Golden snapshots of generated
#                              files, compose validity, error paths, idempotency, skills installer, the vr tool
#                              (pixel filter, baseline rotation, report parsing and exit code), doc links.
#   ./test.sh full             fast tier + real containers: the demo app end to end, and two projects with
#                              different PHP / Node / database versions running side by side.
#   ./test.sh judge            calibrate the vr judge: the real `claude -p` over labelled before/after pages (needs claude,
#                              node and a Chromium; ~2 minutes; uses plan tokens). Fails if it misses broken pages or flags fine ones.
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
  fast|full|judge) TIER="$a" ;; --with-llm) WITH_LLM=1 ;; --keep) KEEP=1 ;; --update-golden) UPDATE=1 ;;
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
for f in "$HARNESS/bootstrap.sh" "$HARNESS/test.sh" "$REPO/skills/install.sh" "$HARNESS/core/files/evals/run.sh" "$HARNESS/core/files/evals/harvest.sh" "$HARNESS/modules/web/root/vr/vr.sh" "$HARNESS/tests/vr/judge/run.sh"; do
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
check "judge severity normalization in merge and re-check" python3 "$VRT/report.test.py" "$VRSRC"
check "html_report.py: sections, images, escaping, odd input, re-runs" python3 "$VRT/html_report.test.py" "$VRSRC"
for f in report.py html_report.py; do check "python syntax: $f" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$VRSRC/$f"; done
if ! have node || ! have npm; then skip "node/npm not installed: vr tests"
else
  check "pages.json: viewports, per-page options, file names, validation (config.mjs)" node "$VRT/config.test.mjs" "$VRSRC"
  check "judge calibration: scoring and case labels (judge/score.mjs)" node "$VRT/judge/score.test.mjs"
  check "--discover link rules: normalising, skips, sitemap, new paths (links.mjs)"      node "$VRT/links.test.mjs" "$VRSRC"
  check "the shipped pages.json resolves to desktop, tablet and mobile for /" bash -c "cd '$VRSRC' && node -e \"import('./config.mjs').then(m=>{const t=m.resolveTargets(JSON.parse(require('fs').readFileSync('pages.json')));if(t.map(x=>x.viewport).join()!=='desktop,tablet,mobile')process.exit(1)})\""
  VRDEPS="$WORK/vr-deps"; mkdir -p "$VRDEPS"; cp "$VRSRC/package.json" "$VRDEPS/"
  if (cd "$VRDEPS" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-audit --no-fund >"$WORK/npm.log" 2>&1); then
    pass "vr dependencies install (playwright, pixelmatch, pngjs)"
    check "vr dependencies import" bash -c "cd '$VRDEPS' && node -e \"import('pngjs').then(()=>import('pixelmatch')).then(()=>import('playwright'))\""

    vrdir() {  # vrdir <name>: a fresh copy of the vr tool with shoot.mjs and claude stubbed; prints its path
      local d="$WORK/vr-$1"; mkdir -p "$d/shots" "$d/bin"
      cp "$VRSRC"/{vr.sh,filter.mjs,config.mjs,report.py,html_report.py,rubric.md,pages.json} "$d/"; cp "$VRT/stub-shoot.mjs" "$d/shoot.mjs"; cp "$VRT/png.mjs" "$d/"
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
    png "$F" baseline/wentblank.png 1000 1000 100,100,300,300; png "$F" current/wentblank.png 1000 1000      # real page -> flat white
    png "$F" baseline/stillblank.png 1000 1000;                png "$F" current/stillblank.png 1000 1000 10,10,12,12   # was already blank
    png "$F" baseline/huge.png 1000 1000;                      png "$F" current/huge.png 1000 1000 0,0,1000,600       # 60% of the page differs
    CH=" $(changed_of "$F") "
    check "identical image is unchanged"                     bash -c "! echo '$CH' | grep -q ' same.png '"
    check "a difference of 40 px is ignored as noise"        bash -c "! echo '$CH' | grep -q ' noise.png '"
    check "a small real change (100 px) is caught"           bash -c "echo '$CH' | grep -q ' tiny.png '"
    check "a large difference is changed"                    bash -c "echo '$CH' | grep -q ' big.png '"
    check "an image missing from current/ is changed"        bash -c "echo '$CH' | grep -q ' gone.png '"
    check "an image only in current/ is changed (new page or tile)" bash -c "echo '$CH' | grep -q ' extra.png '"
    check "a size mismatch is changed"                       bash -c "echo '$CH' | grep -q ' resized.png '"
    check "a page that went flat/blank is listed in blank.json" bash -c "python3 -c \"import json; assert json.load(open('$F/blank.json'))==['wentblank.png'], open('$F/blank.json').read()\""
    check "a page that was already blank, or just changed a lot, is not" bash -c "echo '$CH' | grep -q ' stillblank.png ' && ! grep -q 'stillblank\|big.png' '$F/blank.json'"
    check "diffs.json gives the % of pixels that differ (huge ~60, big ~1, same 0)" bash -c "python3 -c \"import json; d=json.load(open('$F/diffs.json')); assert abs(d['huge.png']-60)<0.2 and abs(d['big.png']-1)<0.2 and d['same.png']==0, d\""
    check "diffs.json has no figure for size mismatches or one-sided files" bash -c "python3 -c \"import json; d=json.load(open('$F/diffs.json')); assert 'resized.png' not in d and 'extra.png' not in d and 'gone.png' not in d, d\""
    check "VR_MIN_DIFF_PX overrides the threshold"           bash -c "cd '$F' && VR_MIN_DIFF_PX=10 node filter.mjs >/dev/null && grep -q noise.png changed.json"

    pngdims() { python3 -c "import struct,sys; d=open(sys.argv[1],'rb').read(); assert d[:8]==b'\\x89PNG\\r\\n\\x1a\\n'; print(*struct.unpack('>II', d[16:24]))" "$1"; }
    red_pixels() { (cd "$F" && node -e "const {PNG}=require('pngjs'); const p=PNG.sync.read(require('fs').readFileSync('diff/'+process.argv[1])); let n=0; for(let i=0;i<p.data.length;i+=4) if(p.data[i]===255&&p.data[i+1]===0&&p.data[i+2]===0) n++; console.log(n)" "$1"); }
    mkdir -p "$F/diff"; echo stale > "$F/diff/stale.png"; (cd "$F" && node filter.mjs >/dev/null)
    check "diff/ holds a valid PNG of the same size for each changed same-size pair" bash -c "[ \"\$($(declare -f pngdims) ; pngdims '$F/diff/big.png')\" = '1000 1000' ] && [ \"\$($(declare -f pngdims) ; pngdims '$F/diff/huge.png')\" = '1000 1000' ]"
    check "the diff image marks the differing pixels (big: about 10,000)" bash -c "n=\$($(declare -f red_pixels); F='$F'; red_pixels big.png); [ \"\$n\" -gt 5000 ] && [ \"\$n\" -lt 15000 ]"
    check "no diff image for unchanged, noise-level, resized or one-sided files" bash -c "cd '$F/diff' && [ ! -e same.png ] && [ ! -e noise.png ] && [ ! -e resized.png ] && [ ! -e gone.png ] && [ ! -e extra.png ]"
    check "diff/ is rebuilt on every run (stale files are removed)" test ! -e "$F/diff/stale.png"

    invalid_threshold() {
      local value
      for value in nonsense NaN Infinity -Infinity -1; do
        if (cd "$F" && VR_MIN_DIFF_PX="$value" node filter.mjs >"$WORK/filter.out" 2>&1); then return 1; fi
        grep -q 'VR_MIN_DIFF_PX must be finite and non-negative' "$WORK/filter.out" || return 1
      done
    }
    check "invalid pixel thresholds fail with a clear error" invalid_threshold
    check "zero is a valid pixel threshold" bash -c "cd '$F' && VR_MIN_DIFF_PX=0 node filter.mjs >/dev/null && grep -q noise.png changed.json"
    check "blank pages bypass even a threshold above the whole image size" bash -c "cd '$F' && VR_MIN_DIFF_PX=1000001 node filter.mjs >/dev/null && python3 -c \"import json; assert 'wentblank.png' in json.load(open('changed.json')); assert json.load(open('blank.json'))==['wentblank.png']; assert 'big.png' not in json.load(open('changed.json'))\""

    echo "-- vr.sh: record, compare, baseline safety, report parsing, exit code"
    R="$(vrdir run)"
    reset() { rm -rf "$R/diff" "$R/report" "$R/baseline" "$R/current" "$R/baseline.new" "$R/baseline.copy" "$R/changed.json" "$R/report.json" "$R/raw_report.txt" "$R/claude.log" "$R/claude.log.calls" "$R/claude.out".[0-9]* "$R/blank.json" "$R/diffs.json" "$R/warnings.json" "$R/raw_report".*.txt "$R/shots"/*; }
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
    rc=0; (cd "$R" && ./vr.sh --discover >"$WORK/vr.out" 2>&1) || rc=$?
    check "--discover with no URL prints usage and exits 2"  bash -c "[ $rc = 2 ] && grep -q 'discover' '$WORK/vr.out'"

    reset; png "$R" shots/home__0.png 1000 1000; (cd "$R" && SHOTS="$R/shots" ./vr.sh --record http://stub >/dev/null 2>&1)
    rc=0; (cd "$R" && SHOTS="$R/nonexistent" ./vr.sh --record http://stub >/dev/null 2>&1) || rc=$?
    check "a failed --record keeps the old baseline"         bash -c "[ $rc != 0 ] && test -f '$R/baseline/home__0.png' && test ! -e '$R/baseline.new'"

    # a baseline exists (home__0 plain); the build under test is given by shots/
    prep() { reset; mkdir -p "$R/baseline"; png "$R" baseline/home__0.png 1000 1000; png "$R" shots/home__0.png 1000 1000 100,100,100,100; }
    run_with() { prep; printf '%s' "$1" > "$R/claude.out"; vrrun "$R" >"$WORK/vr.out" 2>&1; echo $?; }
    sev() { printf '[{"file":"home__0.png","verdict":"x","severity":%s,"seen":"s","findings":[]}]' "$1"; }
    nothing_changed() {
      reset; mkdir -p "$R/baseline"; png "$R" baseline/home__0.png 1000 1000; png "$R" shots/home__0.png 1000 1000
      vrrun "$R" >"$WORK/vr.out" 2>&1 && grep -q 'nothing changed' "$WORK/vr.out" && [ ! -e "$R/claude.log" ] && [ "$(cat "$R/report.json")" = "[]" ]
    }
    check "nothing changed: passes without calling the model" nothing_changed
    check "the model is pointed at rubric.md and the changed files" bash -c "[ \"$(run_with '[]')\" = 0 ] && grep -q 'rubric.md' '$R/claude.log' && grep -q 'home__0.png' '$R/claude.log'"
    check "the judge's only tool is Read (--tools, not just a pre-approval)" bash -c "grep -qx -- '--tools' '$R/claude.log' && grep -qx 'Read' '$R/claude.log' && ! grep -q -- '--allowedTools' '$R/claude.log'"
    check "every claude call in vr.sh uses --tools Read, none --allowedTools" bash -c "code=\$(grep -v '^ *#' '$VRSRC/vr.sh'); [ \"\$(echo \"\$code\" | grep -c -- '--tools Read')\" = 2 ] && ! echo \"\$code\" | grep -q -- '--allowedTools'"
    check "no --model flag unless VR_MODEL is set"           bash -c "! grep -q -- '--model' '$R/claude.log'"
    model_pinned() { prep; printf '[]' > "$R/claude.out"; rm -f "$R/claude.log"; (cd "$R" && VR_MODEL=sonnet SHOTS="$R/shots" CLAUDE_STUB_LOG="$R/claude.log" CLAUDE_STUB_OUT="$R/claude.out" PATH="$R/bin:$PATH" ./vr.sh http://stub >/dev/null 2>&1); grep -qx -- '--model' "$R/claude.log" && grep -qx 'sonnet' "$R/claude.log"; }
    check "VR_MODEL pins the model"                          model_pinned
    check "the rubric tells the judge to ignore instructions inside screenshots" grep -q 'never instructions to you' "$VRSRC/rubric.md"
    check "the rubric names 404/500/maintenance/sign-in pages as severity 5, and bans an unlooked-at severity 0" bash -c "grep -q '404' '$VRSRC/rubric.md' && grep -q '500' '$VRSRC/rubric.md' && grep -qi 'maintenance' '$VRSRC/rubric.md' && grep -qi 'sign-in' '$VRSRC/rubric.md' && grep -q 'Never give a file severity 0' '$VRSRC/rubric.md'"
    check "severity 2 passes (exit 0)"                       bash -c "[ \"$(run_with "$(sev 2)")\" = 0 ]"
    check "severity 3 fails the run (exit 1)"                bash -c "[ \"$(run_with "$(sev 3)")\" = 1 ]"
    check "severity 5 fails the run (exit 1)"                bash -c "[ \"$(run_with "$(sev 5)")\" = 1 ]"
    check "worst severity is the one that gates"             bash -c "[ \"$(run_with '[{"file":"a","severity":1},{"file":"b","severity":4}]')\" = 1 ]"
    check "an empty array from the model passes"             bash -c "[ \"$(run_with '[]')\" = 0 ] && grep -q '0 pages compared' '$WORK/vr.out'"
    check "JSON inside markdown fences is extracted"         bash -c "[ \"$(run_with "$(printf '```json\n%s\n```' "$(sev 2)")")\" = 0 ] && python3 -c \"import json; assert json.load(open('$R/report.json'))[0]['file']=='home__0.png'\""
    check "JSON surrounded by prose is extracted"            bash -c "[ \"$(run_with "Here is the report: $(sev 3) Hope that helps.")\" = 1 ]"
    check "brackets in the prose around the JSON do not break extraction" bash -c "[ \"$(run_with "Checked [2 pages]. Result: $(sev 3) See note [1].")\" = 1 ] && python3 -c \"import json; assert json.load(open('$R/report.json'))[0]['severity']==3\""
    check "brackets with no report inside fail cleanly, without a traceback" bash -c "[ \"$(run_with 'Checked [2 pages], see [1].')\" = 1 ] && grep -q 'No JSON array found' '$WORK/vr.out' && ! grep -q Traceback '$WORK/vr.out'"
    check "output with no JSON array fails and shows the text" bash -c "[ \"$(run_with 'I could not open the images.')\" = 1 ] && grep -q 'No JSON array found' '$WORK/vr.out' && grep -q 'could not open' '$WORK/vr.out'"
    check "a record with no severity counts as 0"            bash -c "[ \"$(run_with '[{"file":"a","verdict":"pass"}]')\" = 0 ]"
    blank_case() {  # blank_case <canned model reply>: baseline is a real page, the build under test is flat white
      reset; mkdir -p "$R/baseline"; png "$R" baseline/home__0.png 1000 1000 100,100,300,300; png "$R" shots/home__0.png 1000 1000
      printf '%s' "$1" > "$R/claude.out"; vrrun "$R" >"$WORK/vr.out" 2>&1; echo $?
    }
    check "a blank page fails even if the judge says severity 0" bash -c "[ \"$(blank_case '[{"file":"home__0.png","verdict":"pass","severity":0,"seen":"s","findings":[]}]')\" = 1 ] && python3 -c \"import json; r=json.load(open('$R/report.json'))[0]; assert r['severity']==5 and r['verdict']=='fail' and len(r['findings'])==1\""
    check "a blank page fails even if the judge leaves it out"   bash -c "[ \"$(blank_case '[]')\" = 1 ] && python3 -c \"import json; r=json.load(open('$R/report.json')); assert r[0]['file']=='home__0.png' and r[0]['severity']==5\""
    check "a judge verdict already at severity 5 is kept as is"   bash -c "[ \"$(blank_case '[{"file":"home__0.png","verdict":"fail","severity":5,"seen":"s","findings":[{"what":"x"}]}]')\" = 1 ] && python3 -c \"import json; r=json.load(open('$R/report.json'))[0]; assert len(r['findings'])==1\""
    echo "-- vr.sh: big-diff warnings, unjudged files, batching"
    big_diff() {  # big_diff <canned reply> [extra env]: 51% of the pixels differ (not blank)
      reset; mkdir -p "$R/baseline"; png "$R" baseline/home__0.png 1000 1000 100,100,300,300; png "$R" shots/home__0.png 1000 1000 0,0,1000,600
      printf '%s' "$1" > "$R/claude.out"; env ${2:-X=1} bash -c "cd '$R' && SHOTS='$R/shots' CLAUDE_STUB_LOG='$R/claude.log' CLAUDE_STUB_OUT='$R/claude.out' PATH='$R/bin:'\$PATH ./vr.sh http://stub" >"$WORK/vr.out" 2>&1; echo $?
    }
    warned() { python3 -c "import json; w=json.load(open('$R/warnings.json')); assert [x['file'] for x in w]==['home__0.png'], w"; }
    check "judge says 0 but 51% of the pixels differ: warns, exit code unchanged" bash -c "$(declare -f warned); R='$R'; [ \"$(big_diff '[{"file":"home__0.png","verdict":"pass","severity":0,"seen":"s","findings":[]}]')\" = 0 ] && grep -q '^WARNING home__0.png: 51% of pixels differ' '$WORK/vr.out' && warned"
    check "no warning when the judge already fails the page"                 bash -c "[ \"$(big_diff '[{"file":"home__0.png","verdict":"fail","severity":4,"seen":"s","findings":[]}]')\" = 1 ] && [ \"\$(cat '$R/warnings.json' | tr -d ' \n')\" = '[]' ]"
    check "no warning below the threshold (VR_WARN_DIFF_PCT=70)"              bash -c "[ \"$(big_diff '[{"file":"home__0.png","verdict":"pass","severity":0,"seen":"s","findings":[]}]' VR_WARN_DIFF_PCT=70)\" = 0 ] && [ \"\$(cat '$R/warnings.json' | tr -d ' \n')\" = '[]' ]"
    check "a lower threshold warns on a smaller diff (VR_WARN_DIFF_PCT=1)"     bash -c "$(declare -f warned); R='$R'; [ \"$(big_diff '[{"file":"home__0.png","verdict":"pass","severity":2,"seen":"s","findings":[]}]' VR_WARN_DIFF_PCT=1)\" = 0 ] && warned"
    check "a changed file the judge never mentions is warned about"            bash -c "[ \"$(run_with '[]')\" = 0 ] && grep -q 'no verdict' '$R/warnings.json'"

    multi() {  # multi <n> <batch size> [reply for call 1] [reply for call 2] ...: n changed files, judged <batch> at a time
      local n=$1 b=$2; shift 2; reset
      mkdir -p "$R/baseline"; for i in $(seq 1 "$n"); do png "$R" "baseline/f$i.png" 1000 1000; png "$R" "shots/f$i.png" 1000 1000 10,10,$((10+i*5)),40; done
      echo '[]' > "$R/claude.out"; local k=1; for r in "$@"; do printf '%s' "$r" > "$R/claude.out.$k"; k=$((k+1)); done
      VR_BATCH=$b vrrun "$R" >"$WORK/vr.out" 2>&1; echo $?
    }
    calls() { wc -l < "$R/claude.log.calls" | tr -d ' '; }
    ok() { printf '[{"file":"f%s.png","verdict":"pass","severity":0,"seen":"s","findings":[]}]' "$1"; }
    rep() { local out="" ; for i in "$@"; do out="$out${out:+,}{\"file\":\"f$i.png\",\"verdict\":\"pass\",\"severity\":${SEV:-0},\"seen\":\"s\",\"findings\":[]}"; done; printf '[%s]' "$out"; }
    check "5 files, batch 2: three judge calls"                                bash -c "multi_out=\"$(multi 5 2 "$(rep 1 2)" "$(rep 3 4)" "$(rep 5)")\"; [ \"\$multi_out\" = 0 ] && [ \"$(calls)\" = 3 ]"
    check "each call is asked about only its own files"                         bash -c "grep -c 'f1.png f2.png' '$R/claude.log' | grep -q 1 && ! grep 'f1.png f2.png' '$R/claude.log' | grep -q 'f3.png' && grep -q 'f5.png' '$R/claude.log'"
    check "the batches' reports are merged into one report.json"               bash -c "python3 -c \"import json; r=json.load(open('$R/report.json')); assert sorted(x['file'] for x in r)==['f1.png','f2.png','f3.png','f4.png','f5.png'], r\""
    check "the default batch size is 6: 5 files go in one call"                bash -c "[ \"$(multi 5 6 "$(rep 1 2 3 4 5)")\" = 0 ] && [ \"$(calls)\" = 1 ]"
    check "a finding in a later batch still fails the run"                      bash -c "[ \"$(SEV=4 multi 5 2 "$(SEV=0 rep 1 2)" "$(SEV=0 rep 3 4)" "$(SEV=4 rep 5)")\" = 1 ]"
    check "a batch with no JSON fails the run and names its reply file"        bash -c "[ \"$(multi 5 2 "$(rep 1 2)" 'sorry, cannot open images' "$(rep 5)")\" = 1 ] && grep -q 'raw_report.2.txt' '$WORK/vr.out'"
    check "a file the judge dropped from its batch is warned about"            bash -c "[ \"$(multi 3 3 "$(rep 1 2)")\" = 0 ] && python3 -c \"import json; w=json.load(open('$R/warnings.json')); assert [x['file'] for x in w]==['f3.png'], w\""

    echo "-- vr.sh: second look at suspect verdicts"
    F1='[{"file":"home__0.png","verdict":"pass","severity":0,"findings":[]}]'                       # no "seen"
    S0='[{"file":"home__0.png","verdict":"pass","severity":0,"seen":"s","findings":[]}]'
    S4='[{"file":"home__0.png","verdict":"fail","severity":4,"seen":"a broken page","findings":[{"what":"it is broken"}]}]'
    S2='[{"file":"home__0.png","verdict":"fail","severity":2,"findings":[]}]'
    # second <first reply> <second reply> [env assignment]: a 1% diff on home__0.png (under the re-check threshold)
    second() { prep; printf '%s' "$1" > "$R/claude.out"; printf '%s' "$2" > "$R/claude.out.2"; env ${3:-X=1} bash -c "cd '$R' && SHOTS='$R/shots' CLAUDE_STUB_LOG='$R/claude.log' CLAUDE_STUB_OUT='$R/claude.out' PATH='$R/bin:'\$PATH ./vr.sh http://stub" >"$WORK/vr.out" 2>&1; echo $?; }
    json() { python3 -c "import json,sys; d=json.load(open('$R/$1')); $2"; }
    t_no_recheck()   { [ "$(second "$S0" "$S4")" = 0 ] && [ "$(calls)" = 1 ]; }
    t_recheck_raises() { [ "$(second "$F1" "$S4")" = 1 ] && [ "$(calls)" = 2 ] && json report.json "r=d[0]; assert r['severity']==4 and r['first_severity']==0 and 'rechecked' in r, r"; }
    t_recheck_prompt() { second "$F1" "$S0" >/dev/null; grep -q 'independent second look' "$R/claude.log" && [ "$(grep -c 'home__0.png' "$R/claude.log")" -ge 2 ]; }
    t_never_lowers()   { [ "$(second "$S2" "$S0")" = 0 ] && json report.json "r=d[0]; assert r['severity']==2 and r['first_severity']==2, r"; }
    t_bad_recheck()    { [ "$(second "$F1" "I could not open it.")" = 0 ] && json warnings.json "assert any('nothing usable' in w['warning'] for w in d), d" && json report.json "assert d[0]['severity']==0"; }
    t_bad_recheck_keeps_fail() { [ "$(second '[{"file":"home__0.png","verdict":"fail","severity":4,"findings":[]}]' "no json")" = 1 ]; }
    t_big_diff_recheck() { reset; mkdir -p "$R/baseline"; png "$R" baseline/home__0.png 1000 1000 100,100,300,300; png "$R" shots/home__0.png 1000 1000 0,0,1000,600
      printf '%s' "$S0" > "$R/claude.out"; printf '%s' "$S0" > "$R/claude.out.2"; vrrun "$R" >"$WORK/vr.out" 2>&1; local rc=$?
      [ $rc = 0 ] && [ "$(calls)" = 2 ] && json report.json "assert 'rechecked' in d[0] and '51%' in d[0]['rechecked'], d" && grep -q '^WARNING home__0.png: 51%' "$WORK/vr.out"; }
    t_recheck_threshold() { reset; mkdir -p "$R/baseline"; png "$R" baseline/home__0.png 1000 1000 100,100,300,300; png "$R" shots/home__0.png 1000 1000 0,0,1000,600
      printf '%s' "$S0" > "$R/claude.out"; VR_RECHECK_DIFF_PCT=60 vrrun "$R" >"$WORK/vr.out" 2>&1; [ "$(calls)" = 1 ]; }
    t_blank_not_rechecked() { [ "$(blank_case "$F1")" = 1 ] && [ "$(calls)" = 1 ]; }
    t_missing_rechecked()   { [ "$(second '[]' "$S4")" = 1 ] && [ "$(calls)" = 2 ] && json report.json "assert d[0]['file']=='home__0.png' and d[0]['severity']==4, d"; }
    t_cap() { multi 3 3 '[{"file":"f1.png","severity":0},{"file":"f2.png","severity":0},{"file":"f3.png","severity":0}]' >/dev/null; rm -f "$R/claude.log.calls"
      VR_RECHECK_MAX=1 multi 3 3 '[{"file":"f1.png","severity":0},{"file":"f2.png","severity":0},{"file":"f3.png","severity":0}]' >/dev/null
      [ "$(calls)" = 2 ] && json warnings.json "assert sum('Not re-checked' in w['warning'] for w in d)==2, d"; }
    t_rechecked_all_when_under_cap() { multi 3 3 '[{"file":"f1.png","severity":0},{"file":"f2.png","severity":0},{"file":"f3.png","severity":0}]' >/dev/null; [ "$(calls)" = 4 ]; }
    check "a described, passed page with a small diff is not re-checked"        t_no_recheck
    check "no description: re-checked, and a higher second severity fails the run" t_recheck_raises
    check "the re-check prompt is for one file and asks for an independent look"  t_recheck_prompt
    t_unreadable_first() { [ "$(second '[{"file":"home__0.png","verdict":"pass","severity":"high","seen":"s","findings":[]}]' "$S4")" = 1 ] && [ "$(calls)" = 2 ] && json report.json "r=d[0]; assert r['severity']==4 and r['first_severity'] is None and r['severity_raw']=='high', r"; }
    t_unreadable_unusable() { [ "$(second '[{"file":"home__0.png","verdict":"pass","severity":"high","seen":"s","findings":[]}]' "no json")" = 0 ] && [ "$(calls)" = 2 ] && json warnings.json "assert any('nothing usable' in w['warning'] and 'unreadable severity' in w['warning'] for w in d), d"; }
    check "an unreadable severity (\"high\") is re-judged, not taken as 0"        t_unreadable_first
    check "an unreadable severity with no usable re-check is warned about"        t_unreadable_unusable
    check "a second opinion never lowers a severity"                              t_never_lowers
    check "an unusable re-check keeps the first verdict and warns"                t_bad_recheck
    check "an unusable re-check does not hide a first-pass failure"               t_bad_recheck_keeps_fail
    check "judge said 0 with 51% of pixels changed: re-checked, and still warned" t_big_diff_recheck
    check "VR_RECHECK_DIFF_PCT sets that threshold (60: no re-check at 51%)"      t_recheck_threshold
    check "a page forced to severity 5 as blank is not re-checked"                t_blank_not_rechecked
    check "a file the judge left out is re-checked"                               t_missing_rechecked
    check "undescribed verdicts for 3 files: 3 re-checks (1 batch call + 3)"      t_rechecked_all_when_under_cap
    check "VR_RECHECK_MAX caps the re-checks and warns about the rest"            t_cap

    echo "-- vr.sh: the HTML report"
    t_report_on_fail()  { [ "$(run_with "$(sev 4)")" = 1 ] && [ -f "$R/report/index.html" ] && grep -q 'home__0.png' "$R/report/index.html" && grep -q 'FAIL' "$R/report/index.html" && grep -q 'http://stub' "$R/report/index.html" && [ -f "$R/report/img/diff/home__0.png" ]; }
    t_report_on_pass()  { [ "$(run_with "$(sev 0)")" = 0 ] && grep -q 'PASS' "$R/report/index.html"; }
    t_report_unchanged() { nothing_changed >/dev/null; grep -q 'Nothing changed' "$R/report/index.html"; }
    t_report_prints_path() { run_with "$(sev 4)" >/dev/null; grep -q '^report: report/index.html' "$WORK/vr.out"; }
    t_no_report_on_record() { reset; png "$R" shots/home__0.png 1000 1000; (cd "$R" && SHOTS="$R/shots" ./vr.sh --record http://stub >/dev/null 2>&1); [ ! -e "$R/report" ] && [ ! -e "$R/diff" ]; }
    t_stale_report_removed() { prep; mkdir -p "$R/report"; echo old > "$R/report/stale.txt"; printf 'no json' > "$R/claude.out"; vrrun "$R" >/dev/null 2>&1; [ ! -e "$R/report/stale.txt" ]; }
    t_report_failure_is_not_fatal() { prep; printf '%s' "$(sev 4)" > "$R/claude.out"; printf 'import sys\nsys.exit(1)\n' > "$R/html_report.py"; vrrun "$R" >"$WORK/vr.out" 2>&1; local rc=$?; cp "$VRSRC/html_report.py" "$R/html_report.py"; [ $rc = 1 ] && grep -q 'could not write the HTML report' "$WORK/vr.out"; }
    check "a failing run writes report/index.html (verdict, URL, diff image)"      t_report_on_fail
    check "a passing run writes one too"                                           t_report_on_pass
    check "a run with nothing changed writes one that says so"                     t_report_unchanged
    check "vr.sh prints where the report is"                                       t_report_prints_path
    check "--record writes no report and no diff folder"                           t_no_report_on_record
    check "a stale report/ is removed when a run dies before it can write one"     t_stale_report_removed
    check "a report that cannot be written does not change the exit code"          t_report_failure_is_not_fatal

    stale_files_removed() { prep; echo stale > "$R/report.json"; echo stale > "$R/raw_report.txt"; printf 'no json' > "$R/claude.out"; vrrun "$R" >/dev/null 2>&1; [ ! -f "$R/report.json" ] && grep -q "no json" "$R/raw_report.txt" && ! grep -q stale "$R/raw_report.txt"; }
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

# ============================================================ JUDGE TIER
if [ "$TIER" = judge ]; then
  for t in node npm claude; do have "$t" || { echo "judge tier needs '$t' on the host"; exit 2; }; done
  echo; echo "== judge: the real vr pipeline (claude -p) over labelled before/after pages =="
  echo "   (set VR_MODEL to pin a model; CHROMIUM_PATH if Playwright has no browser: npx playwright install chromium)"
  if "$VRT/judge/run.sh" "$WORK/judge"; then pass "judge catches broken pages without flagging fine ones"; else fail "judge calibration (see scores above)"; fi
  echo; echo "tier: judge   passed: $PASSES   failed: $FAILS"; [ "$FAILS" -eq 0 ] && exit 0 || exit 1
fi

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
