#!/usr/bin/env bash
# workspace-validate.sh — workspace-orchestration plan, phases 1+3
# (see docs/workspace-orchestration-plan.md §3/§3.2/§12).
#
# Two independent checks, both skip cleanly when not applicable:
#   - shared.methodology (phase 3, always checked when the key is present, regardless of
#     schemaVersion — this field predates the additive schema and is read by every topology)
#   - the OPTIONAL schemaVersion/components/relationships sections (phase 1, additive; only
#     checked when `schemaVersion:` is present)
# A manifest with none of these keys (today's shape) is untouched and always passes — this is
# the backward-compatibility bar. contract-check.sh is unmodified and keeps reading
# `contracts:` exactly as before; this script never touches that section.
#
# usage: workspace-validate.sh [path-to-workspace.yaml]
#   no arg = same manifest lookup as contract-check.sh (./workspace.yaml, ../workspace.yaml,
#            or $WORKSPACE_MANIFEST)
# exit:  0 = nothing to check, or every check passed
#        1 = manifest not found when an explicit path was given
#        2 = at least one check failed (details on stderr)

set -u

MANIFEST="${1:-}"
if [ -n "$MANIFEST" ]; then
  [ -f "$MANIFEST" ] || { echo "workspace-validate: no such file: $MANIFEST" >&2; exit 1; }
else
  for c in "${WORKSPACE_MANIFEST:-}" workspace.yaml ../workspace.yaml; do
    [ -n "$c" ] && [ -f "$c" ] && MANIFEST="$c" && break
  done
  [ -n "$MANIFEST" ] || exit 0   # not a workspace project — silent no-op, same as contract-check.sh
fi

FAIL=0
fail() { echo "workspace-validate: $1" >&2; FAIL=1; }

# --- shared.methodology (phase 3 — checked regardless of schemaVersion) ---
METHOD=$(awk '
  $0 ~ /^[ \t]*shared:[ \t]*$/ { ins=1; shdr=match($0, /[^ \t]/) - 1; next }
  ins && $0 !~ /^[ \t]*$/ {
    indent=match($0, /[^ \t]/) - 1
    if (indent <= shdr) ins=0
  }
  ins && /^[ \t]+methodology:/ {
    v=$0; sub(/^[ \t]+methodology:[ \t]*/, "", v); gsub(/^"|"$/, "", v)
    print v; exit
  }
' "$MANIFEST")
if [ -n "$METHOD" ]; then
  case "$METHOD" in
    bmad|spec-kit|openspec) ;;
    *) fail "shared.methodology '$METHOD' is not one of bmad|spec-kit|openspec" ;;
  esac
fi

grep -qE '^schemaVersion:[[:space:]]*[0-9]+' "$MANIFEST" || { \
  if [ "$FAIL" -eq 0 ]; then echo "workspace-validate: clean"; exit 0; fi; exit 2; \
}

# --- units: name -> path-or-repo-basename (supports block style and flow `{ ... }` style) ---
# `units:` is nested under `workspace:` (2-space indent) per templates/workspace.yaml, unlike
# the top-level contracts:/components:/relationships: sections, so track by indentation depth
# rather than column 0.
UNITS=$(awk '
  $0 ~ /^[ \t]*units:[ \t]*$/ {
    inu=1; hdr=match($0, /[^ \t]/) - 1; next
  }
  inu && $0 !~ /^[ \t]*$/ {
    indent=match($0, /[^ \t]/) - 1
    if (indent <= hdr) inu=0
  }
  inu {
    line=$0
    if (match(line, /\{.*\}/)) {                       # flow style: - { name: x, path: y, ... }
      inner=substr(line, RSTART+1, RLENGTH-2)
      n=split(inner, parts, ",")
      name=""; val=""
      for (i=1;i<=n;i++) {
        p=parts[i]; gsub(/^[ \t]+|[ \t]+$/, "", p)
        if (p ~ /^name:/)      { sub(/^name:[ \t]*/, "", p); name=p }
        else if (p ~ /^path:/) { sub(/^path:[ \t]*/, "", p); val=p }
        else if (p ~ /^repo:/) { sub(/^repo:[ \t]*/, "", p); val=p }
      }
      if (name != "") printf "%s|%s\n", name, val
    } else if (line ~ /^[ \t]*-[ \t]*name:/) {          # block style: - name: x  (then path:/repo: follow)
      if (uname != "") printf "%s|%s\n", uname, uval
      uname=line; sub(/^[ \t]*-[ \t]*name:[ \t]*/, "", uname); uval=""
    } else if (line ~ /^[ \t]+path:/ && uname != "") {
      v=line; sub(/^[ \t]+path:[ \t]*/, "", v); uval=v
    } else if (line ~ /^[ \t]+repo:/ && uname != "") {
      v=line; sub(/^[ \t]+repo:[ \t]*/, "", v); uval=v
    }
  }
  END { if (uname != "") printf "%s|%s\n", uname, uval }
' "$MANIFEST")

unit_covers_path() {   # $1 = component boundary path
  local p="$1" uname uval base
  while IFS='|' read -r uname uval; do
    [ -n "$uname" ] || continue
    base=$(basename "${uval%.git}")
    case "$p" in
      "$uname"|"$uname"/*|"$uval"|"$uval"/*|"$base"|"$base"/*) return 0 ;;
    esac
  done <<<"$UNITS"
  return 1
}

# --- components: id|kind|boundary.type|boundary.path ---
COMPONENTS=$(awk '
  /^components:/ { inc=1; next }
  inc && /^[^ ]/ { inc=0 }
  inc && /^[ \t]*-[ \t]*id:/ {
    if (id != "") printf "%s|%s|%s|%s\n", id, kind, btype, bpath
    id=$0; sub(/^[ \t]*-[ \t]*id:[ \t]*/, "", id); kind=""; btype=""; bpath=""
  }
  inc && /^[ \t]+kind:/        { v=$0; sub(/^[ \t]+kind:[ \t]*/, "", v); kind=v }
  inc && /^[ \t]+type:/        { v=$0; sub(/^[ \t]+type:[ \t]*/, "", v); btype=v }
  inc && /^[ \t]+path:/        { v=$0; sub(/^[ \t]+path:[ \t]*/, "", v); bpath=v }
  END { if (id != "") printf "%s|%s|%s|%s\n", id, kind, btype, bpath }
' "$MANIFEST")

declare -A SEEN_IDS=()
while IFS='|' read -r cid ckind ctype cpath; do
  [ -n "$cid" ] || continue
  if [ -n "${SEEN_IDS[$cid]:-}" ]; then
    fail "duplicate component id '$cid'"
  fi
  SEEN_IDS[$cid]=1
  case "$ctype" in
    repo|monorepo-package|module) ;;
    *) fail "component '$cid': boundary.type '$ctype' is not one of repo|monorepo-package|module" ;;
  esac
  if [ -z "$cpath" ]; then
    fail "component '$cid': boundary.path is empty"
  elif ! unit_covers_path "$cpath"; then
    fail "component '$cid': boundary.path '$cpath' does not resolve inside any declared unit"
  fi
done <<<"$COMPONENTS"

# --- relationships: from|to|type|evidence ---
RELATIONSHIPS=$(awk '
  /^relationships:/ { inr=1; next }
  inr && /^[^ ]/ { inr=0 }
  inr && /^[ \t]*-[ \t]*from:/ {
    if (from != "") printf "%s|%s|%s|%s\n", from, to, rtype, evidence
    from=$0; sub(/^[ \t]*-[ \t]*from:[ \t]*/, "", from); to=""; rtype=""; evidence=""
  }
  inr && /^[ \t]+to:/        { v=$0; sub(/^[ \t]+to:[ \t]*/, "", v); to=v }
  inr && /^[ \t]+type:/      { v=$0; sub(/^[ \t]+type:[ \t]*/, "", v); rtype=v }
  inr && /^[ \t]+evidence:/  { v=$0; sub(/^[ \t]+evidence:[ \t]*/, "", v); evidence=v }
  END { if (from != "") printf "%s|%s|%s|%s\n", from, to, rtype, evidence }
' "$MANIFEST")

while IFS='|' read -r rfrom rto rtype revidence; do
  [ -n "$rfrom" ] || continue
  if [ -z "${SEEN_IDS[$rfrom]:-}" ]; then
    fail "relationship from:'$rfrom' is not a declared component id"
  fi
  if [ -z "${SEEN_IDS[$rto]:-}" ]; then
    fail "relationship to:'$rto' is not a declared component id"
  fi
  case "$rtype" in
    calls|publishes-to|consumes-from|depends-on|owns-data-for|deployed-with|tested-by) ;;
    *) fail "relationship $rfrom -> $rto: type '$rtype' is not a recognized relationship type" ;;
  esac
  if [ -z "$revidence" ]; then
    fail "relationship $rfrom -> $rto: missing evidence — no evidence, no relationship (see §3.1)"
  fi
done <<<"$RELATIONSHIPS"

if [ "$FAIL" -eq 0 ]; then
  echo "workspace-validate: clean"
  exit 0
fi
exit 2
