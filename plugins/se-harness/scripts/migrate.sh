#!/usr/bin/env bash
# migrate.sh — upgrade a project's .harness/ data layout to the schema this plugin expects,
# without losing anything the project changed since it was bootstrapped.
#
# usage: migrate.sh [--status | --dry-run] [--allow-dirty] [--force-blocks] [project-dir]
#   --status        print current -> target schema and the pending chain; change nothing
#   --dry-run       same plus each pending migration's description; change nothing
#   --allow-dirty   proceed although .harness/AGENTS.md/CLAUDE.md/.mcp.json have uncommitted changes
#   --force-blocks  pass --force to render-block.sh (overwrite hand-edited generated blocks;
#                   edited text is still saved to <file>.seaa.bak). Only after the user said so.
#
# Model: the lockfile (.harness/agentstack.lock) carries "schema_version" (absent = 1).
# scripts/migrations/<N>-to-<N+1>.sh each lift the layout by one step; the runner chains them.
# Contract for migration scripts: see scripts/migrations/README.md.
#
# Safety: one backup (.harness/backup/<ts>-schema-<N>/files.tar) before any change; if ANY step
# fails the whole run is rolled back (modified files restored, newly created files removed).
#
# env: HARNESS_MIGRATIONS_DIR overrides the migrations directory (tests).
# exit: 0 ok / up to date · 1 error (rolled back) · 2 refused (dirty tree, project newer than
#       plugin, not bootstrapped) · 3 a generated block was hand-edited (rolled back)

set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIG_DIR="${HARNESS_MIGRATIONS_DIR:-$SCRIPT_DIR/migrations}"

MODE=run; ALLOW_DIRTY=0; FORCE_BLOCKS=0; PROJ=.
for a in "$@"; do
  case "$a" in
    --status) MODE=status ;;
    --dry-run) MODE=dry ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --force-blocks) FORCE_BLOCKS=1 ;;
    -*) echo "unknown option: $a" >&2; exit 1 ;;
    *) PROJ="$a" ;;
  esac
done

LOCK="$PROJ/.harness/agentstack.lock"
[ -f "$LOCK" ] || { echo "not bootstrapped: $LOCK not found (run /harness-init then /harness-bootstrap)" >&2; exit 2; }

get_schema() {
  v=$(grep -o '"schema_version"[[:space:]]*:[[:space:]]*[0-9]*' "$LOCK" | head -1 | grep -o '[0-9]*$' || true)
  echo "${v:-1}"
}
set_schema() {
  if grep -q '"schema_version"' "$LOCK"; then
    sed -E -i.bak "s/(\"schema_version\"[[:space:]]*:[[:space:]]*)[0-9]+/\1$1/" "$LOCK"
  else
    sed -i.bak "0,/{/s/{/{ \"schema_version\": $1,/" "$LOCK"
  fi
  rm -f "$LOCK.bak"
}

FROM=$(get_schema)
TARGET=1
for f in "$MIG_DIR"/*-to-*.sh; do
  [ -e "$f" ] || continue
  t=$(basename "$f" .sh); t=${t##*-to-}
  [ "$t" -gt "$TARGET" ] && TARGET=$t
done

if [ "$FROM" -gt "$TARGET" ]; then
  echo "project schema $FROM is newer than this plugin supports ($TARGET) — update the plugin first." >&2
  exit 2
fi

# Build the chain; every step must exist (no gaps).
CHAIN=""
i=$FROM
while [ "$i" -lt "$TARGET" ]; do
  n=$((i + 1)); m="$MIG_DIR/$i-to-$n.sh"
  [ -f "$m" ] || { echo "migration gap: $m is missing" >&2; exit 1; }
  CHAIN="$CHAIN $m"; i=$n
done

desc_of() { sed -n 's/^# migration: //p' "$1" | head -1; }

if [ "$MODE" != run ]; then
  echo "schema: $FROM -> $TARGET"
  if [ -z "$CHAIN" ]; then echo "up to date"; exit 0; fi
  for m in $CHAIN; do
    b=$(basename "$m" .sh)
    if [ "$MODE" = dry ]; then echo "  $b: $(desc_of "$m")"; else echo "  $b"; fi
  done
  exit 0
fi

if [ -z "$CHAIN" ]; then
  if ! grep -q '"schema_version"' "$LOCK"; then set_schema "$FROM"; echo "baseline recorded: schema_version $FROM"; fi
  echo "up to date (schema $FROM)"
  exit 0
fi

# --- guard: don't mix a migration into someone's uncommitted work ---
if [ "$ALLOW_DIRTY" -ne 1 ] && git -C "$PROJ" rev-parse --git-dir >/dev/null 2>&1; then
  dirty=$(git -C "$PROJ" status --porcelain -- .harness AGENTS.md CLAUDE.md .mcp.json 2>/dev/null | grep -v '^?? .harness/backup/' || true)
  if [ -n "$dirty" ]; then
    echo "refusing: uncommitted changes in harness files (commit or stash them, or pass --allow-dirty):" >&2
    echo "$dirty" >&2
    exit 2
  fi
fi

# --- backup ---
tracked_list() {
  ( cd "$PROJ"
    find .harness -path .harness/backup -prune -o -type f -print
    for f in AGENTS.md CLAUDE.md .mcp.json; do [ -f "$f" ] && echo "$f"; done ) | sort
}
TS=$(date +%Y%m%d-%H%M%S)
BK="$PROJ/.harness/backup/$TS-schema-$FROM"
mkdir -p "$BK"
tracked_list > "$BK/files.list"
( cd "$PROJ" && tar -cf "$BK/files.tar" -T "$BK/files.list" )

rollback() {
  ( cd "$PROJ"
    tracked_list_now=$(mktemp)
    ( find .harness -path .harness/backup -prune -o -type f -print
      for f in AGENTS.md CLAUDE.md .mcp.json; do [ -f "$f" ] && echo "$f"; done ) | sort > "$tracked_list_now"
    comm -13 "$BK/files.list" "$tracked_list_now" | while IFS= read -r f; do rm -f "$f"; done
    rm -f "$tracked_list_now"
    tar -xf "$BK/files.tar" )
}

export HARNESS_RENDER_BLOCK="$SCRIPT_DIR/render-block.sh"
export HARNESS_RENDER_FLAGS=""
[ "$FORCE_BLOCKS" -eq 1 ] && HARNESS_RENDER_FLAGS="--force"

for m in $CHAIN; do
  b=$(basename "$m" .sh); to=${b##*-to-}
  echo "migrating: $b — $(desc_of "$m")"
  rc=0
  bash "$m" "$PROJ" || rc=$?
  if [ "$rc" -ne 0 ]; then
    rollback
    if [ "$rc" -eq 3 ]; then
      echo "conflict in $b: a generated block was hand-edited. Rolled back; nothing changed." >&2
      echo "  review the *.seaa.proposed file(s), then re-run with --force-blocks to take the new blocks." >&2
      exit 3
    fi
    echo "FAILED in $b (exit $rc). Rolled back; nothing changed. Backup kept at $BK" >&2
    exit 1
  fi
  set_schema "$to"
  printf '%s\t%s\t%s\n' "$(date +%Y-%m-%d)" "$((to - 1))" "$to" >> "$PROJ/.harness/migrations.log"
done

echo "migrated schema $FROM -> $TARGET. Backup: $BK"
echo "next: run /harness-sync to refresh generated content, then commit."
