#!/usr/bin/env bash
# workspace-scan-evidence.sh — §10 of the workspace-orchestration plan: the deterministic
# collector for a full workspace-root /harness-scan pass. Run from the workspace root (not
# from inside a member repo — that's scan-evidence.sh's job, called once per unit below).
#
# For each unit declared in workspace.yaml (or, lacking a manifest yet, each entry in
# repos.txt), resolves its path and either runs scan-evidence.sh there (tagged by unit name)
# or reports why it couldn't: not cloned yet, or cloned but not bootstrapped
# (no .harness/profile.yaml — /harness-init hasn't run there). NEVER modifies anything, and
# NEVER guesses at a unit that isn't ready; the caller decides how to handle partial coverage.
#
# usage: workspace-scan-evidence.sh [workspace-dir]   (default: .)
# exit:  0 = report printed (always; this is a read-only collector, like scan-evidence.sh)
#        1 = no workspace.yaml and no repos.txt found in workspace-dir

set -u
WS_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN_EVIDENCE="$SCRIPT_DIR/scan-evidence.sh"

MANIFEST="$WS_DIR/workspace.yaml"
INV="$WS_DIR/repos.txt"

if [ -f "$MANIFEST" ]; then
  # units: name -> path-or-repo-basename (same extraction as workspace-validate.sh — supports
  # both block style and flow `{ ... }` style, since `units:` is nested under `workspace:`).
  ENTRIES=$(awk '
    $0 ~ /^[ \t]*units:[ \t]*$/ { inu=1; hdr=match($0, /[^ \t]/) - 1; next }
    inu && $0 !~ /^[ \t]*$/ {
      indent=match($0, /[^ \t]/) - 1
      if (indent <= hdr) inu=0
    }
    inu {
      line=$0
      if (match(line, /\{.*\}/)) {
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
      } else if (line ~ /^[ \t]*-[ \t]*name:/) {
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
elif [ -f "$INV" ]; then
  # repos.txt: same format workspace-clone.sh reads — <git-url> or <name>=<git-url>.
  ENTRIES=$(awk '
    /^[ \t]*#/ { next }
    /^[ \t]*$/ { next }
    {
      line=$0; gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (match(line, /^[^=]+=/)) {
        name=substr(line, 1, RSTART+RLENGTH-2); url=substr(line, RSTART+RLENGTH)
      } else {
        url=line; name=url
        sub(/\.git$/, "", name); sub(/.*[\/:]/, "", name)
      }
      printf "%s|%s\n", name, url
    }
  ' "$INV")
else
  echo "workspace-scan-evidence: no workspace.yaml or repos.txt in $WS_DIR" >&2
  exit 1
fi

[ -n "$ENTRIES" ] || { echo "workspace-scan-evidence: no units found" >&2; exit 1; }

N_SCANNED=0; N_SKIPPED=0
DECLARED_TOPDIRS=""   # top-level dir name each declared unit lives under — for the
                      # undeclared-directory check below
while IFS='|' read -r name val; do
  [ -n "$name" ] || continue
  # repo: form (a git URL — http(s)://, git@, or ending .git) follows the sibling-clone
  # convention (dest dir = unit name), same as workspace-clone.sh/workspace-validate.sh
  # assume. path: form is relative to the workspace dir as-is, and may be nested
  # (mono-repo units commonly live under services/<name> etc.) — never collapse it to
  # just the unit name.
  case "$val" in
    http://*|https://*|git@*|*.git) unit_path="$WS_DIR/$name"; rel="$name" ;;
    "") unit_path="$WS_DIR/$name"; rel="$name" ;;
    *) unit_path="$WS_DIR/$val"; rel="$val" ;;
  esac
  DECLARED_TOPDIRS="$DECLARED_TOPDIRS ${rel%%/*}"

  printf '\n===== UNIT: %s (%s) =====\n' "$name" "$unit_path"
  if [ ! -d "$unit_path" ]; then
    echo "NOT-CLONED: no directory at $unit_path — run workspace-clone.sh or clone manually first."
    N_SKIPPED=$((N_SKIPPED + 1))
  elif [ ! -f "$unit_path/.harness/profile.yaml" ]; then
    echo "NOT-BOOTSTRAPPED: $unit_path exists but has no .harness/profile.yaml — run /harness-init there first."
    N_SKIPPED=$((N_SKIPPED + 1))
  else
    bash "$SCAN_EVIDENCE" "$unit_path"
    N_SCANNED=$((N_SCANNED + 1))
  fi
done <<<"$ENTRIES"

# Boundary drift (§10): a top-level directory that looks like a unit (has its own .git or
# .harness) but isn't declared anywhere above — a candidate to PROPOSE adding, never added
# silently. Noise directories are skipped outright, never reported as a finding.
printf '\n===== UNDECLARED CANDIDATES (top-level dirs not in the manifest) =====\n'
FOUND_UNDECLARED=0
for d in "$WS_DIR"/*/; do
  [ -d "$d" ] || continue
  base=$(basename "$d")
  case "$base" in
    .git|.harness|node_modules|.venv|venv|dist|build|target|vendor) continue ;;
  esac
  case " $DECLARED_TOPDIRS " in *" $base "*) continue ;; esac
  if [ -d "$d/.git" ] || [ -f "$d/.harness/profile.yaml" ]; then
    echo "UNDECLARED: $d (has $( [ -d "$d/.git" ] && echo -n ".git "; [ -f "$d/.harness/profile.yaml" ] && echo -n ".harness/profile.yaml")) — not in workspace.yaml's units:"
    FOUND_UNDECLARED=$((FOUND_UNDECLARED + 1))
  fi
done
[ "$FOUND_UNDECLARED" -eq 0 ] && echo "(none)"

printf '\n===== WORKSPACE SCAN SUMMARY =====\n'
echo "scanned: $N_SCANNED, skipped: $N_SKIPPED, undeclared: $FOUND_UNDECLARED"
exit 0
