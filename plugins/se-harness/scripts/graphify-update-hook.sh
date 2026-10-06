#!/usr/bin/env bash
# graphify-update-hook.sh — PostToolUse hook on Bash (opt-in, wired per-repo by
# /harness-bootstrap only when Graphify is that repo's chosen structural-memory driver —
# never bundled into the plugin's global hooks.json, per the ECC "composable, opt-in" doctrine:
# a unit that chose CodeGraph/codebase-memory-mcp/deferred must never pay for this).
#
# After a git commit, refreshes graphify-out/graph.json with the cheap incremental path
# (`graphify update --no-cluster`, see /harness-mem-graphify Step 3 point 4) in the
# background, so the structural index stays close to current without slowing the commit down.
# Never does cluster/label/export/merge here — those stay in /harness-mem-graphify, run
# explicitly or on a periodic external trigger (see that command's "Keeping this fresh
# automatically" section).
#
# Always exits 0 — this is a best-effort refresh, never allowed to block work.

set -u

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" \
  | grep -oE '"command"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"' | head -1 \
  | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//; s/\\"/"/g; s/\\\\/\\/g')
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# Only for a unit that actually bootstrapped and actually chose Graphify.
[ -f ".harness/profile.yaml" ] || exit 0
grep -A2 '^memory:' ".harness/profile.yaml" 2>/dev/null | grep -qi 'graphify' || exit 0

# Only if Graphify is actually installed — never install from a hook.
command -v graphify >/dev/null 2>&1 || exit 0
[ -d "graphify-out" ] && [ -f "graphify-out/graph.json" ] || exit 0

# Background, detached, output discarded — never add commit latency or hook noise.
nohup graphify update . --no-cluster >/dev/null 2>&1 &
disown >/dev/null 2>&1 || true

exit 0
