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
#
# Phase 8 (§5.4): every row being `done` means each component passed its OWN gate in
# isolation — it does NOT mean the pieces work together. workspace-plan.md's frontmatter also
# carries `integration: pending|passed|failed`, set by the workspace-orchestrator only after
# the combined check actually ran. This gate requires `passed` too, so a feature can never be
# described as complete solely because individual rows finished.

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
N_INCOMPLETE=0
NOT_INTEGRATED=""
for req_file in $APPROVED; do
  req_id=$(basename "$req_file" .md)
  plan="$(dirname "$req_file")/$req_id/workspace-plan.md"
  [ -f "$plan" ] || continue
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    case "$row" in
      *"status: done"*) ;;
      *)
        N_INCOMPLETE=$((N_INCOMPLETE + 1))
        [ "$N_INCOMPLETE" -le 5 ] || continue   # cap: keep the message short for any hook
                                                 # adapter that truncates it (e.g. Copilot's
                                                 # 500-char deny-reason limit) — the count below
                                                 # still reports the true total.
        comp=$(printf '%s' "$row" | sed -E 's/^- component: *([^|]+)\|.*/\1/' | sed 's/[[:space:]]*$//')
        stat=$(printf '%s' "$row" | sed -E 's/.*status: *([^|]+)\|?.*/\1/' | sed 's/[[:space:]]*$//')
        INCOMPLETE="${INCOMPLETE}${req_id}/${comp}=${stat}; "
        ;;
    esac
  done < <(grep '^- component:' "$plan" 2>/dev/null)

  # Phase 8: rows can all be `done` and the combined integration check still not have passed.
  INTEG=$(grep -m1 "^integration:" "$plan" 2>/dev/null | sed -E 's/^integration:[[:space:]]*([^[:space:]]+).*/\1/')
  case "$INTEG" in
    passed) ;;
    *) NOT_INTEGRATED="${NOT_INTEGRATED}${req_id}=${INTEG:-pending}; " ;;
  esac
done

if [ "$N_INCOMPLETE" -gt 0 ]; then
  # Actionable line FIRST — an adapter that truncates the message (e.g. Copilot CLI's deny
  # reason, cut to 500 chars) must not lose the instruction to make room for row detail.
  echo "BLOCKED by se-harness gate: every workspace-plan.md row must reach status: done before push/PR/deploy." >&2
  echo "Not yet done ($N_INCOMPLETE total): ${INCOMPLETE}" >&2
  exit 2
fi

if [ -n "$NOT_INTEGRATED" ]; then
  echo "BLOCKED by se-harness gate: workspace-plan.md's combined integration check hasn't passed yet." >&2
  echo "Every row being done does not mean the pieces work together — see §5.4. Status: ${NOT_INTEGRATED}" >&2
  exit 2
fi

exit 0
