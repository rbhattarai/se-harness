#!/usr/bin/env bash
# gate-check.sh — PreToolUse hook on Bash (v0).
# HITL gate enforcement (A5 #5): blocks irreversible actions (PR creation, push, deploy)
# while no approved requirement exists in .harness/requirements/.
# Reads the hook JSON on stdin; v0 parses with grep (no jq dependency).
# Exit 2 = block with message to Claude; exit 0 = allow.
#
# Phase 5 (workspace-orchestration plan §5.3): an approved REQ whose impact spanned 2+
# components also gets a REQ-NNN/workspace-plan.md sibling file (see templates/workspace-plan.md
# for the row shape). If one exists, every row must reach `status: done` too — approving the
# requirement is not approving incomplete cross-component work. A REQ with no workspace-plan.md
# (the common single/few-component case, §5.0) is completely unaffected by this.

set -u
INPUT=$(cat)

# Only inspect Bash tool calls whose command looks irreversible.
# Escaped-quote-aware: extract the full command value first (quoted args inside the command
# must not truncate the match), then test it.
CMD=$(printf '%s' "$INPUT" \
  | grep -oE '"command"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"' | head -1 \
  | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//; s/\\"/"/g; s/\\\\/\\/g')
printf '%s' "$CMD" | grep -qE '(gh pr create|git push|docker push|terraform apply|vercel deploy|aws .* deploy|gcloud .* deploy|az .* (deploy|up))' || exit 0

# No harness in this repo → not our business.
[ -d ".harness/requirements" ] || exit 0

APPROVED=$(grep -l "^status: *approved" .harness/requirements/REQ-*.md 2>/dev/null)
if [ -z "$APPROVED" ]; then
  echo "BLOCKED by se-harness gate: no requirement in .harness/requirements/ has status: approved." >&2
  echo "Present the refined requirement to the user and get explicit approval (HITL gate) first." >&2
  exit 2
fi

INCOMPLETE=""
for req_file in $APPROVED; do
  req_id=$(basename "$req_file" .md)
  plan="$(dirname "$req_file")/$req_id/workspace-plan.md"
  [ -f "$plan" ] || continue
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    case "$row" in
      *"status: done"*) ;;
      *) INCOMPLETE="${INCOMPLETE}${req_id}: ${row}"$'\n' ;;
    esac
  done < <(grep '^- component:' "$plan" 2>/dev/null)
done

if [ -n "$INCOMPLETE" ]; then
  echo "BLOCKED by se-harness gate: workspace-plan.md has rows that are not status: done yet:" >&2
  printf '%s' "$INCOMPLETE" >&2
  echo "Every component row must reach status: done before push/PR/deploy for this requirement." >&2
  exit 2
fi

exit 0
