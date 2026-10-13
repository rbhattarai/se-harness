#!/usr/bin/env bash
# org-validate.sh — PostToolUse hook on Edit/Write (v0).
# Machine-checkable second pass for org conventions (A5 #7, WaveMaker pattern B11):
# warns when an edited file imports a library the org has banned, so the agent
# self-corrects toward internal/preferred libraries (compose-first rule).
#
# v0 rule source: .harness/org-rules.txt — one rule per line, format:
#   banned:<pattern>[:<replacement hint>]
# Example:
#   banned:moment:use dayjs (org standard)
#   banned:lodash:use @acme/utils
# Later phases generate this file from profile.yaml's org: section.
# Exit 0 always (warn, don't block) — blocking on style is too aggressive for v0.

set -u
RULES=".harness/org-rules.txt"
[ -f "$RULES" ] || exit 0

INPUT=$(cat)
# Extract the edited file path from the hook JSON (v0: grep-based).
FILE=$(echo "$INPUT" | grep -oE '"file_path"\s*:\s*"[^"]+"' | head -1 | sed -E 's/.*:\s*"([^"]+)"/\1/')
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

WARNED=0
while IFS= read -r rule; do
  case "$rule" in
    banned:*)
      body="${rule#banned:}"
      pattern="${body%%:*}"
      hint="${body#*:}"; [ "$hint" = "$body" ] && hint=""
      # A pattern ending in a letter/digit names a whole module: `moment` must not also flag
      # `momentum-js`. A pattern ending in - / . _ @ is a deliberate prefix (`@acme/legacy-`).
      boundary=""
      case "$pattern" in *[A-Za-z0-9]) boundary="([\"'/<@]|\$)" ;; esac
      if grep -qE "(import|require|from|using)[^\"']*[\"'<]${pattern}${boundary}" "$FILE" 2>/dev/null; then
        echo "se-harness org rule: '$pattern' is banned by org conventions in $FILE.${hint:+ Hint: $hint}" >&2
        WARNED=1
      fi
      ;;
  esac
done < "$RULES"

# Surface warnings to Claude without failing the edit.
[ "$WARNED" -eq 1 ] && exit 2
exit 0
