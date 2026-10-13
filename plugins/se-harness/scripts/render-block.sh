#!/usr/bin/env bash
# render-block.sh — idempotent SEAA:GENERATED block splice (A5/§2 merge mechanism) with
# hand-edit detection.
#
# usage: render-block.sh [--force] <target-file> <content-file>
#        render-block.sh --check <target-file>
#   <content-file> holds the INNER block content only (no markers — this script owns the markers).
#
# Behavior:
#   target missing            → create it: markers wrapping content + editable-area hint
#   target has markers        → replace ONLY the content between markers; everything else untouched
#   target exists, no markers → prepend the marked block above existing content (never modifies it)
#
# Baseline hash: the END marker records `sha=<hash>` of the inner content as last rendered.
# Before replacing a block, the script re-hashes what is there now:
#   hash matches        → block is untouched since last render → safe to replace
#   hash differs        → someone edited INSIDE the generated block → exit 3, target untouched,
#                         new content saved beside it as <target>.seaa.proposed. `--force`
#                         overwrites anyway, saving the edited block as <target>.seaa.bak first.
#   no recorded hash    → block predates hash baselines (legacy) → replaced as before, baseline
#                         recorded from now on.
#
# --check prints one word and exits 0: missing | no-markers | legacy | clean | modified.
#
# exit codes: 0 ok · 1 usage/error · 3 conflict (block hand-edited, not overwritten)

set -eu

MODE=write
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --check) MODE=check; shift ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done

TARGET="${1:?usage: render-block.sh [--force] <target-file> <content-file> | --check <target-file>}"
CONTENT="${2:-}"

START_LINE='<!-- SEAA:GENERATED:START — managed by se-harness; sync rewrites ONLY this block. -->'
END_PREFIX='<!-- SEAA:GENERATED:END'

HASHER="sha256sum"
command -v sha256sum >/dev/null 2>&1 || HASHER="shasum -a 256"

# Normalize (strip CR, guarantee a trailing newline) so hashes are stable across CRLF checkouts.
norm() { tr -d '\r' | awk '{print}'; }
hash_stdin() { norm | $HASHER | awk '{print substr($1,1,16)}'; }

# Inner content of the existing block (between the marker lines, exclusive).
inner_of() {
  awk '/SEAA:GENERATED:END/ {inblock=0} inblock {print} /SEAA:GENERATED:START/ {inblock=1}' "$1"
}
# Recorded baseline from the END marker, empty if none.
recorded_of() {
  grep -m1 'SEAA:GENERATED:END' "$1" | sed -n 's/.*sha=\([0-9a-f]\{8,\}\).*/\1/p'
}

if [ "$MODE" = check ]; then
  if [ ! -f "$TARGET" ]; then echo missing; exit 0; fi
  if ! grep -q 'SEAA:GENERATED:START' "$TARGET"; then echo no-markers; exit 0; fi
  rec=$(recorded_of "$TARGET")
  if [ -z "$rec" ]; then echo legacy; exit 0; fi
  cur=$(inner_of "$TARGET" | hash_stdin)
  if [ "$cur" = "$rec" ]; then echo clean; else echo modified; fi
  exit 0
fi

[ -n "$CONTENT" ] || { echo "usage: render-block.sh [--force] <target-file> <content-file>" >&2; exit 1; }
[ -f "$CONTENT" ] || { echo "content file not found: $CONTENT" >&2; exit 1; }

NEW_HASH=$(hash_stdin < "$CONTENT")
END_LINE="$END_PREFIX sha=$NEW_HASH -->"

if [ ! -f "$TARGET" ]; then
  {
    echo "$START_LINE"
    norm < "$CONTENT"
    echo "$END_LINE"
    echo ""
    echo "<!-- Hand-written notes below this line survive every sync. -->"
  } > "$TARGET"
  echo "created: $TARGET"
elif grep -q 'SEAA:GENERATED:START' "$TARGET"; then
  rec=$(recorded_of "$TARGET")
  cur=$(inner_of "$TARGET" | hash_stdin)
  note=""
  if [ -z "$rec" ]; then
    note=" (legacy block: no prior baseline, recorded now)"
  elif [ "$cur" != "$rec" ] && [ "$cur" != "$NEW_HASH" ]; then
    if [ "$FORCE" -ne 1 ]; then
      norm < "$CONTENT" > "$TARGET.seaa.proposed"
      echo "conflict: generated block in $TARGET was edited by hand; left untouched." >&2
      echo "  proposed new block: $TARGET.seaa.proposed" >&2
      echo "  re-run with --force to overwrite (edited block is saved to $TARGET.seaa.bak)" >&2
      exit 3
    fi
    inner_of "$TARGET" > "$TARGET.seaa.bak"
    note=" (hand edits overwritten; previous block saved to $TARGET.seaa.bak)"
  fi
  awk -v cf="$CONTENT" -v endline="$END_LINE" '
    /SEAA:GENERATED:START/ { print; while ((getline line < cf) > 0) { sub(/\r$/, "", line); print line } close(cf); inblock=1; next }
    /SEAA:GENERATED:END/   { print endline; inblock=0; next }
    !inblock               { print }
  ' "$TARGET" > "$TARGET.seaa.tmp" && mv "$TARGET.seaa.tmp" "$TARGET"
  rm -f "$TARGET.seaa.proposed"
  echo "updated block: $TARGET$note"
else
  {
    echo "$START_LINE"
    norm < "$CONTENT"
    echo "$END_LINE"
    echo ""
    cat "$TARGET"
  } > "$TARGET.seaa.tmp" && mv "$TARGET.seaa.tmp" "$TARGET"
  echo "prepended block: $TARGET (existing content preserved below)"
fi
