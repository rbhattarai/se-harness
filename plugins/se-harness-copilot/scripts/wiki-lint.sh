#!/usr/bin/env bash
# wiki-lint.sh — deterministic health-check for the domain wiki (tier 3 memory).
# Mechanical companion to the wiki-lint skill: index drift, orphan pages, missing
# provenance, contradiction markers, oversize pages, and credential-shaped content
# are all computable — findings here need no LLM judgment. The skill runs this
# first, applies mechanical fixes directly, and reserves LLM judgment for
# contradiction resolution + staleness (grounded by the SOURCES section below).
# NEVER modifies anything. No network, no jq.
# usage: wiki-lint.sh [wiki-dir]   (default: .harness/memory/wiki)
# Exit 0 = clean, 1 = findings, 2 = usage/error.

set -u
WIKI="${1:-.harness/memory/wiki}"
[ -d "$WIKI" ] || { echo "wiki-lint: no such directory: $WIKI" >&2; exit 2; }
cd "$WIKI" || exit 2

FINDINGS=0
section() { printf '\n===== %s =====\n' "$1"; }
found() { FINDINGS=$((FINDINGS + 1)); printf '%s\n' "$1"; }
none_yet=0
maybe_none() { [ "$none_yet" -eq 1 ] || echo "(none)"; none_yet=0; }
hit() { none_yet=1; found "$1"; }

# Pages under check: every *.md except the index and the log.
PAGES=""
for f in *.md; do
  [ -f "$f" ] || continue
  case "$f" in index.md|log.md) continue;; esac
  PAGES="$PAGES $f"
done
PAGES="${PAGES# }"
N_PAGES=$(printf '%s' "$PAGES" | wc -w)

section "INDEX DRIFT"
if [ ! -f index.md ]; then
  hit "INDEX-MISSING: index.md not found"
else
  # Strip single-line HTML comments (the template's commented examples) so the
  # example links don't read as dangling.
  IDX_LINKS=$(sed 's/<!--.*-->//g' index.md \
    | grep -oE '\[[^]]+\]\([^)]*\.md\)' 2>/dev/null \
    | sed -E 's/.*\(([^)]+)\)/\1/' | sort -u || true)
  for p in $PAGES; do
    printf '%s\n' "$IDX_LINKS" | grep -qxF "$p" 2>/dev/null \
      || hit "MISSING-FROM-INDEX: $p"
  done
  for t in $IDX_LINKS; do
    [ -f "$t" ] || hit "DANGLING-INDEX-LINK: index.md -> $t"
  done
fi
[ -f log.md ] || hit "LOG-MISSING: log.md not found"
maybe_none

section "ORPHANS (no inbound [[link]] from another page)"
for p in $PAGES; do
  stem="${p%.md}"
  inbound=0
  for q in $PAGES; do
    [ "$q" = "$p" ] && continue
    if grep -qF "[[$stem]]" "$q" 2>/dev/null; then inbound=1; break; fi
  done
  # index.md lists every page by design, so it never counts as inbound.
  [ "$inbound" -eq 0 ] && hit "ORPHAN: $p"
done
maybe_none

section "PROVENANCE (pages lacking a sources: footer)"
for p in $PAGES; do
  grep -q '^sources:' "$p" 2>/dev/null || hit "NO-SOURCES: $p"
done
maybe_none

section "CONTRADICTION MARKERS (locate only — resolution is human)"
# Any all-caps CONTRADICTION marker, with or without the ⚠ glyph the skill specifies.
for p in $PAGES; do
  while IFS= read -r ln; do
    [ -n "$ln" ] && hit "CONTRADICTION: $p:$ln"
  done < <(grep -nF 'CONTRADICTION' "$p" 2>/dev/null | cut -d: -f1)
done
maybe_none

section "SIZE (pages over 150 lines — propose splits)"
for p in $PAGES; do
  n=$(wc -l < "$p")
  [ "$n" -gt 150 ] && hit "OVERSIZE: $p ($n lines)"
done
maybe_none

section "SECRETS SWEEP (file:line only — content never echoed)"
SECRET_RE='AKIA[0-9A-Z]{16}|aws_secret_access_key|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]+|api[_-]?key[[:space:]]*[:=][[:space:]]*['\''"][^'\''"]+|password[[:space:]]*[:=][[:space:]]*['\''"][^'\''"]+'
while IFS= read -r loc; do
  [ -n "$loc" ] && hit "SECRET-HIT: $loc"
done < <(grep -nE "$SECRET_RE" *.md 2>/dev/null | cut -d: -f1,2 | sort -u)
maybe_none

section "SOURCES (verbatim — grounds the skill's staleness judgment)"
for p in $PAGES; do
  grep -H '^sources:' "$p" 2>/dev/null || echo "$p: (no sources: line)"
done

printf '\n'
[ "$N_PAGES" -eq 1 ] && pages="page" || pages="pages"
[ "$FINDINGS" -eq 1 ] && findings="finding" || findings="findings"
if [ "$FINDINGS" -eq 0 ]; then
  echo "wiki-lint: clean ($N_PAGES $pages checked)"
  exit 0
fi
echo "wiki-lint: $FINDINGS $findings ($N_PAGES $pages checked)"
exit 1
