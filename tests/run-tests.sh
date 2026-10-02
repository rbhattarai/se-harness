#!/usr/bin/env bash
# run-tests.sh — repo test suite: manifest integrity, version lockstep, plugin structure,
# generated-variant completeness, script syntax, and open-source hygiene files.
# Runs anywhere bash + python are available (CI: ubuntu-latest; local: Git Bash).
#
# usage: bash tests/run-tests.sh
#   TESTS_COUNT_FILE=<path>  (optional) write the passing-test count to <path> (for CI badge)

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PY=""
for c in python3 python; do
  if "$c" -c "pass" >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -n "$PY" ] || { echo "ERROR: python not found"; exit 2; }

PASS=0; FAIL=0
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $desc"
  fi
}

json_valid() { "$PY" -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$1"; }
json_field() { "$PY" -c "
import json,sys
d=json.load(open(sys.argv[1], encoding='utf-8'))
for k in sys.argv[2].split('.'): d=d[k]
assert isinstance(d,str) and d.strip(), 'empty'
print(d)" "$1" "$2"; }
get_field() { awk -v f="$1" '/^---$/{n++; next} n==1 && $0 ~ "^"f": " {sub("^"f": ",""); print; exit}' "$2"; }

# --- manifests: valid JSON ---
for j in .claude-plugin/marketplace.json .github/plugin/marketplace.json \
         plugins/se-harness/.claude-plugin/plugin.json plugins/se-harness-copilot/plugin.json \
         plugins/se-harness-copilot/hooks.json registry/recommendations.json \
         plugins/se-harness/hooks/hooks.json; do
  [ -f "$j" ] && check "valid JSON: $j" json_valid "$j"
done

# --- manifests: required fields ---
for f in name version description license; do
  check "se-harness plugin.json has $f" json_field plugins/se-harness/.claude-plugin/plugin.json "$f"
  check "se-harness-copilot plugin.json has $f" json_field plugins/se-harness-copilot/plugin.json "$f"
done
check "marketplace.json has name" json_field .claude-plugin/marketplace.json name
check "marketplace.json has metadata.version" json_field .claude-plugin/marketplace.json metadata.version
check "marketplace.json has owner.name" json_field .claude-plugin/marketplace.json owner.name

# --- version lockstep: plugin.json == marketplace == build-script heredoc == copilot variant ---
V_PLUGIN=$(json_field plugins/se-harness/.claude-plugin/plugin.json version 2>/dev/null)
V_MARKET=$(json_field .claude-plugin/marketplace.json metadata.version 2>/dev/null)
V_COPILOT=$(json_field plugins/se-harness-copilot/plugin.json version 2>/dev/null)
V_SCRIPT=$(grep -m1 -oE '"version": "[0-9][0-9a-zA-Z.-]*"' plugins/se-harness/scripts/build-copilot-plugin.sh | grep -oE '[0-9][0-9a-zA-Z.-]*')
check "version lockstep: plugin.json == marketplace metadata.version" test "$V_PLUGIN" = "$V_MARKET"
check "version lockstep: plugin.json == build-script heredoc" test "$V_PLUGIN" = "$V_SCRIPT"
check "version lockstep: plugin.json == generated copilot plugin.json" test "$V_PLUGIN" = "$V_COPILOT"

# --- marketplace mirror is byte-identical to the source of truth ---
check "mirror .github/plugin/marketplace.json matches .claude-plugin/" \
  cmp -s .claude-plugin/marketplace.json .github/plugin/marketplace.json

# --- agents: frontmatter contract (build script depends on name/description) ---
for f in plugins/se-harness/agents/*.md; do
  b=$(basename "$f")
  check "agent $b: frontmatter name" test -n "$(get_field name "$f")"
  check "agent $b: frontmatter description" test -n "$(get_field description "$f")"
done

# --- skills: SKILL.md with description, shared verbatim across ecosystems ---
for d in plugins/se-harness/skills/*/; do
  s=$(basename "$d")
  check "skill $s: SKILL.md exists" test -f "$d/SKILL.md"
  check "skill $s: frontmatter description" test -n "$(get_field description "$d/SKILL.md")"
  check "skill $s: copied into copilot variant" cmp -s "$d/SKILL.md" "plugins/se-harness-copilot/skills/$s/SKILL.md"
done

# --- commands: description frontmatter + generated copilot counterparts ---
for f in plugins/se-harness/commands/*.md; do
  c=$(basename "$f" .md)
  check "command $c: frontmatter description" test -n "$(get_field description "$f")"
  check "command $c: copilot command generated" test -f "plugins/se-harness-copilot/commands/$c.md"
  check "command $c: copilot command-skill generated" test -f "plugins/se-harness-copilot/skills/$c/SKILL.md"
  check "command $c: copilot rewrite left no CLAUDE_PLUGIN_ROOT" \
    bash -c "! grep -q 'CLAUDE_PLUGIN_ROOT' 'plugins/se-harness-copilot/commands/$c.md'"
done

# --- generated agents: one .agent.md per source agent ---
for f in plugins/se-harness/agents/*.md; do
  n=$(get_field name "$f")
  check "agent $n: copilot .agent.md generated" test -f "plugins/se-harness-copilot/agents/$n.agent.md"
done

# --- scripts: bash syntax ---
for f in plugins/se-harness/scripts/*.sh tests/run-tests.sh; do
  check "bash -n: $f" bash -n "$f"
done

# --- workspace-validate.sh: additive schema (phase 1 of the workspace-orchestration plan) ---
WV_FIX=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)

# today's shape (no schemaVersion key) must pass untouched — the backward-compatibility bar
cat > "$WV_FIX/today.yaml" <<'EOF'
workspace:
  name: acme
  topology: multi-repo
  units:
    - { name: frontend, repo: <url>/frontend.git, stack: [angular] }
contracts:
  - name: core-api
    file: docs/api/core-openapi.yaml
    provider: frontend
    consumers: []
EOF
check "workspace-validate: today's shape (no schemaVersion) exits 0" \
  bash plugins/se-harness/scripts/workspace-validate.sh "$WV_FIX/today.yaml"

# a well-formed additive manifest (schemaVersion + components + relationships) passes clean
cat > "$WV_FIX/good.yaml" <<'EOF'
schemaVersion: 2
workspace:
  name: acme
  units:
    - { name: frontend, repo: <url>/frontend.git, stack: [angular] }
    - { name: backend-core, repo: <url>/backend-core.git, stack: [dotnet] }
components:
  - id: storefront-ui
    kind: application
    boundary:
      type: repo
      path: frontend
    role: customer-ui
  - id: cart-api
    kind: service
    boundary:
      type: monorepo-package
      path: backend-core/services/cart-api
    role: backend-service
relationships:
  - from: storefront-ui
    to: cart-api
    type: calls
    evidence: contracts/cart-api.yaml
contracts:
  - name: cart-api
    file: contracts/cart-api.yaml
    provider: cart-api
    consumers: [storefront-ui]
EOF
check "workspace-validate: well-formed additive manifest exits 0" \
  bash plugins/se-harness/scripts/workspace-validate.sh "$WV_FIX/good.yaml"
WV_OUT="$WV_FIX.out"
bash plugins/se-harness/scripts/workspace-validate.sh "$WV_FIX/good.yaml" > "$WV_OUT" 2>&1
check "workspace-validate: well-formed additive manifest reports clean" grep -q "clean" "$WV_OUT"

# violations: bad boundary.type, path outside any unit, missing evidence, unknown component id
cat > "$WV_FIX/bad.yaml" <<'EOF'
schemaVersion: 2
workspace:
  name: acme
  units:
    - { name: frontend, repo: <url>/frontend.git, stack: [angular] }
components:
  - id: ghost-service
    kind: service
    boundary:
      type: made-up-type
      path: nowhere/at/all
    role: backend-service
relationships:
  - from: ghost-service
    to: unknown-id
    type: not-a-real-type
EOF
bash plugins/se-harness/scripts/workspace-validate.sh "$WV_FIX/bad.yaml" > "$WV_OUT" 2>&1
WV_CODE=$?
check "workspace-validate: bad manifest exits 2" test "$WV_CODE" -eq 2
for msg in "not one of repo|monorepo-package|module" "does not resolve inside any declared unit" \
           "is not a declared component id" "missing evidence" "not a recognized relationship type"; do
  check "workspace-validate reports: $msg" grep -qF "$msg" "$WV_OUT"
done
check "workspace-validate: missing file exits 1" \
  bash -c 'bash plugins/se-harness/scripts/workspace-validate.sh "$0" >/dev/null 2>&1; test $? -eq 1' \
  "$WV_FIX/nope.yaml"
rm -rf "$WV_FIX" "$WV_OUT"

# --- contract-check.sh keeps working unchanged against a manifest with the additive keys ---
CC_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/se-harness/scripts/contract-check.sh"
WVG=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
(
  cd "$WVG" && git init -q && git config user.email t@t.co && git config user.name t
  mkdir -p contracts
  cat > workspace.yaml <<'EOF'
schemaVersion: 2
workspace:
  name: acme
  units:
    - { name: frontend, repo: <url>/frontend.git, stack: [angular] }
    - { name: cart-api, repo: <url>/cart-api.git, stack: [dotnet] }
components:
  - id: storefront-ui
    kind: application
    boundary: { type: repo, path: frontend }
    role: customer-ui
relationships: []
contracts:
  - name: cart-api
    file: contracts/cart-api.yaml
    provider: cart-api
    consumers: [frontend]
EOF
  echo "v1" > contracts/cart-api.yaml
  git add -A && git commit -q -m base
) >/dev/null 2>&1
check "contract-check: additive manifest, no contract change, exits 0" \
  bash -c 'cd "$1" && bash "$0" HEAD' "$CC_SCRIPT" "$WVG"
(cd "$WVG" && echo "v2" > contracts/cart-api.yaml && git add -A) >/dev/null 2>&1
(cd "$WVG" && bash "$CC_SCRIPT" HEAD >/dev/null 2>&1); CC_CODE=$?
check "contract-check: additive manifest still flags a real contract change" test "$CC_CODE" -eq 2
rm -rf "$WVG"

# --- privacy invariant: plugins make no network calls (see PRIVACY.md) ---
check "no network calls in plugin scripts" \
  bash -c "! grep -rlE 'curl |wget |Invoke-WebRequest|Invoke-RestMethod' plugins/*/scripts/"

# --- open-source hygiene: files exist and license ships with each plugin ---
for f in LICENSE plugins/se-harness/LICENSE plugins/se-harness-copilot/LICENSE \
         PRIVACY.md CONTRIBUTING.md CODE_OF_CONDUCT.md README.md; do
  check "file exists: $f" test -s "$f"
done
check "hooks.json (copilot) declares version 1" \
  "$PY" -c "import json; assert json.load(open('plugins/se-harness-copilot/hooks.json'))['version'] == 1"

echo "-----------------------------------------"
echo "$PASS passing, $FAIL failing"
[ -n "${TESTS_COUNT_FILE:-}" ] && echo "$PASS" > "$TESTS_COUNT_FILE"
[ "$FAIL" -eq 0 ]
