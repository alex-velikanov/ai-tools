#!/usr/bin/env bash
# harness-init — apply the dev harness (hooks, scanning, evals, MCP config, ...)
# to a project directory. Safe to re-run: never overwrites existing files
# unless --force, never touches app code, never commits.
set -euo pipefail

# Resolve symlinks so this works when invoked via /usr/local/bin/harness-init.
HARNESS_DIR="$(cd "$(dirname "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")")" && pwd)"

usage() {
  cat <<'EOF'
Usage: harness-init <target-dir> [--php[=dir]] [--go[=dir]] [--web[=dir]] [options]

Stacks (each takes an optional subdirectory, default "." = project root):
  --php[=dir]   PHPStan config, Xdebug MCP, composer Dependabot entry
  --go[=dir]    golangci config, gomod Dependabot entry
  --web[=dir]   Playwright config + MCP, visual-fidelity tool (vr/), npm Dependabot entry

Options:
  --install     also run installs (phpstan, xdebug-mcp, playwright + browsers + agents, vr deps)
  --force       replace existing files that differ (default: skip and show diff)
  --dry-run     show what would happen, write nothing
  -h, --help    this help

Always applied: lefthook (gitleaks + semgrep), .semgrepignore, evals/ harness,
eval.yml, Dependabot, AGENTS.md (+ CLAUDE.md symlink), .review-log.md, .cursor/mcp.json.
EOF
}

TARGET=""; FORCE=0; INSTALL=0; DRY=0
PHP=0; GO=0; WEB=0; PHP_DIR="."; GO_DIR="."; WEB_DIR="."
while [ $# -gt 0 ]; do
  case "$1" in
    --php) PHP=1 ;;  --php=*) PHP=1; PHP_DIR="${1#*=}" ;;
    --go)  GO=1 ;;   --go=*)  GO=1;  GO_DIR="${1#*=}" ;;
    --web) WEB=1 ;;  --web=*) WEB=1; WEB_DIR="${1#*=}" ;;
    --force) FORCE=1 ;; --install) INSTALL=1 ;; --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "$TARGET" ] || { echo "only one target dir allowed" >&2; exit 2; }; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { usage >&2; exit 2; }

[ "$DRY" = 1 ] || mkdir -p "$TARGET"
[ -d "$TARGET" ] || { echo "target does not exist (dry run): $TARGET"; TARGET="$(cd "$(dirname "$TARGET")" && pwd)/$(basename "$TARGET")"; }
[ -d "$TARGET" ] && TARGET="$(cd "$TARGET" && pwd)"
PROJECT_NAME="$(basename "$TARGET")"

COMPOSER_BIN="$HOME/.composer/vendor/bin"
if command -v composer >/dev/null 2>&1; then
  COMPOSER_BIN="$(composer global config bin-dir --absolute 2>/dev/null | tail -1 || echo "$COMPOSER_BIN")"
fi

slash()  { if [ "$1" = "." ]; then echo "/"; else echo "/${1#./}"; fi; }
prefix() { if [ "$1" = "." ]; then echo ""; else echo "${1#./}/"; fi; }

render() {
  sed -e "s|{{PROJECT_ROOT}}|$TARGET|g" -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
      -e "s|{{PHP_DIR}}|$PHP_DIR|g" -e "s|{{GO_DIR}}|$GO_DIR|g" -e "s|{{WEB_DIR}}|$WEB_DIR|g" \
      -e "s|{{PHP_DIR_SLASH}}|$(slash "$PHP_DIR")|g" -e "s|{{GO_DIR_SLASH}}|$(slash "$GO_DIR")|g" \
      -e "s|{{WEB_DIR_SLASH}}|$(slash "$WEB_DIR")|g" \
      -e "s|{{PHP_DIR_PREFIX}}|$(prefix "$PHP_DIR")|g" -e "s|{{GO_DIR_PREFIX}}|$(prefix "$GO_DIR")|g" \
      -e "s|{{WEB_DIR_PREFIX}}|$(prefix "$WEB_DIR")|g" -e "s|{{COMPOSER_BIN}}|$COMPOSER_BIN|g" "$@"
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

echo "harness-init → $TARGET  [php=$PHP go=$GO web=$WEB force=$FORCE install=$INSTALL dry=$DRY]"
echo

# ---- 1. verbatim files
echo "Files:"
apply_tree "$HARNESS_DIR/core/files" ""
[ "$PHP" = 1 ] && apply_tree "$HARNESS_DIR/modules/php/files" "$(prefix "$PHP_DIR")"
[ "$GO"  = 1 ] && apply_tree "$HARNESS_DIR/modules/go/files"  "$(prefix "$GO_DIR")"
if [ "$WEB" = 1 ]; then
  apply_tree "$HARNESS_DIR/modules/web/files" "$(prefix "$WEB_DIR")"
  apply_tree "$HARNESS_DIR/modules/web/root" ""
fi

# ---- 2. assembled files
MODS=""; [ "$PHP" = 1 ] && MODS="$MODS php"; [ "$GO" = 1 ] && MODS="$MODS go"; [ "$WEB" = 1 ] && MODS="$MODS web"

{ cat "$HARNESS_DIR/core/fragments/dependabot.head.yml"
  for m in $MODS; do cat "$HARNESS_DIR/modules/$m/dependabot.fragment.yml"; done
  cat "$HARNESS_DIR/core/fragments/dependabot.actions.yml"; } | render > "$TMP/dependabot"
put "$TMP/dependabot" ".github/dependabot.yml"

{ cat "$HARNESS_DIR/core/fragments/AGENTS.head.md"
  for m in $MODS; do cat "$HARNESS_DIR/modules/$m/AGENTS.commands.md"; done
  [ -z "$MODS" ] && echo "TODO: test / lint / run commands"
  cat "$HARNESS_DIR/core/fragments/AGENTS.tail.md"; } | render > "$TMP/agents"
put "$TMP/agents" "AGENTS.md"

if [ ! -e "$TARGET/CLAUDE.md" ] && [ ! -L "$TARGET/CLAUDE.md" ]; then
  [ "$DRY" = 1 ] || ln -s AGENTS.md "$TARGET/CLAUDE.md"
  N_NEW=$((N_NEW+1)); log created "CLAUDE.md -> AGENTS.md"
else N_SAME=$((N_SAME+1)); log same "CLAUDE.md"; fi

# MCP config: merge servers into any existing .cursor/mcp.json, never replace one that exists.
frags=""; for m in $MODS; do [ -f "$HARNESS_DIR/modules/$m/mcp.fragment.json" ] && { render "$HARNESS_DIR/modules/$m/mcp.fragment.json" > "$TMP/mcp.$m"; frags="$frags $TMP/mcp.$m"; }; done
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
if [ "$PHP" = 1 ]; then need php "brew install php"; need composer "brew install composer"
  if [ -x "$COMPOSER_BIN/xdebug-mcp" ]; then log ok "xdebug-mcp"; else log MISSING "xdebug-mcp — composer global require koriym/xdebug-mcp"; fi; fi
[ "$GO" = 1 ] && { need go "brew install go"; need golangci-lint "optional: brew install golangci-lint"; need dlv "optional: brew install delve"; }
[ "$WEB" = 1 ] && { need node "brew install node"; need npm "ships with node"; }

# ---- 5. installs (opt-in: they add dependencies to your project)
INSTALL_CMDS=()
if [ "$PHP" = 1 ]; then
  [ -f "$TARGET/$PHP_DIR/composer.json" ] && INSTALL_CMDS+=("cd '$TARGET/$PHP_DIR' && composer require --dev phpstan/phpstan --no-interaction")
  [ -x "$COMPOSER_BIN/xdebug-mcp" ] || INSTALL_CMDS+=("composer global require koriym/xdebug-mcp --no-interaction")
fi
if [ "$WEB" = 1 ]; then
  [ -f "$TARGET/$WEB_DIR/package.json" ] && INSTALL_CMDS+=("cd '$TARGET/$WEB_DIR' && { npm ls @playwright/test >/dev/null 2>&1 || npm i -D @playwright/test; } && npx playwright install chromium chromium-headless-shell")
  [ -f "$TARGET/$WEB_DIR/package.json" ] && INSTALL_CMDS+=("cd '$TARGET/$WEB_DIR' && [ -f .claude/agents/playwright-test-planner.md ] || { [ -f seed.spec.ts ] && cp seed.spec.ts \"$TMP/seed.bak\"; npx playwright init-agents --loop=claude; [ -f \"$TMP/seed.bak\" ] && cp \"$TMP/seed.bak\" seed.spec.ts; true; }")
  INSTALL_CMDS+=("cd '$TARGET/vr' && npm install")
fi
echo; echo "Installs:"
if [ "${#INSTALL_CMDS[@]}" -eq 0 ]; then log none "nothing to install"
elif [ "$INSTALL" = 1 ] && [ "$DRY" != 1 ]; then
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
