#!/usr/bin/env bash
# build-copilot-plugin.sh — generate the Copilot CLI plugin variant (plugins/se-harness-copilot)
# from the Claude-first se-harness plugin. B6 compiler pattern: shared source, thin per-platform
# converter, deterministic output, clean-before-regenerate. Commit the output — Copilot installs
# it from this repo via `copilot plugin install se-harness-copilot@<marketplace>`.
#
# Per docs/copilot/platform-notes.md:
#   agents  → NAME.agent.md (tools field dropped; carried as body guidance)
#   skills  → SKILL.md standard is shared; copied verbatim; PLUS each command is also emitted
#             as a skill directory (Copilot commands are skill-shaped — user-verified)
#   commands→ copied with ${CLAUDE_PLUGIN_ROOT}/scripts/ rewritten to tools/harness/ (repo-vendored)
#   hooks   → bundled hooks.json with plugin-root-relative ./scripts/ paths (user-verified:
#             plugin hooks.json paths resolve against the plugin root); repo-level
#             .github/hooks/ via templates/copilot-hooks.json remains supported too
#   mcp     → not bundled (guide covers MCP per-surface)
#
# usage: build-copilot-plugin.sh   (no args; paths derived from repo layout)

set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/.."                      # plugins/se-harness
OUT="$SCRIPT_DIR/../../se-harness-copilot"  # plugins/se-harness-copilot

get_field() { awk -v f="$1" '/^---$/{n++; next} n==1 && $0 ~ "^"f": " {sub("^"f": ",""); print; exit}' "$2"; }
get_body()  { awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$1"; }

rm -rf "$OUT"
mkdir -p "$OUT/agents" "$OUT/skills" "$OUT/commands" "$OUT/scripts"

# --- plugin.json (Copilot schema; name required, kebab, <=64 chars) ---
cat > "$OUT/plugin.json" <<'EOF'
{
  "name": "se-harness-copilot",
  "description": "SE Harness for GitHub Copilot CLI: SDLC agent roster, harness skills, goal-loop commands, and bundled enforcement hooks. Generated from the Claude-first se-harness plugin - do not edit by hand; regenerate with build-copilot-plugin.sh. Repo-level hooks for the coding agent/VS Code - see docs/setup-guide-copilot.md.",
  "version": "0.1.1",
  "author": { "name": "Rohan Bhattarai", "email": "rohan.bhattarai.dev@gmail.com" },
  "repository": "https://github.com/rbhattarai/software-engineering-ai-agents-bootstrap",
  "license": "MIT",
  "keywords": ["sdlc", "agents", "harness", "bootstrap", "hitl", "memory"],
  "agents": "./agents",
  "skills": "./skills",
  "commands": "./commands",
  "hooks": "./hooks.json"
}
EOF

# --- hooks.json: Copilot version-1 schema, plugin-root-relative script paths ---
cat > "$OUT/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "type": "command",
        "bash": "bash ./scripts/copilot-hook-adapter.sh pre ./scripts/gate-check.sh",
        "powershell": "bash ./scripts/copilot-hook-adapter.sh pre ./scripts/gate-check.sh",
        "timeoutSec": 15
      },
      {
        "type": "command",
        "bash": "bash ./scripts/copilot-hook-adapter.sh pre ./scripts/contract-check.sh",
        "powershell": "bash ./scripts/copilot-hook-adapter.sh pre ./scripts/contract-check.sh",
        "timeoutSec": 15
      }
    ],
    "postToolUse": [
      {
        "type": "command",
        "bash": "bash ./scripts/copilot-hook-adapter.sh post ./scripts/org-validate.sh",
        "powershell": "bash ./scripts/copilot-hook-adapter.sh post ./scripts/org-validate.sh",
        "timeoutSec": 10
      },
      {
        "type": "command",
        "bash": "bash ./scripts/copilot-hook-adapter.sh post ./scripts/memory-log-commit.sh",
        "powershell": "bash ./scripts/copilot-hook-adapter.sh post ./scripts/memory-log-commit.sh",
        "timeoutSec": 10
      }
    ]
  }
}
EOF

# --- agents: *.md -> NAME.agent.md, tools -> body guidance ---
COUNT_A=0
for f in "$SRC"/agents/*.md; do
  name=$(get_field name "$f"); desc=$(get_field description "$f"); tools=$(get_field tools "$f")
  [ -n "$name" ] || continue
  {
    printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$name" "$desc"
    [ -n "$tools" ] && printf '> Tool guidance (from the Claude Code profile): restrict yourself to %s-equivalents.\n\n' "$tools"
    get_body "$f"
  } > "$OUT/agents/$name.agent.md"
  COUNT_A=$((COUNT_A + 1))
done

# --- skills: shared SKILL.md standard, verbatim copy ---
COUNT_S=0
for d in "$SRC"/skills/*/; do
  sname=$(basename "$d")
  mkdir -p "$OUT/skills/$sname"
  cp -R "$d"/. "$OUT/skills/$sname/"
  COUNT_S=$((COUNT_S + 1))
done

# --- commands: rewrite plugin-root paths for the Copilot context ---
#   scripts   → tools/harness/           (repo-vendored per setup guide 4.7)
#   templates → ../se-harness/templates/ (framework repo cloned as sibling per guide Part 2)
#   registry  → ../se-harness/registry/
COUNT_C=0
for f in "$SRC"/commands/*.md; do
  cname=$(basename "$f")
  sed -e 's|\${CLAUDE_PLUGIN_ROOT}/scripts/|tools/harness/|g' \
      -e 's|\${CLAUDE_PLUGIN_ROOT}/\.\./\.\./templates/|../se-harness/templates/|g' \
      -e 's|\${CLAUDE_PLUGIN_ROOT}/\.\./\.\./registry/|../se-harness/registry/|g' \
      "$f" > "$OUT/commands/$cname"

  # Also emit as a skill directory (Copilot commands are skill-shaped: SKILL.md registered
  # into the skill registry, invoked `copilot <name> ...` — user-verified). The command file
  # already has Claude command frontmatter (description, argument-hint); rebuild it as skill
  # frontmatter (name + description) over the same rewritten body.
  cmdname="${cname%.md}"
  desc=$(get_field description "$f")
  mkdir -p "$OUT/skills/$cmdname"
  {
    printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$cmdname" "$desc"
    get_body "$OUT/commands/$cname"
  } > "$OUT/skills/$cmdname/SKILL.md"

  COUNT_C=$((COUNT_C + 1))
done

# --- license: ship the repo LICENSE with the generated plugin ---
[ -f "$SRC/LICENSE" ] && cp "$SRC/LICENSE" "$OUT/LICENSE"

# --- scripts: bundled for reference + easy vendoring (commands expect them at tools/harness/) ---
cp "$SRC"/scripts/*.sh "$OUT/scripts/"
cat > "$OUT/scripts/README.md" <<'EOF'
Vendor these into each repo the harness manages (commands reference `tools/harness/`):

    mkdir -p tools/harness && cp <plugin-dir>/scripts/*.sh tools/harness/

Enforcement hooks install at repo level: copy `templates/copilot-hooks.json` from the
framework repo to `.github/hooks/se-harness.json` (see docs/setup-guide-copilot.md 4.7).
EOF

# --- marketplace mirror: Copilot's canonical location (.github/plugin/) ---
# Single source of truth stays .claude-plugin/marketplace.json (read by BOTH ecosystems);
# this mirror exists for orgs whose tooling expects the .github/plugin/ location.
# Regenerated on every build so it can never drift.
REPO_ROOT="$SCRIPT_DIR/../../.."
if [ -f "$REPO_ROOT/.claude-plugin/marketplace.json" ]; then
  mkdir -p "$REPO_ROOT/.github/plugin"
  cp "$REPO_ROOT/.claude-plugin/marketplace.json" "$REPO_ROOT/.github/plugin/marketplace.json"
  echo "mirrored marketplace.json -> .github/plugin/ (Copilot canonical location)"
fi

echo "built $OUT: $COUNT_A agents, $COUNT_S skills + $COUNT_C command-skills, $COUNT_C commands"
