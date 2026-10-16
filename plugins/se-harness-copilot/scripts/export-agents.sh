#!/usr/bin/env bash
# export-agents.sh — compile the se-harness agent roster to another client's format (Phase 7).
# agency-agents compiler pattern (B6): one shared frontmatter parser, thin per-client
# converters, deterministic output (no timestamps), clean-before-regenerate.
#
# usage: export-agents.sh <copilot|cursor> [target-root]   (default target-root: .)
#   copilot → <root>/.github/agents/<name>.md   (agent profiles — B10; AGENTS.md/CLAUDE.md
#             are already read natively by Copilot, so instructions need no conversion)
#   cursor  → <root>/.cursor/rules/<name>.mdc   (rule files; no subagent concept — B3 caveat)

set -eu
CLIENT="${1:?usage: export-agents.sh <copilot|cursor> [target-root]}"
ROOT="${2:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Claude plugin: agents/ is a sibling of scripts/. Copilot repo-vendored layout (tools/harness/): agents/ sits beside
# the scripts (/harness-init Step 0a copies it there) and the files are NAME.agent.md.
AGENTS_DIR=""
for cand in "$SCRIPT_DIR/../agents" "$SCRIPT_DIR/agents"; do [ -d "$cand" ] && { AGENTS_DIR="$cand"; break; }; done
[ -n "$AGENTS_DIR" ] || { echo "agents dir not found next to the scripts (looked in ../agents and ./agents)" >&2; exit 1; }

get_field() { awk -v f="$1" '/^---$/{n++; next} n==1 && $0 ~ "^"f": " {sub("^"f": ",""); print; exit}' "$2"; }
get_body()  { awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$1"; }

case "$CLIENT" in
  copilot) OUT="$ROOT/.github/agents"; EXT="md" ;;
  cursor)  OUT="$ROOT/.cursor/rules";  EXT="mdc" ;;
  *) echo "unknown client: $CLIENT (copilot|cursor). codex needs no export — it reads AGENTS.md natively." >&2; exit 1 ;;
esac

mkdir -p "$OUT"
# Clean only files we own (se-harness roster names), so renamed agents leave no orphans.
for f in "$AGENTS_DIR"/*.md; do b=$(basename "${f%.md}"); rm -f "$OUT/${b%.agent}.$EXT"; done

COUNT=0
for f in "$AGENTS_DIR"/*.md; do
  name=$(get_field name "$f"); desc=$(get_field description "$f"); tools=$(get_field tools "$f")
  [ -n "$name" ] || continue
  target="$OUT/$name.$EXT"
  case "$CLIENT" in
    copilot)
      # Copilot agent profile: YAML frontmatter (name, description) + markdown body (≤30k chars).
      # Claude tool names don't map 1:1 — carried as guidance in the body instead of frontmatter.
      {
        printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$name" "$desc"
        [ -n "$tools" ] && printf '> Tool guidance (from Claude Code profile): restrict to %s-equivalents.\n\n' "$tools"
        get_body "$f"
      } > "$target"
      ;;
    cursor)
      # Cursor .mdc rule: description/globs/alwaysApply frontmatter + body. Cursor has no
      # subagent isolation — the rule activates contextually via its description (B3 caveat).
      {
        printf -- '---\ndescription: %s\nglobs: ""\nalwaysApply: false\n---\n\n' "$desc"
        get_body "$f"
      } > "$target"
      ;;
  esac
  COUNT=$((COUNT + 1))
  echo "wrote $target"
done
echo "exported $COUNT agents for $CLIENT"
