#!/usr/bin/env bash
# workspace-clone.sh — phase 2 of the workspace-orchestration plan: opt-in, confirmed
# repository acquisition (see docs/workspace-orchestration-plan.md §4.2).
#
# Cloning only ever happens in `apply` mode, and only for entries you name (or every entry,
# if you name none). `plan` mode never touches disk — it classifies each entry so the command
# can show you the plan before anything clones. Nothing here resets, overwrites, or deletes an
# existing directory; a destination that already exists and doesn't match is a collision,
# reported and skipped, never touched.
#
# usage:
#   workspace-clone.sh plan  <inventory-file> [workspace-dir]
#   workspace-clone.sh apply <inventory-file> [workspace-dir] [name...]
#
# inventory-file: one repo per non-blank, non-'#' line:
#   <git-url>              destination dir name = URL basename, .git stripped
#   <name>=<git-url>       explicit destination dir name
#
# workspace-dir: directory destinations resolve under (default: current directory)
# name...: (apply only) clone only these entries; omit to apply every entry in the file
#
# exit (plan):  0 = plan printed (always — plan mode cannot fail once the file is readable)
#               1 = usage error / inventory file or workspace dir not found
# exit (apply): 0 = every requested entry cloned, or already present with a matching remote
#               1 = usage error / inventory file or workspace dir not found
#               2 = at least one requested entry hit a collision or a git-clone failure —
#                   every other entry still completed; see per-repo lines on stdout/stderr

set -u

CMD="${1:?usage: workspace-clone.sh plan|apply <inventory-file> [workspace-dir] [name...]}"
INV="${2:?inventory file required}"
[ -f "$INV" ] || { echo "workspace-clone: no such inventory file: $INV" >&2; exit 1; }
WS_DIR="${3:-.}"
[ -d "$WS_DIR" ] || { echo "workspace-clone: no such workspace dir: $WS_DIR" >&2; exit 1; }
NAMES=""
if [ "$CMD" = "apply" ] && [ $# -ge 4 ]; then
  shift 3
  NAMES="$*"
fi

ENTRIES=$(awk '
  /^[ \t]*#/ { next }
  /^[ \t]*$/ { next }
  {
    line=$0; gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (match(line, /^[^=]+=/)) {
      name=substr(line, 1, RSTART+RLENGTH-2)
      url=substr(line, RSTART+RLENGTH)
    } else {
      url=line
      name=url
      sub(/\.git$/, "", name)
      sub(/.*[\/:]/, "", name)
    }
    printf "%s|%s\n", name, url
  }
' "$INV")
[ -n "$ENTRIES" ] || { echo "workspace-clone: no entries found in $INV" >&2; exit 1; }

# classify DEST URL -> missing | matches | collision
classify() {
  local dest="$1" url="$2"
  [ -e "$dest" ] || { echo "missing"; return; }
  if git -C "$dest" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local remote
    remote=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
    [ "$remote" = "$url" ] && echo "matches" || echo "collision"
  else
    echo "collision"
  fi
}

wanted() {   # name -> 0 if included in this run
  [ -z "$NAMES" ] && return 0
  case " $NAMES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

case "$CMD" in
  plan)
    printf '%-24s %-10s %s\n' "NAME" "STATUS" "DESTINATION <- URL"
    while IFS='|' read -r name url; do
      [ -n "$name" ] || continue
      dest="$WS_DIR/$name"
      printf '%-24s %-10s %s <- %s\n' "$name" "$(classify "$dest" "$url")" "$dest" "$url"
    done <<<"$ENTRIES"
    exit 0
    ;;
  apply)
    FAIL=0
    while IFS='|' read -r name url; do
      [ -n "$name" ] || continue
      wanted "$name" || continue
      dest="$WS_DIR/$name"
      status=$(classify "$dest" "$url")
      case "$status" in
        matches)
          echo "workspace-clone: $name already present at $dest (origin matches) — skipped" ;;
        collision)
          echo "workspace-clone: $name: $dest exists and is not a clone of $url — skipped, not touched" >&2
          FAIL=1 ;;
        missing)
          if git clone -- "$url" "$dest" >/dev/null 2>&1; then
            echo "workspace-clone: cloned $name -> $dest"
          else
            echo "workspace-clone: $name: clone failed ($url)" >&2
            FAIL=1
          fi ;;
      esac
    done <<<"$ENTRIES"
    [ "$FAIL" -eq 0 ] && exit 0
    exit 2
    ;;
  *)
    echo "workspace-clone: unknown command '$CMD' (expected plan|apply)" >&2
    exit 1
    ;;
esac
