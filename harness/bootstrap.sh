#!/usr/bin/env bash
# harness-init — apply the dev harness (hooks, scanning, evals, MCP config, Docker runtime, ...)
# to a project directory. Safe to re-run: never overwrites existing files unless --force,
# never touches app code, never commits.
set -euo pipefail

# Resolve symlinks so this works when invoked via /usr/local/bin/harness-init.
HARNESS_DIR="$(cd "$(dirname "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")")" && pwd)"

usage() {
  cat <<'EOF'
Usage: harness-init <target-dir> [--php[=dir]] [--go[=dir]] [--web[=dir]] [options]

Stacks (each takes an optional subdirectory, default "." = project root):
  --php[=dir]   PHP in Docker: Dockerfile (Xdebug + Xdebug MCP baked in), PHPStan/PHPUnit config
  --go[=dir]    Go on the host (go.mod pins the toolchain): golangci config, gomod Dependabot entry
  --web[=dir]   Node in Docker (dev server), plus host-side e2e/ (Playwright) and vr/ (visual tool)

Runtime options (PHP, Node and the database run in Docker Compose; there is no host mode):
  --php-version V     PHP version for the container            (default 8.3)
  --node-version V    Node version for the container           (default 22)
  --db KIND[:TAG]     postgres | mysql, e.g. postgres:17       (default none; tags: postgres 16, mysql 8.4)

Other options:
  --install     also run installs (build + start containers, phpstan, Playwright, vr deps)
  --update-vr   move an existing vr/ to the version pinned in VR_VERSION (replaces the tool's files; keeps your pages.json and rubric.md)
  --force       replace existing files that differ (default: skip and show diff)
  --dry-run     show what would happen, write nothing
  -h, --help    this help

Always applied: lefthook (gitleaks + semgrep), .semgrepignore, evals/ harness, eval.yml,
Dependabot, AGENTS.md (+ CLAUDE.md symlink), .review-log.md, .cursor/mcp.json.
EOF
}

die() { echo "error: $*" >&2; exit 2; }

TARGET=""; FORCE=0; INSTALL=0; DRY=0; UPDATE_VR=0
PHP=0; GO=0; WEB=0; PHP_DIR="."; GO_DIR="."; WEB_DIR="."
PHP_VERSION="8.3"; NODE_VERSION="22"; DB_SPEC="none"
while [ $# -gt 0 ]; do
  case "$1" in
    --php) PHP=1 ;;  --php=*) PHP=1; PHP_DIR="${1#*=}" ;;
    --go)  GO=1 ;;   --go=*)  GO=1;  GO_DIR="${1#*=}" ;;
    --web) WEB=1 ;;  --web=*) WEB=1; WEB_DIR="${1#*=}" ;;
    --php-version)  [ $# -ge 2 ] || die "--php-version needs a value";  PHP_VERSION="$2"; shift ;;
    --php-version=*) PHP_VERSION="${1#*=}" ;;
    --node-version) [ $# -ge 2 ] || die "--node-version needs a value"; NODE_VERSION="$2"; shift ;;
    --node-version=*) NODE_VERSION="${1#*=}" ;;
    --db)           [ $# -ge 2 ] || die "--db needs a value";           DB_SPEC="$2"; shift ;;
    --db=*) DB_SPEC="${1#*=}" ;;
    --force) FORCE=1 ;; --install) INSTALL=1 ;; --dry-run) DRY=1 ;; --update-vr) UPDATE_VR=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "$TARGET" ] || die "only one target dir allowed"; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { usage >&2; exit 2; }

# ---- validate runtime options
[[ "$PHP_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]            || die "--php-version must look like 8.3 (got '$PHP_VERSION')"
[[ "$NODE_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]        || die "--node-version must look like 22 or 22.11 (got '$NODE_VERSION')"
DB_KIND="${DB_SPEC%%:*}"; DB_TAG=""; [[ "$DB_SPEC" == *:* ]] && DB_TAG="${DB_SPEC#*:}"
case "$DB_KIND" in
  none) ;;
  postgres) DB_TAG="${DB_TAG:-16}"; DB_PORT=5432; PHP_DB_EXT="pdo_pgsql" ;;
  mysql)    DB_TAG="${DB_TAG:-8.4}"; DB_PORT=3306; PHP_DB_EXT="pdo_mysql" ;;
  *) die "--db must be postgres, mysql or none (got '$DB_KIND')" ;;
esac
[ "$DB_KIND" = none ] && { DB_PORT=""; PHP_DB_EXT=""; }
[ -z "$DB_TAG" ] || [[ "$DB_TAG" =~ ^[A-Za-z0-9._-]+$ ]] || die "--db tag has odd characters: '$DB_TAG'"
if [ "$DB_KIND" != none ] && [ "$PHP" = 0 ] && [ "$WEB" = 0 ]; then die "--db needs --php or --web (something has to use the database)"; fi
PG_DATA_PATH="/var/lib/postgresql/data"
if [ "$DB_KIND" = postgres ] && [[ "$DB_TAG" =~ ^[0-9]+ ]] && [ "${BASH_REMATCH[0]}" -ge 18 ]; then PG_DATA_PATH="/var/lib/postgresql"; fi
DB_NOTE=""
[ "$WEB" = 1 ] && DB_NOTE="$DB_NOTE, Node"
[ "$DB_KIND" != none ] && DB_NOTE="$DB_NOTE, $DB_KIND"

[ "$DRY" = 1 ] || mkdir -p "$TARGET"
[ -d "$TARGET" ] || { echo "target does not exist (dry run): $TARGET"; TARGET="$(cd "$(dirname "$TARGET")" && pwd)/$(basename "$TARGET")"; }
[ -d "$TARGET" ] && TARGET="$(cd "$TARGET" && pwd)"
PROJECT_NAME="$(basename "$TARGET")"
PROJECT_SLUG="$(printf '%s' "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9_-]/-/g' -e 's/^[-_]*//')"; [ -n "$PROJECT_SLUG" ] || PROJECT_SLUG="app"
DOCKER_BIN="$(command -v docker 2>/dev/null || echo docker)"

slash()  { if [ "$1" = "." ]; then echo "/"; else echo "/${1#./}"; fi; }
prefix() { if [ "$1" = "." ]; then echo ""; else echo "${1#./}/"; fi; }

render() {
  sed -e "s|{{PROJECT_ROOT}}|$TARGET|g" -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" -e "s|{{PROJECT_SLUG}}|$PROJECT_SLUG|g" \
      -e "s|{{PHP_DIR}}|$PHP_DIR|g" -e "s|{{GO_DIR}}|$GO_DIR|g" -e "s|{{WEB_DIR}}|$WEB_DIR|g" \
      -e "s|{{PHP_DIR_SLASH}}|$(slash "$PHP_DIR")|g" -e "s|{{GO_DIR_SLASH}}|$(slash "$GO_DIR")|g" \
      -e "s|{{WEB_DIR_SLASH}}|$(slash "$WEB_DIR")|g" \
      -e "s|{{PHP_DIR_PREFIX}}|$(prefix "$PHP_DIR")|g" -e "s|{{GO_DIR_PREFIX}}|$(prefix "$GO_DIR")|g" \
      -e "s|{{WEB_DIR_PREFIX}}|$(prefix "$WEB_DIR")|g" \
      -e "s|{{PHP_VERSION}}|$PHP_VERSION|g" -e "s|{{NODE_VERSION}}|$NODE_VERSION|g" \
      -e "s|{{DB_KIND}}|$DB_KIND|g" -e "s|{{DB_TAG}}|$DB_TAG|g" -e "s|{{DB_PORT}}|${DB_PORT:-}|g" \
      -e "s|{{PG_DATA_PATH}}|$PG_DATA_PATH|g" -e "s|{{PHP_DB_EXT}}|${PHP_DB_EXT:-}|g" \
      -e "s|{{DB_NOTE}}|$DB_NOTE|g" -e "s|{{DOCKER_BIN}}|$DOCKER_BIN|g" "$@"
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
N_NEW=0; N_SAME=0; N_SKIP=0; N_MERGED=0
log() { printf '  %-9s %s\n' "$1" "$2"; }

# put <content-file> <dest relative to project> [x]
put() {
  local src="$1" rel="$2" dest="$TARGET/$2"
  if [ -e "$dest" ]; then
    if cmp -s "$src" "$dest"; then N_SAME=$((N_SAME+1)); log same "$rel"; return; fi
    if [ "$FORCE" != 1 ]; then
      N_SKIP=$((N_SKIP+1)); log SKIP "$rel (exists, differs — --force to replace)"
      diff -u "$dest" "$src" | sed -n '1,14p' | sed 's/^/              /' || true
      return
    fi
    log replaced "$rel"
  else
    N_NEW=$((N_NEW+1)); log created "$rel"
  fi
  [ "$DRY" = 1 ] && return
  mkdir -p "$(dirname "$dest")"; cp "$src" "$dest"
  [ "${3:-}" = x ] && chmod +x "$dest"
  return 0
}

# apply_tree <source tree> <dest prefix relative to project ("" for root)>
apply_tree() {
  local tree="$1" pre="$2" f rel
  [ -d "$tree" ] || return 0
  while IFS= read -r f; do
    rel="${f#$tree/}"
    render "$f" > "$TMP/render"
    if [ -x "$f" ]; then put "$TMP/render" "$pre$rel" x; else put "$TMP/render" "$pre$rel"; fi
  done < <(find "$tree" -type f | sort)
}

# ---- the visual tool (vr/) is its own project (visual-regressions): fetch the release pinned in VR_VERSION into a temp dir before
# anything is written, so an unreachable repo or a missing tag stops the run with the project untouched.
# VR_REPO_URL (a URL or a local path) and VR_VERSION (a tag) override the defaults, for tests and for trying a newer release.
VR_REPO_URL="${VR_REPO_URL:-https://github.com/alex-velikanov/visual-regressions}"
VR_TAG="${VR_VERSION:-$(tr -d '[:space:]' < "$HARNESS_DIR/VR_VERSION")}"
VR_TREE=""
if [ "$WEB" = 1 ]; then
  VR_TREE="$TMP/vr-tool"
  if ! git clone -q --depth 1 --branch "$VR_TAG" "$VR_REPO_URL" "$TMP/vr-src" 2>"$TMP/vr-clone.log"; then
    echo "error: could not fetch vr $VR_TAG from $VR_REPO_URL (--web needs it). Nothing was written." >&2
    sed 's/^/  /' "$TMP/vr-clone.log" | tail -3 >&2
    echo "  Check the network and the tag, or set VR_REPO_URL to a local copy of the repository." >&2
    exit 1
  fi
  mkdir -p "$VR_TREE"
  git -C "$TMP/vr-src" archive HEAD -- . ':(exclude)tests' ':(exclude)test.sh' ':(exclude).github' ':(exclude).gitignore' ':(exclude)CLAUDE.md' | tar -x -C "$VR_TREE"
  printf '%s\n' "$VR_TAG" > "$VR_TREE/.vr-version"
fi

# apply_vr — vr/ gets the release's files. Like everything else a differing file is kept unless --force; --update-vr replaces the
# tool's own files and still keeps pages.json and rubric.md, which are the project's.
apply_vr() {
  local f rel keep="$FORCE" had=""
  [ -f "$TARGET/vr/.vr-version" ] && had="$(tr -d '[:space:]' < "$TARGET/vr/.vr-version")"
  # An installation at another release is left whole: adding the new release's missing files would mix two revisions.
  if [ -d "$TARGET/vr" ] && [ "$UPDATE_VR" != 1 ] && [ -n "$had" ] && [ "$had" != "$VR_TAG" ]; then
    log note "vr/ is at $had and this harness pins $VR_TAG: left unchanged, run again with --update-vr to move it"
    return 0
  fi
  # Check the whole unversioned installation before adding any release files or its version marker.
  if [ -d "$TARGET/vr" ] && [ ! -e "$TARGET/vr/.vr-version" ] && [ "$UPDATE_VR" != 1 ]; then
    while IFS= read -r f; do
      rel="${f#$VR_TREE/}"
      case "$rel" in .vr-version|pages.json|rubric.md) continue ;; esac
      if [ -e "$TARGET/vr/$rel" ] && ! cmp -s "$f" "$TARGET/vr/$rel"; then
        log note "vr/ has differing tool files and no .vr-version; left unchanged: run again with --update-vr to move it to $VR_TAG"
        return 0
      fi
    done < <(find "$VR_TREE" -type f | sort)
  fi
  while IFS= read -r f; do
    rel="${f#$VR_TREE/}"
    FORCE="$keep"
    if [ "$UPDATE_VR" = 1 ]; then
      case "$rel" in pages.json|rubric.md) FORCE=0 ;; *) FORCE=1 ;; esac
    fi
    if [ -x "$f" ]; then put "$f" "vr/$rel" x; else put "$f" "vr/$rel"; fi
  done < <(find "$VR_TREE" -type f | sort)
  FORCE="$keep"
}

# append_gitignore <fragment...> — adds only lines not already present
append_gitignore() {
  local dest="$TARGET/.gitignore" added=0 line
  for frag in "$@"; do
    [ -f "$frag" ] || continue
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if [ -f "$dest" ] && grep -qxF -- "$line" "$dest"; then continue; fi
      if [ "$DRY" != 1 ]; then printf '%s\n' "$line" >> "$dest"; fi
      added=$((added+1))
    done < <(render "$frag")
  done
  if [ "$added" -gt 0 ]; then N_MERGED=$((N_MERGED+1)); log merged ".gitignore (+$added lines)"; else N_SAME=$((N_SAME+1)); log same ".gitignore"; fi
}

echo "harness-init → $TARGET  [php=$PHP go=$GO web=$WEB db=$DB_KIND force=$FORCE install=$INSTALL dry=$DRY]"
[ "$PHP" = 1 ] && echo "  php $PHP_VERSION (docker)"; [ "$WEB" = 1 ] && echo "  node $NODE_VERSION (docker)"; [ "$DB_KIND" != none ] && echo "  $DB_KIND:$DB_TAG (docker)"
echo

# ---- 1. verbatim files
echo "Files:"
apply_tree "$HARNESS_DIR/core/files" ""
if [ "$PHP" = 1 ]; then
  apply_tree "$HARNESS_DIR/modules/php/files" "$(prefix "$PHP_DIR")"
  apply_tree "$HARNESS_DIR/modules/php/root" ""
fi
[ "$GO" = 1 ] && apply_tree "$HARNESS_DIR/modules/go/files" "$(prefix "$GO_DIR")"
if [ "$WEB" = 1 ]; then
  apply_tree "$HARNESS_DIR/modules/web/files" "$(prefix "$WEB_DIR")"
  apply_tree "$HARNESS_DIR/modules/web/root" ""
  apply_vr
fi

# ---- 2. assembled files
MODS=""; [ "$PHP" = 1 ] && MODS="$MODS php"; [ "$GO" = 1 ] && MODS="$MODS go"; [ "$WEB" = 1 ] && MODS="$MODS web"

{ cat "$HARNESS_DIR/core/fragments/dependabot.head.yml"
  for m in $MODS; do cat "$HARNESS_DIR/modules/$m/dependabot.fragment.yml"; done
  cat "$HARNESS_DIR/core/fragments/dependabot.actions.yml"; } | render > "$TMP/dependabot"
put "$TMP/dependabot" ".github/dependabot.yml"

{ cat "$HARNESS_DIR/core/fragments/AGENTS.head.md"
  for m in $MODS; do cat "$HARNESS_DIR/modules/$m/AGENTS.commands.md"; done
  if [ -z "$MODS" ]; then echo "TODO: test / lint / run commands"; fi
  if [ "$DB_KIND" = postgres ]; then echo 'DB shell:  docker compose exec db psql -U app app'; fi
  if [ "$DB_KIND" = mysql ]; then echo 'DB shell:  docker compose exec db mysql -uapp -pdev app'; fi
  cat "$HARNESS_DIR/core/fragments/AGENTS.tail.md"; } | render > "$TMP/agents"
put "$TMP/agents" "AGENTS.md"

if [ "$PHP" = 1 ] || [ "$WEB" = 1 ]; then
  {
    echo "name: $PROJECT_SLUG"; echo; echo "services:"
    if [ "$PHP" = 1 ]; then
      cat "$HARNESS_DIR/modules/php/compose.fragment.yml"
      if [ "$DB_KIND" != none ]; then cat "$HARNESS_DIR/modules/docker/app-db.fragment.yml"; fi
    fi
    if [ "$WEB" = 1 ]; then cat "$HARNESS_DIR/modules/web/compose.fragment.yml"; fi
    if [ "$DB_KIND" != none ]; then
      cat "$HARNESS_DIR/modules/docker/db.$DB_KIND.fragment.yml"
      printf '\nvolumes:\n  db_data:\n'
    fi
  } | render > "$TMP/compose"
  put "$TMP/compose" "compose.yaml"
fi

if [ ! -e "$TARGET/CLAUDE.md" ] && [ ! -L "$TARGET/CLAUDE.md" ]; then
  [ "$DRY" = 1 ] || ln -s AGENTS.md "$TARGET/CLAUDE.md"
  N_NEW=$((N_NEW+1)); log created "CLAUDE.md -> AGENTS.md"
else N_SAME=$((N_SAME+1)); log same "CLAUDE.md"; fi

# MCP config: merge servers into any existing .cursor/mcp.json, never replace one that exists.
frags=""; for m in $MODS; do if [ -f "$HARNESS_DIR/modules/$m/mcp.fragment.json" ]; then render "$HARNESS_DIR/modules/$m/mcp.fragment.json" > "$TMP/mcp.$m"; frags="$frags $TMP/mcp.$m"; fi; done
MCP_OUT="$(python3 - "$TARGET/.cursor/mcp.json" "$DRY" $frags <<'PY'
import json, os, sys
dest, dry, frags = sys.argv[1], sys.argv[2] == "1", sys.argv[3:]
cfg = json.load(open(dest)) if os.path.exists(dest) else {}
servers = cfg.setdefault("mcpServers", {})
added = []
for f in frags:
    for name, spec in json.load(open(f)).items():
        if name not in servers:
            servers[name] = spec; added.append(name)
if added and not dry:
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    json.dump(cfg, open(dest, "w"), indent=2); open(dest, "a").write("\n")
print("merged:" + ",".join(added) if added else "same")
PY
)"
case "$MCP_OUT" in
  merged:*) N_MERGED=$((N_MERGED+1)); log merged ".cursor/mcp.json (+${MCP_OUT#merged:})" ;;
  *) N_SAME=$((N_SAME+1)); log same ".cursor/mcp.json" ;;
esac

gi=("$HARNESS_DIR/core/fragments/gitignore.fragment")
for m in $MODS; do gi+=("$HARNESS_DIR/modules/$m/gitignore.fragment"); done
append_gitignore "${gi[@]}"

# ---- 3. git + hooks
echo; echo "Git:"
if [ "$DRY" = 1 ]; then log skipped "git init / lefthook install (dry run)"
else
  if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then git -C "$TARGET" init -q -b main; log created "git repository (branch main)"; else log same "git repository"; fi
  if command -v lefthook >/dev/null 2>&1; then (cd "$TARGET" && lefthook install >/dev/null 2>&1) && log ok "lefthook hooks installed"; else log WARN "lefthook not found — brew install lefthook"; fi
fi

# ---- 4. tool check
echo; echo "Tools:"
need() { if command -v "$1" >/dev/null 2>&1; then log ok "$1"; else log MISSING "$1 — $2"; fi; }
need git "xcode-select --install"; need semgrep "brew install semgrep"; need gitleaks "brew install gitleaks"
need lefthook "brew install lefthook"; need claude "npm i -g @anthropic-ai/claude-code (evals + vr.sh shell out to it)"
if [ "$PHP" = 1 ] || [ "$WEB" = 1 ] || [ "$DB_KIND" != none ]; then
  need docker "install OrbStack or Docker Desktop"
  if docker compose version >/dev/null 2>&1; then log ok "docker compose"; else log MISSING "docker compose plugin"; fi
fi
if [ "$WEB" = 1 ]; then need node "brew install node (host-side e2e/ and vr/ only; the app's Node runs in Docker)"; need npm "ships with node"; fi
if [ "$GO" = 1 ]; then need go "brew install go"; need golangci-lint "optional: brew install golangci-lint"; need dlv "optional: brew install delve"; fi

# ---- 5. installs (opt-in: they build images and add dependencies to your project)
DC="docker compose -f '$TARGET/compose.yaml'"
INSTALL_CMDS=()
if [ "$PHP" = 1 ] || [ "$WEB" = 1 ]; then INSTALL_CMDS+=("$DC up -d --build"); fi
if [ "$PHP" = 1 ] && [ -f "$TARGET/$PHP_DIR/composer.json" ]; then
  INSTALL_CMDS+=("$DC exec -T app composer require --dev phpstan/phpstan --no-interaction")
fi
if [ "$WEB" = 1 ]; then
  INSTALL_CMDS+=("cd '$TARGET/e2e' && { npm ls @playwright/test >/dev/null 2>&1 || npm i -D @playwright/test; } && npx playwright install chromium chromium-headless-shell")
  INSTALL_CMDS+=("cd '$TARGET/e2e' && [ -f .claude/agents/playwright-test-planner.md ] || { [ -f seed.spec.ts ] && cp seed.spec.ts \"$TMP/seed.bak\"; npx playwright init-agents --loop=claude; [ -f \"$TMP/seed.bak\" ] && cp \"$TMP/seed.bak\" seed.spec.ts; true; }")
  INSTALL_CMDS+=("cd '$TARGET/vr' && npm install")
fi
echo; echo "Installs:"
if [ "${#INSTALL_CMDS[@]}" -eq 0 ]; then log none "nothing to install"
elif [ "$INSTALL" = 1 ] && [ "$DRY" != 1 ]; then
  if { [ "$PHP" = 1 ] || [ "$WEB" = 1 ]; } && ! docker info >/dev/null 2>&1; then echo "error: Docker is not running — start OrbStack/Docker Desktop and re-run with --install" >&2; exit 1; fi
  for c in "${INSTALL_CMDS[@]}"; do log run "$c"; bash -c "$c" >"$TMP/install.log" 2>&1 || { log FAILED "see output below"; tail -15 "$TMP/install.log"; exit 1; }; done
else
  log pending "re-run with --install, or run by hand:"; for c in "${INSTALL_CMDS[@]}"; do echo "              $c"; done
fi

echo
echo "Summary: $N_NEW created, $N_MERGED merged, $N_SAME unchanged, $N_SKIP skipped"
cat <<EOF

Still manual (once per project):
  1. Fill in AGENTS.md "Structure" and "Rules" with real facts; verify the Commands section.
  2. Set vr/pages.json to your real URLs (web).
  3. Push to GitHub, then: branch protection on main; repo secret ANTHROPIC_API_KEY (for eval.yml).
  4. Sentry: create project, set rate limits BEFORE pointing prod at it, then add the SDK.
  5. After ~2 weeks of real work: ./evals/harvest.sh, curate ~12 cases (about half clean).
EOF
[ "$N_SKIP" -gt 0 ] && echo "  (!) $N_SKIP existing file(s) were left untouched — review the diffs above."
exit 0
