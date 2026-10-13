#!/usr/bin/env bash
# contract-check.sh — multi-repo tier 2 (A6): deterministic cross-unit impact check.
# When a change touches a contract file declared in workspace.yaml, flag every declared
# consumer — the "order-service changed its API, does payment-service still match?" case,
# solved without a service graph.
#
# usage: contract-check.sh <base-ref|-->   standalone (-- = auto base: origin/main, else HEAD~1)
#        no args = hook mode (PreToolUse pipes tool JSON on stdin; fires only on push/PR).
# exit:  0 = no contract impact (or no manifest — not a workspace project)
#        2 = contract changed; consumers listed on stderr

set -u
# Locate the manifest FIRST (before any stdin read): repo root, parent (meta-repo checkout
# beside member repos), or env. Not a workspace project → silent no-op.
MANIFEST=""
for c in "${WORKSPACE_MANIFEST:-}" workspace.yaml ../workspace.yaml; do
  [ -n "$c" ] && [ -f "$c" ] && MANIFEST="$c" && break
done
[ -n "$MANIFEST" ] || exit 0

# Mode by arguments (never probe the TTY — non-TTY shells without piped stdin would hang):
# args present = standalone (stdin untouched); no args = hook mode (stdin is always piped).
BASE=""
if [ $# -ge 1 ]; then
  [ "$1" != "--" ] && BASE="$1"
else
  INPUT=$(cat 2>/dev/null || true)
  if printf '%s' "$INPUT" | grep -q '"command"'; then
    CMD=$(printf '%s' "$INPUT" \
      | grep -oE '"command"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"' | head -1 \
      | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//; s/\\"/"/g; s/\\\\/\\/g')
    # shellcheck source=irreversible-cmd.sh
    . "$(dirname "${BASH_SOURCE[0]}")/irreversible-cmd.sh"
    is_irreversible "$CMD" && [ "$IRR_KIND" != deploy ] || exit 0
  fi
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
if [ -z "$BASE" ]; then
  if git rev-parse --verify -q origin/main >/dev/null; then BASE="origin/main";
  elif git rev-parse --verify -q HEAD~1 >/dev/null; then BASE="HEAD~1"; fi
  # No resolvable base (fresh repo): still check staged + working-tree changes below.
fi

CHANGED=$(
  [ -n "$BASE" ] && git diff --name-only "$BASE"...HEAD 2>/dev/null
  git diff --name-only 2>/dev/null
  git diff --cached --name-only 2>/dev/null
)
[ -n "$CHANGED" ] || exit 0

# Parse the contracts: section (strict stanza shape — see templates/workspace.yaml).
# Emits: name|file|provider|consumers
IMPACT=0
while IFS='|' read -r cname cfile cprovider cconsumers; do
  [ -n "$cfile" ] || continue
  if printf '%s\n' "$CHANGED" | grep -qxF "$cfile"; then
    IMPACT=1
    echo "se-harness contract-check: contract '$cname' ($cfile) changed." >&2
    echo "  provider:  ${cprovider:-unknown}" >&2
    echo "  consumers: ${cconsumers:-none declared}" >&2
    echo "  → verify each consumer still matches, and link consumer tasks to this REQ." >&2
  fi
done <<EOF
$(awk '
  /^contracts:/ { inc=1; next }
  inc && /^[^ ]/ { inc=0 }
  inc && /^  - name:/    { if (name != "") printf "%s|%s|%s|%s\n", name, file, prov, cons;
                           name=$3; file=""; prov=""; cons="" }
  inc && /^    file:/     { file=$2 }
  inc && /^    provider:/ { prov=$2 }
  inc && /^    consumers:/ { sub(/^    consumers:[ ]*/, ""); gsub(/[\[\]]/, ""); cons=$0 }
  END { if (name != "") printf "%s|%s|%s|%s\n", name, file, prov, cons }
' "$MANIFEST")
EOF

[ "$IMPACT" -eq 1 ] && exit 2
exit 0
