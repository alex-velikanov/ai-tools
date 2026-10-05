#!/usr/bin/env bash
# Tests for the harness and the skills installer.
#
#   ./test.sh                  fast tier: seconds, starts no containers. Golden snapshots of generated
#                              files, compose validity, error paths, idempotency, skills installer, fetching the
#                              pinned vr release (against a local fixture, no network), doc links.
#   ./test.sh full             fast tier + real containers: the demo app end to end, and two projects with
#                              different PHP / Node / database versions running side by side.
#   ./test.sh --update-golden  regenerate tests/golden/ (review the git diff before committing it)
#   Flags: --with-llm  also run the eval harness via `claude -p` (full tier, uses plan tokens)
#          --keep      keep the temp directory
#
# The visual tool (vr) is its own repository, alex-velikanov/visual-regressions, with its own tests (fast, browser, judge).
# Run the fast tier after ANY change to bootstrap.sh, core/, modules/ or skills/. Run full before relying on changes.
set -uo pipefail
unset VR_DATA      # a caller's VR_DATA may be a real project's data folder, and the fixtures' --record would replace its baseline
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
for f in "$HARNESS/bootstrap.sh" "$HARNESS/test.sh" "$REPO/skills/install.sh" "$HARNESS/core/files/evals/run.sh" "$HARNESS/core/files/evals/harvest.sh"; do
  check "bash -n ${f#$REPO/}" bash -n "$f"
done

# A local git repository that looks like visual-regressions: the tool at the root, plus the things that must not be installed.
read -r VRTAG _ < "$HARNESS/VR_VERSION"; VRTAG2="v9.9.9-fixture"
VRFIX="$WORK/vr-fixture"; mkdir -p "$VRFIX/tests" "$VRFIX/.github/workflows"
printf '#!/usr/bin/env bash\necho vr\n' > "$VRFIX/vr.sh"; chmod +x "$VRFIX/vr.sh"
echo one > "$VRFIX/marker"; echo '{"pages":["/"]}' > "$VRFIX/pages.json"; echo "# rubric" > "$VRFIX/rubric.md"
echo '{"name":"fixture"}' > "$VRFIX/package.json"; echo "# fixture" > "$VRFIX/README.md"; echo "export const a = 1;" > "$VRFIX/auth.mjs"
echo "test" > "$VRFIX/tests/x.test.mjs"; echo "test" > "$VRFIX/test.sh"; echo "ci" > "$VRFIX/.github/workflows/test.yml"
echo "claude" > "$VRFIX/CLAUDE.md"; echo "node_modules/" > "$VRFIX/.gitignore"
mkdir -p "$VRFIX/retired tools"
echo retired > "$VRFIX/retired tools/old helper.mjs"
git -C "$VRFIX" init -q -b main && gitc "$VRFIX" add -A && gitc "$VRFIX" commit -q -m one && gitc "$VRFIX" tag "$VRTAG"
echo two > "$VRFIX/marker"; echo "export const a = 2;" > "$VRFIX/auth.mjs"; echo "export const b = 1;" > "$VRFIX/added-later.mjs"
rm "$VRFIX/retired tools/old helper.mjs"
gitc "$VRFIX" add -A && gitc "$VRFIX" commit -q -m two && gitc "$VRFIX" tag "$VRTAG2"
VRCOMMIT="$(git -C "$VRFIX" rev-parse "$VRTAG^{commit}")"; VRCOMMIT2="$(git -C "$VRFIX" rev-parse "$VRTAG2^{commit}")"
export VR_REPO_URL="$VRFIX"      # every bootstrap in these tests fetches vr from the fixture
export VR_VERSION="$VRTAG" VR_COMMIT="$VRCOMMIT"      # the default pin of these tests is the fixture's first release

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
  rm -rf "$norm"; mkdir -p "$norm"; normalize "$dir" "$norm" "$dir"; rm -rf "$norm/vr"   # vr/ is fetched from its own repo: tested below, not snapshotted
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
echo; echo "== fast: vr comes from its own repository (a local fixture, no network) =="
vrproj() { rm -rf "$WORK/vrp/$1"; mkdir -p "$WORK/vrp/$1"; echo "$WORK/vrp/$1"; }
boot_vr() { local dir="$1"; shift; "$HARNESS/bootstrap.sh" "$dir" "$@" >"$WORK/vrboot.log" 2>&1; }
P="$(vrproj web)"; boot_vr "$P" --web
vr_fetched() { [ -x "$P/vr/vr.sh" ] && [ "$(cat "$P/vr/.vr-version")" = "$VRTAG $VRCOMMIT" ] && [ "$(cat "$P/vr/marker")" = one ] \
  && { for f in pages.json rubric.md package.json README.md auth.mjs; do [ -f "$P/vr/$f" ] || return 1; done; }; }
check "--web puts the pinned vr release in vr/ (executable vr.sh, .vr-version is the tag)" vr_fetched
vr_only_the_tool() { for f in tests test.sh .github CLAUDE.md .gitignore .git; do [ ! -e "$P/vr/$f" ] || { echo "vr/$f should not be installed"; return 1; }; done; }
check "the release's tests, CI files and git data are not installed" vr_only_the_tool
check "re-run changes nothing" bash -c "'$HARNESS/bootstrap.sh' '$P' --web | grep -q 'Summary: 0 created, 0 merged'"
echo '{"pages":["/mine"]}' > "$P/vr/pages.json"; echo "# my rubric" > "$P/vr/rubric.md"; echo "local edit" >> "$P/vr/auth.mjs"
echo "local edit" >> "$P/vr/retired tools/old helper.mjs"
echo custom > "$P/vr/retired tools/custom.mjs"
mkdir -p "$P/vr/tests"; echo custom > "$P/vr/tests/x.test.mjs"
VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT2" boot_vr "$P" --web
vr_pin_moved_without_flag() { grep -q "run again with --update-vr" "$WORK/vrboot.log" && [ "$(cat "$P/vr/.vr-version")" = "$VRTAG $VRCOMMIT" ] && [ "$(cat "$P/vr/marker")" = one ] && grep -q "local edit" "$P/vr/auth.mjs" && [ ! -e "$P/vr/added-later.mjs" ]; }
check "a newer pin alone leaves vr/ whole (nothing replaced, no new files from the newer release) and shows the way to update" vr_pin_moved_without_flag
check "a newer pin alone keeps retired release files" test -f "$P/vr/retired tools/old helper.mjs"
cp -R "$P/vr" "$WORK/vr-before-update"
VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT2" boot_vr "$P" --web --update-vr --dry-run
check "update dry-run reports retired files and leaves vr unchanged" bash -c "diff -r '$WORK/vr-before-update' '$P/vr' && grep -q 'removed.*vr/retired tools/old helper.mjs' '$WORK/vrboot.log'"
VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT2" boot_vr "$P" --web --update-vr
vr_updated() { [ "$(cat "$P/vr/.vr-version")" = "$VRTAG2 $VRCOMMIT2" ] && [ "$(cat "$P/vr/marker")" = two ] && [ -f "$P/vr/added-later.mjs" ] && ! grep -q "local edit" "$P/vr/auth.mjs"; }
check "--update-vr moves vr/ to the new release (changed and new files, a local edit to the tool is replaced)" vr_updated
check "--update-vr removes retired release files even with local edits" test ! -e "$P/vr/retired tools/old helper.mjs"
check "--update-vr preserves extra project files and excluded release paths" bash -c "[ \"\$(cat '$P/vr/retired tools/custom.mjs')\" = custom ] && [ \"\$(cat '$P/vr/tests/x.test.mjs')\" = custom ]"
vr_project_files_kept() { [ "$(cat "$P/vr/pages.json")" = '{"pages":["/mine"]}' ] && [ "$(cat "$P/vr/rubric.md")" = "# my rubric" ]; }
check "--update-vr keeps the project's own pages.json and rubric.md" vr_project_files_kept
echo "local edit" >> "$P/vr/auth.mjs"; echo "# local notes" > "$P/AGENTS.md"
VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT2" boot_vr "$P" --web --update-vr --force
check "--update-vr with --force keeps pages.json and rubric.md" vr_project_files_kept
check "--update-vr with --force replaces tool files" vr_updated
check "--force still replaces other harness files after vr" bash -c "! grep -q 'local notes' '$P/AGENTS.md'"
VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT2" boot_vr "$P" --web --force
check "--force without --update-vr still replaces project files (at the installed release)" bash -c "cmp -s '$VRFIX/pages.json' '$P/vr/pages.json' && cmp -s '$VRFIX/rubric.md' '$P/vr/rubric.md'"
VR_VERSION="$VRTAG" VR_COMMIT="$VRCOMMIT" boot_vr "$P" --web --update-vr
check "downgrading removes later release files and restores earlier files" bash -c "[ ! -e '$P/vr/added-later.mjs' ] && [ -f '$P/vr/retired tools/old helper.mjs' ] && [ \"\$(cat '$P/vr/.vr-version')\" = '$VRTAG $VRCOMMIT' ]"

Q="$(vrproj missing-previous)"; boot_vr "$Q" --web
echo no-such-tag > "$Q/vr/.vr-version"
cp -R "$Q" "$WORK/before-missing-previous"
VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT2" boot_vr "$Q" --web --update-vr; RC=$?
check "an unavailable previous release fails before writing project files" bash -c "[ '$RC' -eq 1 ] && grep -q 'could not fetch previous vr' '$WORK/vrboot.log' && diff -r '$WORK/before-missing-previous' '$Q'"

# Project configuration remains owned by the project even when removed upstream.
gitc "$VRFIX" rm -q pages.json rubric.md
gitc "$VRFIX" commit -q -m 'remove defaults' && gitc "$VRFIX" tag v9.9.10-fixture
VRCOMMIT3="$(git -C "$VRFIX" rev-parse HEAD)"
VR_VERSION=v9.9.10-fixture VR_COMMIT="$VRCOMMIT3" boot_vr "$P" --web --update-vr --force
check "project configuration survives removal from the release" bash -c "[ -f '$P/vr/pages.json' ] && [ -f '$P/vr/rubric.md' ]"

vr_unversioned_kept() {
  local flag="$1" dir
  dir="$(vrproj "unversioned-$flag")"
  boot_vr "$dir" --web || return 1
  rm "$dir/vr/.vr-version" "$dir/vr/README.md"
  echo "local edit" >> "$dir/vr/vr.sh"
  cp -R "$dir/vr" "$dir/before"
  local args=(); [ "$flag" = plain ] || args+=("--$flag")
  VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT2" boot_vr "$dir" --web "${args[@]}" || return 1
  diff -r "$dir/before" "$dir/vr" && grep -q 'run again with --update-vr' "$WORK/vrboot.log"
}
for flag in plain force dry-run; do
  check "unversioned differing vr stays unchanged ($flag), including missing files and version marker" vr_unversioned_kept "$flag"
done
P="$(vrproj migrate)"; boot_vr "$P" --web
rm "$P/vr/.vr-version"
echo '{"pages":["/mine"]}' > "$P/vr/pages.json"; echo "# my rubric" > "$P/vr/rubric.md"
echo "local edit" >> "$P/vr/auth.mjs"
VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT2" boot_vr "$P" --web --update-vr --force
check "--update-vr migrates an unversioned installation" vr_updated
check "unversioned migration with --force preserves project files" vr_project_files_kept
rm "$P/vr/.vr-version" "$P/vr/README.md"
VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT2" boot_vr "$P" --web
check "matching unversioned tools can gain missing release files and a version marker" bash -c "[ -f '$P/vr/README.md' ] && [ \"\$(cat '$P/vr/.vr-version')\" = '$VRTAG2 $VRCOMMIT2' ]"
check "custom project files alone do not block adopting a version" vr_project_files_kept
echo; echo "-- the pin is a tag and a commit: a moved tag is refused"
Q="$(vrproj moved-tag-pin)"; VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT" boot_vr "$Q" --web; RC=$?
vr_moved_tag_refused() { [ "$RC" -eq 1 ] && grep -q "is at commit $VRCOMMIT2" "$WORK/vrboot.log" && grep -q "pins $VRCOMMIT" "$WORK/vrboot.log" && grep -q "Refusing to install" "$WORK/vrboot.log" && [ -z "$(ls -A "$Q")" ]; }
check "a tag that points at another commit than the pin is refused, and nothing is written" vr_moved_tag_refused
Q="$(vrproj no-commit)"; ( unset VR_COMMIT; VR_VERSION="$VRTAG2" boot_vr "$Q" --web ); RC=$?
check "VR_VERSION without VR_COMMIT is refused with the way to look the commit up" bash -c "[ '$RC' -eq 2 ] && grep -q 'VR_COMMIT' '$WORK/vrboot.log' && grep -q 'git ls-remote' '$WORK/vrboot.log' && [ -z \"\$(ls -A '$Q')\" ]"
Q="$(vrproj short-commit)"; VR_VERSION="$VRTAG2" VR_COMMIT="${VRCOMMIT2:0:7}" boot_vr "$Q" --web; RC=$?
check "a commit that is not the full 40 hex characters is refused" bash -c "[ '$RC' -eq 2 ] && grep -q '40-character' '$WORK/vrboot.log' && [ -z \"\$(ls -A '$Q')\" ]"

Q="$(vrproj commit-only)"; ( unset VR_VERSION; boot_vr "$Q" --web ); RC=$?
check "VR_COMMIT alone overrides the default commit while using the default tag" bash -c "[ '$RC' -eq 0 ] && [ \"\$(cat '$Q/vr/.vr-version')\" = '$VRTAG $VRCOMMIT' ]"

# one tag, moved after it was installed: the same tag at another commit is another release
gitc "$VRFIX" tag v9.9.7-moved "$VRCOMMIT"
M="$(vrproj moved-after-install)"; VR_VERSION=v9.9.7-moved VR_COMMIT="$VRCOMMIT" boot_vr "$M" --web
gitc "$VRFIX" tag -f v9.9.7-moved "$VRCOMMIT2" >/dev/null
VR_VERSION=v9.9.7-moved VR_COMMIT="$VRCOMMIT2" boot_vr "$M" --web
vr_same_tag_other_commit_left_whole() { grep -q "run again with --update-vr" "$WORK/vrboot.log" && [ "$(cat "$M/vr/.vr-version")" = "v9.9.7-moved $VRCOMMIT" ] && [ "$(cat "$M/vr/marker")" = one ] && [ ! -e "$M/vr/added-later.mjs" ]; }
check "the same tag at another commit is another release: vr/ is left whole without --update-vr" vr_same_tag_other_commit_left_whole
VR_VERSION=v9.9.7-moved VR_COMMIT="$VRCOMMIT2" boot_vr "$M" --web --update-vr
check "--update-vr moves vr/ to the same tag at its new commit" bash -c "[ \"\$(cat '$M/vr/.vr-version')\" = 'v9.9.7-moved $VRCOMMIT2' ] && [ \"\$(cat '$M/vr/marker')\" = two ]"

check "same-tag --update-vr removes retired release files" test ! -e "$M/vr/retired tools/old helper.mjs"

# A recorded commit that cannot be fetched must not allow a partial same-tag update.
Q="$(vrproj same-tag-missing-commit)"; boot_vr "$Q" --web
printf '%s %s\n' "$VRTAG" 0000000000000000000000000000000000000000 > "$Q/vr/.vr-version"
cp -R "$Q" "$WORK/before-same-tag-missing-commit"
boot_vr "$Q" --web --update-vr --force; RC=$?
check "same-tag update with an unavailable recorded commit fails before writing project files" bash -c "[ '$RC' -eq 1 ] && grep -q 'could not resolve previous vr' '$WORK/vrboot.log' && diff -r '$WORK/before-same-tag-missing-commit' '$Q'"

# the previous release is trusted only while its tag still points at the commit recorded at install time
gitc "$VRFIX" tag v9.9.6-prev "$VRCOMMIT"
N="$(vrproj previous-moved)"; VR_VERSION=v9.9.6-prev VR_COMMIT="$VRCOMMIT" boot_vr "$N" --web
gitc "$VRFIX" tag -f v9.9.6-prev "$VRCOMMIT2" >/dev/null
cp -R "$N" "$WORK/before-previous-moved"
VR_VERSION=v9.9.10-fixture VR_COMMIT="$VRCOMMIT3" boot_vr "$N" --web --update-vr; RC=$?
vr_previous_moved_refused() { [ "$RC" -eq 1 ] && grep -q "was installed at commit $VRCOMMIT" "$WORK/vrboot.log" && diff -r "$WORK/before-previous-moved" "$N"; }
check "--update-vr refuses to trust a previous release whose tag moved, before writing anything" vr_previous_moved_refused

# a marker written before pins carried a commit still works, and gains the commit
L="$(vrproj legacy-marker)"; boot_vr "$L" --web
echo "$VRTAG" > "$L/vr/.vr-version"
boot_vr "$L" --web
check "a tag-only marker for the pinned tag gains the commit, quietly" bash -c "[ \"\$(cat '$L/vr/.vr-version')\" = '$VRTAG $VRCOMMIT' ] && ! grep -q 'SKIP' '$WORK/vrboot.log'"
echo "$VRTAG" > "$L/vr/.vr-version"
VR_VERSION="$VRTAG2" VR_COMMIT="$VRCOMMIT2" boot_vr "$L" --web --update-vr
check "--update-vr works from a tag-only marker (the previous release is taken by tag)" bash -c "[ \"\$(cat '$L/vr/.vr-version')\" = '$VRTAG2 $VRCOMMIT2' ] && [ ! -e '$L/vr/retired tools/old helper.mjs' ]"

Q="$(vrproj bad)"; VR_VERSION=no-such-tag VR_COMMIT="$VRCOMMIT" boot_vr "$Q" --web; RC=$?
vr_bad_tag() { [ "$RC" -eq 1 ] && ! grep -qE "^(tar|fatal: cannot change)" "$WORK/vrboot.log" && grep -q "could not fetch vr no-such-tag" "$WORK/vrboot.log" && grep -q "VR_REPO_URL" "$WORK/vrboot.log" && [ -z "$(ls -A "$Q")" ]; }
check "a missing tag stops the run with a clear message and writes nothing" vr_bad_tag
Q="$(vrproj gone)"; VR_REPO_URL="$WORK/no-such-repo" boot_vr "$Q" --web; RC=$?
vr_bad_repo() { [ "$RC" -eq 1 ] && grep -q "could not fetch vr" "$WORK/vrboot.log" && [ -z "$(ls -A "$Q")" ]; }
check "an unreachable repository stops the run the same way" vr_bad_repo
Q="$(vrproj nowebfetch)"; VR_REPO_URL="$WORK/no-such-repo" boot_vr "$Q" --go; RC=$?
check "without --web nothing is fetched (a bad VR_REPO_URL does not matter)" bash -c "[ '$RC' -eq 0 ] && [ ! -e '$Q/vr' ]"
Q="$(vrproj dry)"; boot_vr "$Q" --web --dry-run
check "--dry-run installs no vr" bash -c "[ -z \"\$(ls -A '$Q' 2>/dev/null)\" ]"


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
