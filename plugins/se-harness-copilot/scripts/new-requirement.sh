#!/usr/bin/env bash
# new-requirement.sh — scaffold the next .harness/requirements/REQ-NNN.md from the template.
# Deterministic mechanics for /harness-goal step 3; the LLM fills the content afterwards.
#
# usage: new-requirement.sh "<goal text>"
# prints the created file path on stdout.

set -eu
GOAL="${1:?usage: new-requirement.sh \"<goal text>\"}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Locate templates: the plugin's own dir (marketplace install / repo checkout), an explicit
# override, or the sibling framework clone Copilot setups use (tools/harness/ -> ../se-harness).
TPL_DIR=""
for cand in "${SE_HARNESS_TEMPLATES:-}" "$SCRIPT_DIR/../templates" "$SCRIPT_DIR/../../../se-harness/plugins/se-harness/templates"; do
  [ -n "$cand" ] && [ -d "$cand" ] && { TPL_DIR="$cand"; break; }
done
TEMPLATE="$TPL_DIR/requirement.md"
[ -n "$TPL_DIR" ] && [ -f "$TEMPLATE" ] || { echo "template not found (looked next to the plugin; set SE_HARNESS_TEMPLATES to override)" >&2; exit 1; }

REQ_DIR=".harness/requirements"
mkdir -p "$REQ_DIR"

# Next 3-digit id from the highest existing REQ-NNN (files or dirs).
LAST=$(ls -d "$REQ_DIR"/REQ-* 2>/dev/null | sed -E 's/.*REQ-([0-9]+).*/\1/' | sort -n | tail -1)
NEXT=$(printf '%03d' $(( ${LAST:-0} + 1 )))
FILE="$REQ_DIR/REQ-$NEXT.md"
[ ! -e "$FILE" ] || { echo "collision: $FILE already exists" >&2; exit 1; }

TODAY=$(date +%Y-%m-%d)
# awk substitution — goal text may contain slashes/quotes, so no sed delimiters.
awk -v id="REQ-$NEXT" -v today="$TODAY" -v goal="$GOAL" '
  BEGIN { gsub(/\\/, "\\\\", goal); gsub(/"/, "\\\"", goal) }   # YAML-safe double-quoted string
  { gsub(/REQ-000/, id); gsub(/YYYY-MM-DD/, today) }
  /^goal:/ { printf "goal: \"%s\"\n", goal; next }
  { print }
' "$TEMPLATE" > "$FILE"

mkdir -p "$REQ_DIR/REQ-$NEXT"   # artifact dir: design.md, story.md, test-cases.md, e2e-plan.md
echo "$FILE"
