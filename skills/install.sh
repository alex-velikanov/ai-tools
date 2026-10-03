#!/usr/bin/env bash
# Make the skills in this repo visible to Claude Code and Cursor.
#
# Both tools read ~/.claude/skills/, so one install location serves both. Each skill is
# symlinked individually (not the whole directory), so skills created there by other
# tools are left alone.
#
#   ./install.sh              link every skill (default)
#   ./install.sh --copy       copy instead of symlink (fallback if a tool won't follow links)
#   ./install.sh --force      replace skills that exist but differ (old one is backed up)
#   ./install.sh --dry-run    show what would happen
#   ./install.sh --target DIR install somewhere else (default: ~/.claude/skills)
#
# Status per skill: linked | copied | same | UPDATED | SKIP (differs) | created
set -euo pipefail

SRC="$(cd "$(dirname "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")")" && pwd)"
TARGET="$HOME/.claude/skills"; MODE=link; FORCE=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --copy) MODE=copy ;; --force) FORCE=1 ;; --dry-run) DRY=1 ;;
    --target) TARGET="$2"; shift ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac; shift
done

BACKUP="$(dirname "$TARGET")/skills-backup-$(date +%Y%m%d-%H%M%S)"
[ "$DRY" = 1 ] || mkdir -p "$TARGET"
log() { printf '  %-9s %s\n' "$1" "$2"; }
backup() { [ "$DRY" = 1 ] || { mkdir -p "$BACKUP"; mv "$1" "$BACKUP/"; }; }   # outside TARGET so it isn't loaded as a skill
place() {  # place <name>
  local n="$1" from="$SRC/$1" to="$TARGET/$1"
  if [ "$MODE" = link ]; then [ "$DRY" = 1 ] || ln -s "$from" "$to"; else [ "$DRY" = 1 ] || cp -R "$from" "$to"; fi
}

N_BAD=0
for dir in "$SRC"/*/; do
  name="$(basename "$dir")"; [ -f "$dir/SKILL.md" ] || continue
  to="$TARGET/$name"
  if [ -L "$to" ]; then
    if [ "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$to")" = "$SRC/$name" ] && [ "$MODE" = link ]; then log same "$name (already linked)"; continue; fi
    if [ "$FORCE" = 1 ]; then backup "$to"; place "$name"; log UPDATED "$name (was a link elsewhere / mode change)"; else log SKIP "$name (symlink to somewhere else; --force)"; N_BAD=$((N_BAD+1)); fi
  elif [ -d "$to" ]; then
    if diff -rq "$to" "$dir" >/dev/null 2>&1; then
      backup "$to"; place "$name"; log "$MODE" "$name (identical content replaced; old kept in $(basename "$BACKUP"))"
    elif [ "$FORCE" = 1 ]; then backup "$to"; place "$name"; log UPDATED "$name (differed; old kept in $(basename "$BACKUP"))"
    else log SKIP "$name (exists and DIFFERS from repo — --force to replace)"; diff -r "$to" "$dir" | sed -n '1,10p' | sed 's/^/              /' || true; N_BAD=$((N_BAD+1)); fi
  else
    place "$name"; log created "$name ($MODE)"
  fi
done
echo; echo "target: $TARGET   mode: $MODE   $( [ "$N_BAD" -gt 0 ] && echo "$N_BAD skipped" || echo ok )"
[ -d "$BACKUP" ] && echo "backup of replaced originals: $BACKUP (delete once you've confirmed everything works)"
exit 0
