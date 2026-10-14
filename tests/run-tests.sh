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
         plugins/se-harness-copilot/hooks.json plugins/se-harness/registry/recommendations.json \
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

# --- wiki-lint.sh: functional checks on fixture wikis ---
WL_FIX=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
WL_OUT="$WL_FIX.out"
printf '# Index\n\n- [payments](payments.md) — x\n- [ghost](ghost.md) — x\n' > "$WL_FIX/index.md"
printf '# Log\n' > "$WL_FIX/log.md"
printf '# Payments\n\nSee [[refunds]].\n\n## CONTRADICTION here\n\nsources: X, ingested 2026-07-15\n' > "$WL_FIX/payments.md"
i=0; while [ "$i" -lt 160 ]; do echo "filler $i" >> "$WL_FIX/payments.md"; i=$((i + 1)); done
printf '# Refunds\n' > "$WL_FIX/refunds.md"
printf '# Lonely\n\nsources: Y, ingested 2026-07-10\n' > "$WL_FIX/lonely.md"
printf '# Secrets\n\npassword = "hunter2-value"\n\nsources: Z, ingested 2026-07-12\n' > "$WL_FIX/secrets.md"
bash plugins/se-harness/scripts/wiki-lint.sh "$WL_FIX" > "$WL_OUT" 2>&1
WL_CODE=$?
check "wiki-lint exits 1 on findings" test "$WL_CODE" -eq 1
for tag in MISSING-FROM-INDEX DANGLING-INDEX-LINK ORPHAN NO-SOURCES CONTRADICTION OVERSIZE SECRET-HIT; do
  check "wiki-lint reports $tag" grep -q "$tag" "$WL_OUT"
done
check "wiki-lint never echoes secret content" bash -c "! grep -q hunter2 $WL_OUT"
WL_CLEAN=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
printf '# Index\n\n- [a](a.md) — x\n- [b](b.md) — x\n' > "$WL_CLEAN/index.md"
printf '# Log\n' > "$WL_CLEAN/log.md"
printf '# A\n\nSee [[b]].\n\nsources: X, ingested 2026-07-15\n' > "$WL_CLEAN/a.md"
printf '# B\n\nSee [[a]].\n\nsources: Y, ingested 2026-07-15\n' > "$WL_CLEAN/b.md"
bash plugins/se-harness/scripts/wiki-lint.sh "$WL_CLEAN" > "$WL_OUT" 2>&1
WL_CODE=$?
check "wiki-lint exits 0 when clean" test "$WL_CODE" -eq 0
check "wiki-lint reports clean" grep -q "wiki-lint: clean" "$WL_OUT"
check "wiki-lint exits 2 on missing dir" \
  bash -c 'bash plugins/se-harness/scripts/wiki-lint.sh "$0" >/dev/null 2>&1; test $? -eq 2' "$WL_FIX/nope"
rm -rf "$WL_FIX" "$WL_CLEAN" "$WL_OUT"

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

# shared.methodology (phase 3) — checked regardless of schemaVersion
cat > "$WV_FIX/method-ok.yaml" <<'EOF'
workspace:
  name: acme
  shared:
    methodology: openspec
    org: {}
EOF
check "workspace-validate: valid shared.methodology, no schemaVersion, exits 0" \
  bash plugins/se-harness/scripts/workspace-validate.sh "$WV_FIX/method-ok.yaml"

cat > "$WV_FIX/method-bad.yaml" <<'EOF'
workspace:
  name: acme
  shared:
    methodology: scrum-of-scrums
EOF
bash plugins/se-harness/scripts/workspace-validate.sh "$WV_FIX/method-bad.yaml" > "$WV_OUT" 2>&1
WV_METHOD_CODE=$?
check "workspace-validate: invalid shared.methodology exits 2" test "$WV_METHOD_CODE" -eq 2
check "workspace-validate: invalid shared.methodology is reported" \
  grep -qF "shared.methodology 'scrum-of-scrums' is not one of" "$WV_OUT"
for m in se-harness openspec spec-kit bmad; do
  printf 'workspace:\n  name: acme\n  shared:\n    methodology: %s\n' "$m" > "$WV_FIX/method-$m.yaml"
  check "workspace-validate: shared.methodology '$m' is accepted" \
    bash plugins/se-harness/scripts/workspace-validate.sh "$WV_FIX/method-$m.yaml"
done
check "init offers all four methodology choices, including se-harness (built-in)" \
  bash -c "f=plugins/se-harness/commands/harness-init.md; grep -q 'se-harness (built-in)' \$f && grep -q 'OpenSpec' \$f && grep -q 'Spec Kit' \$f && grep -q 'BMAD' \$f && grep -q 'methodology: se-harness' \$f"
check "registry: methodologies are se-harness (native), openspec, spec-kit and bmad" \
  "$PY" -c "
import json
m = json.load(open('plugins/se-harness/registry/recommendations.json', encoding='utf-8'))['methodologies']
assert m['se-harness']['kind'] == 'native' and 'none' not in m
assert {'se-harness', 'openspec', 'spec-kit', 'bmad'} <= set(m)"

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

# --- workspace-clone.sh: opt-in, confirmed, never-overwrite repo acquisition (phase 2) ---
WC_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/se-harness/scripts/workspace-clone.sh"
WC_FIX=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
git init -q --bare "$WC_FIX/remote-a.git" >/dev/null 2>&1
mkdir -p "$WC_FIX/ws"
git clone -q "$WC_FIX/remote-a.git" "$WC_FIX/seed" >/dev/null 2>&1
STORED_URL=$(git -C "$WC_FIX/seed" remote get-url origin)
rm -rf "$WC_FIX/seed"
printf '# comment, then a blank line\n\nservice-a=%s\n' "$STORED_URL" > "$WC_FIX/repos.txt"

WC_OUT="$WC_FIX.out"
bash "$WC_SCRIPT" plan "$WC_FIX/repos.txt" "$WC_FIX/ws" > "$WC_OUT" 2>&1
check "workspace-clone: plan exits 0" test $? -eq 0
check "workspace-clone: plan reports missing before any clone" grep -q "service-a  *missing" "$WC_OUT"
check "workspace-clone: plan never touches disk" bash -c "[ ! -e '$WC_FIX/ws/service-a' ]"

bash "$WC_SCRIPT" apply "$WC_FIX/repos.txt" "$WC_FIX/ws" > "$WC_OUT" 2>&1
check "workspace-clone: apply (missing) exits 0" test $? -eq 0
check "workspace-clone: apply actually cloned the repo" test -d "$WC_FIX/ws/service-a/.git"

bash "$WC_SCRIPT" plan "$WC_FIX/repos.txt" "$WC_FIX/ws" > "$WC_OUT" 2>&1
check "workspace-clone: plan reports matches after clone" grep -q "service-a  *matches" "$WC_OUT"

bash "$WC_SCRIPT" apply "$WC_FIX/repos.txt" "$WC_FIX/ws" > "$WC_OUT" 2>&1
check "workspace-clone: re-apply on a matching clone exits 0 (no-op)" test $? -eq 0
check "workspace-clone: re-apply reports already-present, not a re-clone" grep -q "already present" "$WC_OUT"

mkdir -p "$WC_FIX/ws2/service-a" && echo unrelated > "$WC_FIX/ws2/service-a/file.txt"
bash "$WC_SCRIPT" apply "$WC_FIX/repos.txt" "$WC_FIX/ws2" > "$WC_OUT" 2>&1
WC_CODE=$?
check "workspace-clone: collision exits 2" test "$WC_CODE" -eq 2
check "workspace-clone: collision is reported, never touched" test -f "$WC_FIX/ws2/service-a/file.txt"
check "workspace-clone: collision content is untouched" grep -qF unrelated "$WC_FIX/ws2/service-a/file.txt"

check "workspace-clone: missing inventory file exits 1" \
  bash -c "bash '$WC_SCRIPT' plan '$WC_FIX/nope.txt' '$WC_FIX/ws' >/dev/null 2>&1; test \$? -eq 1"
rm -rf "$WC_FIX" "$WC_OUT"

# --- gate-check.sh: HITL gate + phase 5's workspace-plan.md row check ---
GC_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/se-harness/scripts/gate-check.sh"
GC_FIX=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
gc_payload() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }

(cd "$GC_FIX" && gc_payload "git push origin main" | bash "$GC_SCRIPT") >/dev/null 2>&1
check "gate-check: no .harness dir at all — allowed" test $? -eq 0

mkdir -p "$GC_FIX/.harness/requirements"
(cd "$GC_FIX" && gc_payload "git push origin main" | bash "$GC_SCRIPT") >/dev/null 2>&1
check "gate-check: harness dir, zero requirements — blocked" test $? -eq 2

(cd "$GC_FIX" && gc_payload "ls -la" | bash "$GC_SCRIPT") >/dev/null 2>&1
check "gate-check: non-irreversible command — always allowed" test $? -eq 0

cat > "$GC_FIX/.harness/requirements/REQ-001.md" <<'EOF'
---
id: REQ-001
status: draft
---
EOF
(cd "$GC_FIX" && gc_payload "git push origin main" | bash "$GC_SCRIPT") >/dev/null 2>&1
check "gate-check: REQ exists but draft — blocked" test $? -eq 2

sed -i 's/status: draft/status: approved/' "$GC_FIX/.harness/requirements/REQ-001.md" 2>/dev/null \
  || sed -i '' 's/status: draft/status: approved/' "$GC_FIX/.harness/requirements/REQ-001.md"
(cd "$GC_FIX" && gc_payload "git push origin main" | bash "$GC_SCRIPT") >/dev/null 2>&1
check "gate-check: REQ approved, no workspace-plan.md — allowed (unchanged behavior)" test $? -eq 0

mkdir -p "$GC_FIX/.harness/requirements/REQ-001"
cat > "$GC_FIX/.harness/requirements/REQ-001/workspace-plan.md" <<'EOF'
---
req: REQ-001
integration: passed
---
- component: frontend | status: pending | owner: implementer-frontend | outcome: UI done | depends_on: cart-api | evidence: -
- component: cart-api | status: done | owner: implementer-backend | outcome: API done | depends_on: - | evidence: -
EOF
GC_OUT="$GC_FIX.out"
(cd "$GC_FIX" && gc_payload "gh pr create --title x" | bash "$GC_SCRIPT") > "$GC_OUT" 2>&1
GC_CODE=$?
check "gate-check: approved REQ, a pending workspace-plan row — blocked" test "$GC_CODE" -eq 2
check "gate-check: blocked message names the pending component" grep -qF "frontend=pending" "$GC_OUT"
check "gate-check: blocked message leads with the actionable instruction" \
  bash -c "head -1 '$GC_OUT' | grep -qF 'must reach status: done'"

sed -i 's/status: pending/status: done/' "$GC_FIX/.harness/requirements/REQ-001/workspace-plan.md" 2>/dev/null \
  || sed -i '' 's/status: pending/status: done/' "$GC_FIX/.harness/requirements/REQ-001/workspace-plan.md"
(cd "$GC_FIX" && gc_payload "gh pr create --title x" | bash "$GC_SCRIPT") >/dev/null 2>&1
check "gate-check: all workspace-plan rows done — allowed" test $? -eq 0

# phase 7: many incomplete rows must still produce a short, actionable message — the Copilot
# hook adapter truncates a deny reason to 500 chars, so the instruction can't depend on a row
# dump that might get cut off first.
for i in 1 2 3 4 5 6 7 8; do
  echo "- component: svc$i | status: pending | owner: x | outcome: x | depends_on: - | evidence: -" \
    >> "$GC_FIX/.harness/requirements/REQ-001/workspace-plan.md"
done
(cd "$GC_FIX" && gc_payload "git push" | bash "$GC_SCRIPT") > "$GC_OUT" 2>&1
check "gate-check: many incomplete rows still exits 2" test $? -eq 2
check "gate-check: many incomplete rows reports the true total count" grep -qF "(8 total)" "$GC_OUT"
check "gate-check: many incomplete rows message stays well under 500 chars" \
  bash -c "[ \$(wc -c < '$GC_OUT') -lt 500 ]"

# phase 8: all rows done is not enough — the combined integration check must also have passed
rm -rf "$GC_FIX/.harness/requirements/REQ-001" "$GC_FIX/.harness/requirements/REQ-001.md"
mkdir -p "$GC_FIX/.harness/requirements/REQ-002"
cat > "$GC_FIX/.harness/requirements/REQ-002.md" <<'EOF'
---
id: REQ-002
status: approved
---
EOF
cat > "$GC_FIX/.harness/requirements/REQ-002/workspace-plan.md" <<'EOF'
---
req: REQ-002
integration: pending
---
- component: frontend | status: done | owner: a | outcome: x | depends_on: - | evidence: -
- component: cart-api | status: done | owner: b | outcome: x | depends_on: - | evidence: -
EOF
(cd "$GC_FIX" && gc_payload "git push" | bash "$GC_SCRIPT") > "$GC_OUT" 2>&1
check "gate-check: all rows done but integration: pending — blocked" test $? -eq 2
check "gate-check: integration-pending message cites §5.4" grep -qF "does not mean the pieces work together" "$GC_OUT"

sed -i 's/integration: pending/integration: failed/' "$GC_FIX/.harness/requirements/REQ-002/workspace-plan.md" 2>/dev/null \
  || sed -i '' 's/integration: pending/integration: failed/' "$GC_FIX/.harness/requirements/REQ-002/workspace-plan.md"
(cd "$GC_FIX" && gc_payload "git push" | bash "$GC_SCRIPT") >/dev/null 2>&1
check "gate-check: integration: failed — blocked" test $? -eq 2

sed -i 's/integration: failed/integration: passed/' "$GC_FIX/.harness/requirements/REQ-002/workspace-plan.md" 2>/dev/null \
  || sed -i '' 's/integration: failed/integration: passed/' "$GC_FIX/.harness/requirements/REQ-002/workspace-plan.md"
(cd "$GC_FIX" && gc_payload "git push" | bash "$GC_SCRIPT") >/dev/null 2>&1
check "gate-check: integration: passed, all rows done — allowed" test $? -eq 0

# a workspace-plan.md with no integration: field at all (pre-phase-8 shape) defaults to not
# passed, never to an implicit pass
cat > "$GC_FIX/.harness/requirements/REQ-002/workspace-plan.md" <<'EOF'
- component: frontend | status: done | owner: a | outcome: x | depends_on: - | evidence: -
EOF
(cd "$GC_FIX" && gc_payload "git push" | bash "$GC_SCRIPT") >/dev/null 2>&1
check "gate-check: missing integration: field defaults to blocked, not an implicit pass" test $? -eq 2
rm -rf "$GC_FIX" "$GC_OUT"

# --- workspace-scan-evidence.sh: §10, full workspace-root scan collector ---
WSE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/se-harness/scripts/workspace-scan-evidence.sh"
WSE_FIX=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
WSE_OUT="$WSE_FIX.out"

# mono-repo: path: form with a NESTED path — must resolve to the nested dir, not <name>
cat > "$WSE_FIX/workspace.yaml" <<'EOF'
workspace:
  name: acme
  units:
    - name: example-service
      path: services/example
      stack: []
EOF
mkdir -p "$WSE_FIX/services/example/.harness"
echo 'project: {}' > "$WSE_FIX/services/example/.harness/profile.yaml"
echo '{"name":"example"}' > "$WSE_FIX/services/example/package.json"
bash "$WSE_SCRIPT" "$WSE_FIX" > "$WSE_OUT" 2>&1
check "workspace-scan-evidence: mono-repo exits 0" test $? -eq 0
check "workspace-scan-evidence: resolves nested path:, not just the unit name" \
  grep -qF "UNIT: example-service ($WSE_FIX/services/example)" "$WSE_OUT"
check "workspace-scan-evidence: scans the bootstrapped unit's real manifest" grep -qF '"name":"example"' "$WSE_OUT"

# multi-repo: repo: form (flow style), mixed readiness — one scanned, one not-bootstrapped,
# one not-cloned at all
cat > "$WSE_FIX/workspace.yaml" <<'EOF'
workspace:
  name: acme
  units:
    - { name: frontend, repo: <url>/frontend.git, stack: [angular] }
    - { name: backend-core, repo: <url>/backend-core.git, stack: [dotnet] }
    - { name: not-cloned, repo: <url>/not-cloned.git, stack: [] }
EOF
mkdir -p "$WSE_FIX/frontend/.harness" "$WSE_FIX/backend-core"
echo 'project: {}' > "$WSE_FIX/frontend/.harness/profile.yaml"
bash "$WSE_SCRIPT" "$WSE_FIX" > "$WSE_OUT" 2>&1
check "workspace-scan-evidence: multi-repo exits 0" test $? -eq 0
check "workspace-scan-evidence: reports NOT-BOOTSTRAPPED for a cloned-but-uninitialized unit" \
  grep -qF "NOT-BOOTSTRAPPED" "$WSE_OUT"
check "workspace-scan-evidence: reports NOT-CLONED for a missing unit" grep -qF "NOT-CLONED" "$WSE_OUT"
check "workspace-scan-evidence: summary counts scanned/skipped correctly" \
  grep -qF "scanned: 1, skipped: 2" "$WSE_OUT"

# undeclared directory: already bootstrapped but not in workspace.yaml — must be proposed,
# never silently adopted; node_modules-style noise must never be flagged
mkdir -p "$WSE_FIX/mystery-service/.harness" "$WSE_FIX/node_modules"
echo 'project: {}' > "$WSE_FIX/mystery-service/.harness/profile.yaml"
bash "$WSE_SCRIPT" "$WSE_FIX" > "$WSE_OUT" 2>&1
check "workspace-scan-evidence: flags an undeclared bootstrapped directory" grep -qF "UNDECLARED" "$WSE_OUT"
check "workspace-scan-evidence: never flags node_modules as undeclared" \
  bash -c "! grep -q 'UNDECLARED.*node_modules' '$WSE_OUT'"
rm -rf "$WSE_FIX/mystery-service" "$WSE_FIX/node_modules"

# no workspace.yaml and no repos.txt — usage error, not a silent "nothing to do"
EMPTY_FIX=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
bash "$WSE_SCRIPT" "$EMPTY_FIX" >/dev/null 2>&1
check "workspace-scan-evidence: no manifest at all exits 1" test $? -eq 1
rm -rf "$EMPTY_FIX" "$WSE_FIX" "$WSE_OUT"

# --- render-block.sh: hash baseline + hand-edit detection (upgrade safety) ---
RB="plugins/se-harness/scripts/render-block.sh"
RB_FIX=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
printf 'gen-a
gen-b
' > "$RB_FIX/v1"; printf 'gen-new
gen-b
' > "$RB_FIX/v2"
bash "$RB" "$RB_FIX/T.md" "$RB_FIX/v1" >/dev/null
check "render-block: created block records a sha baseline" grep -qE 'SEAA:GENERATED:END sha=[0-9a-f]{16}' "$RB_FIX/T.md"
check "render-block: --check reports clean after render" test "$(bash "$RB" --check "$RB_FIX/T.md")" = clean
echo "my hand-written note" >> "$RB_FIX/T.md"
bash "$RB" "$RB_FIX/T.md" "$RB_FIX/v2" >/dev/null
check "render-block: untouched block is replaced" grep -q gen-new "$RB_FIX/T.md"
check "render-block: text outside the markers survives a re-render" grep -q "my hand-written note" "$RB_FIX/T.md"
sed -i 's/^gen-b$/HAND-EDITED/' "$RB_FIX/T.md"
check "render-block: --check reports modified after an in-block edit" test "$(bash "$RB" --check "$RB_FIX/T.md")" = modified
bash "$RB" "$RB_FIX/T.md" "$RB_FIX/v1" >/dev/null 2>&1
check "render-block: hand-edited block exits 3 (conflict)" test $? -eq 3
check "render-block: conflict leaves the edited block untouched" grep -q HAND-EDITED "$RB_FIX/T.md"
check "render-block: conflict writes a .seaa.proposed file" test -s "$RB_FIX/T.md.seaa.proposed"
bash "$RB" --force "$RB_FIX/T.md" "$RB_FIX/v1" >/dev/null 2>&1
check "render-block: --force overwrites the edited block" bash -c "! grep -q HAND-EDITED '$RB_FIX/T.md'"
check "render-block: --force saves the edited block to .seaa.bak" grep -q HAND-EDITED "$RB_FIX/T.md.seaa.bak"
printf '<!-- SEAA:GENERATED:START -->
old
<!-- SEAA:GENERATED:END -->
mine
' > "$RB_FIX/L.md"
check "render-block: pre-baseline block is reported legacy" test "$(bash "$RB" --check "$RB_FIX/L.md")" = legacy
bash "$RB" "$RB_FIX/L.md" "$RB_FIX/v1" >/dev/null 2>&1
check "render-block: legacy block is replaced and gains a baseline" grep -qE 'END sha=[0-9a-f]{16}' "$RB_FIX/L.md"
check "render-block: --check on a missing file reports missing" test "$(bash "$RB" --check "$RB_FIX/none.md")" = missing
rm -rf "$RB_FIX"

# --- version stamps documented in the commands that write/read the lockfile ---
check "harness-init writes schema_version into the lockfile" grep -q 'schema_version: 1' plugins/se-harness/commands/harness-init.md
check "harness-sync checks version stamps (Step 0b)" grep -q 'Step 0b' plugins/se-harness/commands/harness-sync.md
for c in harness-init harness-bootstrap harness-scan harness-sync; do
  check "$c handles render-block conflict exit (--force only after asking)" grep -q 'seaa.proposed' plugins/se-harness/commands/$c.md
done

# --- migrate.sh: schema migration chain (upgrade without losing project changes) ---
MG="plugins/se-harness/scripts/migrate.sh"
MFX="tests/fixtures/migrate"
mg_fresh() { rm -rf "$1"; cp -r "$MFX/v1-project" "$1"; }
MG_TMP=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)

# real plugin today: schema 1, no migrations — a v1 project is simply "up to date" + baseline stamp
mg_fresh "$MG_TMP/p"
check "migrate: real chain reports up to date at schema 1" bash -c "bash '$MG' --status '$MG_TMP/p' | grep -q 'up to date'"
bash "$MG" "$MG_TMP/p" >/dev/null 2>&1
check "migrate: up-to-date run stamps schema_version 1 into a legacy lockfile" grep -q '"schema_version": 1' "$MG_TMP/p/.harness/agentstack.lock"
check "migrate: baseline stamp keeps the lockfile valid JSON" json_valid "$MG_TMP/p/.harness/agentstack.lock"
check "migrate: no backup created when there is nothing to migrate" test ! -d "$MG_TMP/p/.harness/backup"

# 1 -> 3 chain
mg_fresh "$MG_TMP/p"
export HARNESS_MIGRATIONS_DIR="$PWD/$MFX/migrations-ok"
check "migrate: --dry-run lists the pending chain" bash -c "bash '$MG' --dry-run '$MG_TMP/p' | grep -q '1-to-2: fixture step'"
check "migrate: --dry-run changes nothing" bash -c "! grep -q schema_version '$MG_TMP/p/.harness/agentstack.lock'"
bash "$MG" "$MG_TMP/p" >/dev/null 2>&1
check "migrate: chain runs 1->2->3 (both markers created)" test -f "$MG_TMP/p/.harness/v2.marker" -a -f "$MG_TMP/p/.harness/v3.marker"
check "migrate: lockfile ends at schema_version 3" grep -q '"schema_version": 3' "$MG_TMP/p/.harness/agentstack.lock"
check "migrate: lockfile keeps its other fields" grep -q '"se_harness": "1.0.0"' "$MG_TMP/p/.harness/agentstack.lock"
check "migrate: lockfile stays valid JSON" json_valid "$MG_TMP/p/.harness/agentstack.lock"
check "migrate: history appended to migrations.log" test "$(wc -l < "$MG_TMP/p/.harness/migrations.log" | tr -d ' ')" = 2
check "migrate: backup tarball written" test -s "$(ls -d "$MG_TMP"/p/.harness/backup/*/ | head -1)files.tar"
check "migrate: user memory survives" grep -q 'USER-NOTE: we deploy on Fridays' "$MG_TMP/p/.harness/memory/MEMORY.md"
check "migrate: user requirement survives" grep -q 'user-written requirement' "$MG_TMP/p/.harness/requirements/REQ-001.md"
check "migrate: hand-written AGENTS.md text survives" grep -q 'HAND-WRITTEN: never use ORM X' "$MG_TMP/p/AGENTS.md"
check "migrate: generated block was re-rendered by the migration" grep -q 'v2 generated text' "$MG_TMP/p/AGENTS.md"
bash "$MG" "$MG_TMP/p" >/dev/null 2>&1
check "migrate: re-running is a no-op (idempotent)" test "$(wc -l < "$MG_TMP/p/.harness/migrations.log" | tr -d ' ')" = 2

# failure mid-chain rolls the WHOLE run back
mg_fresh "$MG_TMP/p"
export HARNESS_MIGRATIONS_DIR="$PWD/$MFX/migrations-fail"
bash "$MG" "$MG_TMP/p" >/dev/null 2>&1
check "migrate: failing step exits 1" test $? -eq 1
check "migrate: rollback restores memory the failed step clobbered" grep -q 'USER-NOTE' "$MG_TMP/p/.harness/memory/MEMORY.md"
check "migrate: rollback removes files the run created" test ! -e "$MG_TMP/p/.harness/v2.marker" -a ! -e "$MG_TMP/p/.harness/v3.marker"
check "migrate: rollback restores the earlier-step block change" grep -q 'v1 generated text' "$MG_TMP/p/AGENTS.md"
check "migrate: rollback leaves schema_version unset" bash -c "! grep -q schema_version '$MG_TMP/p/.harness/agentstack.lock'"

# hand-edited generated block: conflict, rolled back, then --force-blocks takes it
mg_fresh "$MG_TMP/p"
export HARNESS_MIGRATIONS_DIR="$PWD/$MFX/migrations-ok"
printf 'v1 generated text
' > "$MG_TMP/v1blk"
bash plugins/se-harness/scripts/render-block.sh "$MG_TMP/p/AGENTS.md" "$MG_TMP/v1blk" >/dev/null
sed -i 's/^v1 generated text$/MY EDIT INSIDE BLOCK/' "$MG_TMP/p/AGENTS.md"
bash "$MG" "$MG_TMP/p" >/dev/null 2>&1
check "migrate: hand-edited block exits 3" test $? -eq 3
check "migrate: conflict leaves the edit and the schema untouched" bash -c "grep -q 'MY EDIT INSIDE BLOCK' '$MG_TMP/p/AGENTS.md' && ! grep -q schema_version '$MG_TMP/p/.harness/agentstack.lock'"
bash "$MG" --force-blocks "$MG_TMP/p" >/dev/null 2>&1
check "migrate: --force-blocks completes the migration" grep -q '"schema_version": 3' "$MG_TMP/p/.harness/agentstack.lock"
check "migrate: --force-blocks keeps the edit in a .seaa.bak" grep -q 'MY EDIT INSIDE BLOCK' "$MG_TMP/p/AGENTS.md.seaa.bak"

# guards
mg_fresh "$MG_TMP/p"
export HARNESS_MIGRATIONS_DIR="$PWD/$MFX/migrations-gap"
bash "$MG" "$MG_TMP/p" >/dev/null 2>&1
check "migrate: a gap in the chain exits 1 before changing anything" test $? -eq 1
export HARNESS_MIGRATIONS_DIR="$PWD/$MFX/migrations-ok"
sed -i 's/"se_harness"/"schema_version": 9, "se_harness"/' "$MG_TMP/p/.harness/agentstack.lock"
bash "$MG" "$MG_TMP/p" >/dev/null 2>&1
check "migrate: project newer than plugin exits 2" test $? -eq 2
mg_fresh "$MG_TMP/p"
mkdir -p "$MG_TMP/empty"
bash "$MG" "$MG_TMP/empty" >/dev/null 2>&1
check "migrate: un-bootstrapped dir exits 2" test $? -eq 2
if command -v git >/dev/null 2>&1; then
  ( cd "$MG_TMP/p" && git init -q . && git add -A 2>/dev/null && git -c user.email=t@t -c user.name=t commit -qm base 2>/dev/null && echo dirty >> AGENTS.md )
  bash "$MG" "$MG_TMP/p" >/dev/null 2>&1
  check "migrate: uncommitted harness files are refused (exit 2)" test $? -eq 2
  bash "$MG" --allow-dirty "$MG_TMP/p" >/dev/null 2>&1
  check "migrate: --allow-dirty overrides the guard" grep -q '"schema_version": 3' "$MG_TMP/p/.harness/agentstack.lock"
fi
unset HARNESS_MIGRATIONS_DIR
rm -rf "$MG_TMP"
check "migrations dir ships a contract README" test -s plugins/se-harness/scripts/migrations/README.md
check "harness-update plumbing: migrate.sh is shipped in the copilot build" test -f plugins/se-harness-copilot/scripts/migrate.sh

# --- /harness-update: wrapper wiring (marketplace first, GitHub fallback, migrate, re-entrant) ---
HU=plugins/se-harness/commands/harness-update.md
check "harness-update: tries the marketplace refresh first" grep -q 'claude plugin marketplace update se-harness' "$HU"
check "harness-update: falls back to the GitHub repo's plugin.json" grep -q 'raw.githubusercontent.com/rbhattarai/se-harness' "$HU"
check "harness-update: installs via claude plugin update at the project's scope" grep -q 'claude plugin update se-harness@se-harness --scope' "$HU"
check "harness-update: is re-entrant (restart, then run again)" grep -qi 'restart' "$HU"
check "harness-update: migrates through migrate.sh" grep -q 'scripts/migrate.sh' "$HU"
check "harness-update: hands off to /harness-sync" grep -q '/harness-sync' "$HU"
check "harness-update: never auto-confirms (-y/--force/--accept-command)" grep -q 'accept-command' "$HU"
check "harness-update: supports --check" grep -q 'argument-hint: \[--check\]' "$HU"
check "harness-update: shipped migrate.sh is the one it references" test -f plugins/se-harness/scripts/migrate.sh

# --- doc-extract.sh: any-format NAS docs, readiness gate, scanned-PDF flag ---
DX="plugins/se-harness/scripts/doc-extract.sh"
DXR="plugins/se-harness/scripts/doc-registry"
# real registry integrity: every referenced extractor is defined, every row well-formed
dx_registry_ok() {
  local ids x
  ids=$(awk -F'\t' '!/^#/ && NF {print $1}' "$DXR/extractors.tsv")
  for x in $(awk -F'\t' '!/^#/ && NF && $2 != "image" {print $3}' "$DXR/formats.tsv" | tr ',' '\n' | sort -u); do
    echo "$ids" | grep -qx "$x" || { echo "undefined extractor: $x"; return 1; }
  done
}
check "doc-registry: every formats.tsv extractor id exists in extractors.tsv" dx_registry_ok
dx_cols() { [ -z "$(awk -F'\t' -v n="$2" '!/^#/ && NF && NF!=n' "$1")" ]; }
check "doc-registry: formats rows have exactly 3 columns" dx_cols "$DXR/formats.tsv" 3
check "doc-registry: extractors rows have exactly 5 columns" dx_cols "$DXR/extractors.tsv" 5
for e in pdf doc docx ppt pptx xls xlsx txt md; do
  check "doc-registry: supports .$e" awk -F'\t' -v e="$e" '$1==e {f=1} END {exit !f}' "$DXR/formats.tsv"
done
dx_narrow() {
  local c; c=$(bash "$DX" --install-cmd markitdown)
  case "$c" in *'markitdown[pdf,docx,pptx,xlsx,xls,outlook]'*) ;; *) return 1 ;; esac
  case "$c" in *'[all]'*) return 1 ;; esac
}
check "doc-registry: MarkItDown install uses narrow extras, not [all]" dx_narrow

# behavior, against a throwaway registry whose tool readiness we control
DX_T=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
mkdir -p "$DX_T/reg" "$DX_T/extra" "$DX_T/tree/sub/deep" "$DX_T/tree/@eaDir"
printf 'md\ttext\tnative\ndocx\toffice\tfake\npdf\tdocument\tfake\nxlsx\toffice\tnever\npng\timage\t-\n' > "$DX_T/reg/formats.tsv"
printf 'native\ttrue\tcat {in}\t-\tplain\nfake\ttest -f "$DX_T/tool"\ttr a-z A-Z < {in}\tINSTALL-FAKE-TOOL\tfake\nnever\tfalse\tcat {in}\tINSTALL-NEVER\tnever ready\n' > "$DX_T/reg/extractors.tsv"
export DOC_REGISTRY_DIR="$DX_T/reg" DX_T
echo "hello docs" > "$DX_T/tree/a.md"; echo "word text" > "$DX_T/tree/b.docx"; echo "deep" > "$DX_T/tree/sub/deep/c.DOCX"
echo x > "$DX_T/tree/pic.png"; echo x > "$DX_T/tree/odd.xyz"; echo x > "$DX_T/tree/sheet.xlsx"
echo x > "$DX_T/tree/~\$b.docx"; echo x > "$DX_T/tree/Thumbs.db"; echo x > "$DX_T/tree/@eaDir/t.docx"
TAB=$(printf '\t')
dx_has() { bash "$DX" --inventory "$@" 2>/dev/null | grep -q "$DX_PAT"; }
DX_PAT="FORMAT${TAB}docx${TAB}2${TAB}[0-9]*${TAB}missing${TAB}fake";           check "doc-extract: unready tool → missing + recommended extractor, recursive, case-insensitive" dx_has "$DX_T/tree"
DX_PAT="JUNK${TAB}2";                                                           check "doc-extract: lock/Thumbs/@eaDir junk dropped and counted" dx_has "$DX_T/tree"
DX_PAT="FORMAT${TAB}md${TAB}1${TAB}[0-9]*${TAB}ready${TAB}native";              check "doc-extract: native format is ready with no install" dx_has "$DX_T/tree"
DX_PAT="FORMAT${TAB}xyz${TAB}1${TAB}[0-9]*${TAB}unsupported";                   check "doc-extract: unknown extension reported unsupported" dx_has "$DX_T/tree"
DX_PAT="FORMAT${TAB}png${TAB}1${TAB}[0-9]*${TAB}flagged-ocr${TAB}-";            check "doc-extract: images flagged for OCR, no extractor offered" dx_has "$DX_T/tree"
DX_PAT="FORMAT${TAB}docx${TAB}2${TAB}[0-9]*${TAB}declined";                     check "doc-extract: --skip-ext marks a declined format" dx_has --skip-ext docx "$DX_T/tree"
DX_PAT="MISSING_PATH";                                                          check "doc-extract: a missing directory is reported, not silently empty" dx_has "$DX_T/nope"
check "doc-extract: --install-cmd prints the registry's install text" test "$(bash "$DX" --install-cmd fake)" = INSTALL-FAKE-TOOL

bash "$DX" --extract "$DX_T/tree/b.docx" >/dev/null 2>&1; check "doc-extract: extract with tool missing exits 4" test $? -eq 4
dx_msg() { bash "$DX" --extract "$DX_T/tree/b.docx" 2>&1 | grep -q INSTALL-FAKE-TOOL; }
check "doc-extract: exit-4 message names the install text" dx_msg
touch "$DX_T/tool"
DX_PAT="FORMAT${TAB}docx${TAB}2${TAB}[0-9]*${TAB}ready${TAB}fake";              check "doc-extract: once the tool exists the format becomes ready" dx_has "$DX_T/tree"
check "doc-extract: extract returns the extractor's text" test "$(bash "$DX" --extract "$DX_T/tree/b.docx")" = "WORD TEXT"
bash "$DX" --extract "$DX_T/tree/odd.xyz" >/dev/null 2>&1; check "doc-extract: unsupported extension exits 5" test $? -eq 5
bash "$DX" --extract "$DX_T/tree/pic.png" >/dev/null 2>&1; check "doc-extract: image exits 7 (flagged, not ingested)" test $? -eq 7
bash "$DX" --extract "$DX_T/tree/sheet.xlsx" >/dev/null 2>&1; check "doc-extract: extractor that is never ready exits 4" test $? -eq 4
bash "$DX" --extract "$DX_T/tree/b.docx" --max-bytes 3 >/dev/null 2>&1; check "doc-extract: over --max-bytes exits 8" test $? -eq 8
printf 'abcdefghij\n' > "$DX_T/tree/long.md"
dx_trunc() { bash "$DX" --extract "$DX_T/tree/long.md" --max-chars 4 | grep -q 'truncated at 4 of'; }
check "doc-extract: --max-chars truncates with a marker" dx_trunc
# scanned PDF: big file, ~no extractable text -> 7 ; text PDF -> 0
head -c 200000 /dev/zero | tr '\0' '1' > "$DX_T/tree/scan.pdf"
printf 'fake\ttest -f "$DX_T/tool"\ttr -cd "a-zA-Z \\n" < {in}\tINSTALL-FAKE-TOOL\tfake\nnever\tfalse\tcat {in}\tINSTALL-NEVER\tnever ready\nnative\ttrue\tcat {in}\t-\tplain\n' > "$DX_T/reg/extractors.tsv"
bash "$DX" --extract "$DX_T/tree/scan.pdf" >/dev/null 2>&1; check "doc-extract: scanned PDF (no letters in 200KB) exits 7" test $? -eq 7
printf 'The quarterly report describes loan origination and the underwriting rules in detail for all products.\n' > "$DX_T/tree/text.pdf"
bash "$DX" --extract "$DX_T/tree/text.pdf" >/dev/null 2>&1; check "doc-extract: text PDF extracts fine (exit 0)" test $? -eq 0
# failing extractor -> 6 (a bad file never aborts a run)
printf 'docx\toffice\tbroken\n' > "$DX_T/extra/formats.tsv"
printf 'broken\ttrue\tfalse {in}\tINSTALL-BROKEN\tfails\n' > "$DX_T/extra/extractors.tsv"
bash "$DX" --extract "$DX_T/tree/b.docx" --registry-extra "$DX_T/extra" >/dev/null 2>&1; check "doc-extract: failing extractor exits 6" test $? -eq 6
# --registry-extra adds a brand-new format with the user's own converter
printf 'abc\tcustom\tmine\n' > "$DX_T/extra/formats.tsv"
printf 'mine\ttrue\ttr a-z A-Z < {in}\t-\tuser converter\n' > "$DX_T/extra/extractors.tsv"
echo "custom fmt" > "$DX_T/tree/x.abc"
DX_PAT="FORMAT${TAB}abc${TAB}1${TAB}[0-9]*${TAB}ready${TAB}mine";               check "doc-extract: --registry-extra makes a new format ready" dx_has --registry-extra "$DX_T/extra" "$DX_T/tree"
check "doc-extract: user converter output is used" test "$(bash "$DX" --extract "$DX_T/tree/x.abc" --registry-extra "$DX_T/extra")" = "CUSTOM FMT"
echo "spaced" > "$DX_T/tree/we ird 'name'.md"
check "doc-extract: awkward file names are quoted safely" test "$(bash "$DX" --extract "$DX_T/tree/we ird 'name'.md")" = spaced
rm -rf "$DX_T"
unset DOC_REGISTRY_DIR DX_T DX_PAT
DX_CR=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
printf 'md\ttext\tnative\r\n' > "$DX_CR/formats.tsv"
printf 'native\ttrue\tcat {in}\t-\tplain\r\n' > "$DX_CR/extractors.tsv"
echo crlf-ok > "$DX_CR/t.md"
check "doc-extract: CRLF-terminated registry rows still resolve" test "$(DOC_REGISTRY_DIR=$DX_CR bash "$DX" --extract "$DX_CR/t.md")" = crlf-ok
rm -rf "$DX_CR"

# command wiring
MW=plugins/se-harness/commands/harness-mem-wiki.md
check "harness-mem-wiki: drives doc-extract.sh" grep -q 'scripts/doc-extract.sh' "$MW"
check "harness-mem-wiki: no longer limited to PDF/Office" bash -c "! grep -q 'Fingerprint each PDF/Office' $MW"
check "harness-mem-wiki: skipping a format ignores only that extension" grep -q 'only that extension' "$MW"
check "harness-mem-wiki: records format decisions in the manifest" grep -q 'formats: {<ext>' "$MW"
check "harness-mem-wiki: flags scanned PDFs/images, no OCR install offered" grep -q 'OCR is out of scope' "$MW"
check "harness-mem-wiki: supports user-supplied converters" grep -q 'registry-extra' "$MW"

# --- plugin is self-contained: a marketplace install copies ONLY plugins/se-harness/ ---
# (regression: templates/ and registry/ used to live at the repo root, so installed copies of
#  template-hash.sh / new-requirement.sh failed and ${CLAUDE_PLUGIN_ROOT}/../../ paths dangled)
check "plugin ships templates/ and registry/ inside its own directory" \
  test -f plugins/se-harness/templates/AGENTS.md.tmpl -a -f plugins/se-harness/registry/recommendations.json
check "no repo-root templates/ or registry/ left behind" test ! -e templates -a ! -e registry
check "no \${CLAUDE_PLUGIN_ROOT}/../ escape in commands/skills/agents/hooks/scripts" \
  bash -c "! grep -rF '\${CLAUDE_PLUGIN_ROOT}/../' plugins/se-harness --include=*.md --include=*.json --include=*.sh | grep -v 'build-copilot-plugin.sh'"
cpr_paths_exist() {
  local bad=0 p rel
  while IFS= read -r p; do
    rel="${p#\$\{CLAUDE_PLUGIN_ROOT\}/}"; rel="${rel%[.,;:)\`]}"; rel="${rel%/}"
    [ -z "$rel" ] && continue
    [ -e "plugins/se-harness/$rel" ] || { echo "dangling: $p"; bad=1; }
  done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' plugins/se-harness/commands plugins/se-harness/skills plugins/se-harness/agents 2>/dev/null | sort -u)
  return $bad
}
check "every \${CLAUDE_PLUGIN_ROOT}/<path> the commands name exists inside the plugin" cpr_paths_exist
INST_T=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
cp -r plugins/se-harness "$INST_T/installed"
mkdir -p "$INST_T/proj"
check "installed-copy: template-hash.sh works without the repo around it" \
  bash -c "cd '$INST_T/proj' && bash '$INST_T/installed/scripts/template-hash.sh' | grep -q 'AGENTS.md.tmpl'"
check "installed-copy: new-requirement.sh finds its template" \
  bash -c "cd '$INST_T/proj' && bash '$INST_T/installed/scripts/new-requirement.sh' 'smoke goal' | grep -q 'REQ-001'"
check "installed-copy: SE_HARNESS_TEMPLATES override is honored" \
  bash -c "mv '$INST_T/installed/templates' '$INST_T/elsewhere' && cd '$INST_T/proj' && SE_HARNESS_TEMPLATES='$INST_T/elsewhere' bash '$INST_T/installed/scripts/template-hash.sh' | grep -q 'AGENTS.md.tmpl'"
check "installed-copy: a missing templates dir is a clear error, not a crash" \
  bash -c "cd '$INST_T/proj' && ! bash '$INST_T/installed/scripts/template-hash.sh' 2>&1 | grep -q 'AGENTS.md.tmpl'"
rm -rf "$INST_T"
check "copilot commands point templates at the sibling framework clone's plugin dir" \
  bash -c "grep -rq '../se-harness/plugins/se-harness/templates/' plugins/se-harness-copilot/commands"

# --- observability as a recorded decision: decision-review.sh + the contract the commands rely on ---
DR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/se-harness/scripts/decision-review.sh"
DR_FIX=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
# dr_get <dir> <topic> <field#>: 2=status 3=value 4=decided 5=detail
dr_get() { bash "$DR_SCRIPT" "$1" | awk -F'\t' -v t="$2" -v n="$3" '$1 == t { print $n }'; }

mkdir -p "$DR_FIX/none/.harness"
printf 'methodology: openspec\n' > "$DR_FIX/none/.harness/profile.yaml"
check "decision-review: a project with no observability block reads as unset (asked on the next sync)" \
  test "$(dr_get "$DR_FIX/none" observability 2)" = "unset"

mkdir -p "$DR_FIX/lf/.harness"
cat > "$DR_FIX/lf/.harness/profile.yaml" <<'EOF'
methodology: openspec
observability:
  status: configured
  provider: langfuse        # comment must not leak into the value
  host: "http://localhost:3000"
  decided: 2026-10-13
EOF
printf 'LANGFUSE_PUBLIC_KEY=pk-lf-secret-value\nLANGFUSE_SECRET_KEY=\n' > "$DR_FIX/lf/.env.harness"
check "decision-review: configured Langfuse is reported as provider @ host" \
  test "$(dr_get "$DR_FIX/lf" observability 3)" = "langfuse @ http://localhost:3000"
check "decision-review: configured decision carries its date" \
  test "$(dr_get "$DR_FIX/lf" observability 4)" = "2026-10-13"
check "decision-review: reports a missing secret by NAME, with the per-surface caveat" \
  bash -c "case \"\$(bash '$DR_SCRIPT' '$DR_FIX/lf' | awk -F'\t' '\$1==\"observability\"{print \$5}')\" in *'.env.harness: missing LANGFUSE_SECRET_KEY'*'Copilot'*'keychain'*) exit 0;; *) exit 1;; esac"
check "decision-review: never prints a secret value" \
  bash -c "! bash '$DR_SCRIPT' '$DR_FIX/lf' | grep -q 'pk-lf-secret-value'"
printf 'LANGFUSE_PUBLIC_KEY=a\nLANGFUSE_SECRET_KEY=b\n' > "$DR_FIX/lf/.env.harness"
check "decision-review: both keys present -> env ok" \
  test "$(dr_get "$DR_FIX/lf" observability 5)" = ".env.harness: ok"

mkdir -p "$DR_FIX/ws/unit/.harness"
cat > "$DR_FIX/ws/workspace.yaml" <<'EOF'
workspace:
  name: demo
  shared:
    methodology: openspec
    observability:
      status: configured
      provider: langfuse
      host: http://localhost:3000
      decided: 2026-10-13
EOF
printf 'project: {}\n' > "$DR_FIX/ws/unit/.harness/profile.yaml"
check "decision-review: a unit inherits the workspace's shared.observability" \
  test "$(dr_get "$DR_FIX/ws/unit" observability 3)" = "langfuse @ http://localhost:3000"
check "decision-review: a unit inherits the workspace methodology" \
  test "$(dr_get "$DR_FIX/ws/unit" methodology 3)" = "openspec"

mkdir -p "$DR_FIX/def/.harness"
printf 'observability:\n  status: deferred\n' > "$DR_FIX/def/.harness/profile.yaml"
check "decision-review: deferred is reported as deferred" \
  test "$(dr_get "$DR_FIX/def" observability 2)" = "deferred"
printf 'observability:\n  status: declined\n  decided: 2026-10-01\n' > "$DR_FIX/def/.harness/profile.yaml"
check "decision-review: declined is distinct from deferred" \
  test "$(dr_get "$DR_FIX/def" observability 2)" = "declined"
check "decision-review: declined carries its date" \
  test "$(dr_get "$DR_FIX/def" observability 4)" = "2026-10-01"
printf 'observability:\n  status: maybe\n' > "$DR_FIX/def/.harness/profile.yaml"
check "decision-review: an unknown status is flagged invalid, not silently accepted" \
  test "$(dr_get "$DR_FIX/def" observability 2)" = "invalid(maybe)"
printf 'observability:\n  status: configured\n' > "$DR_FIX/def/.harness/profile.yaml"
check "decision-review: configured without a provider is flagged invalid" \
  test "$(dr_get "$DR_FIX/def" observability 2)" = "invalid(configured-without-provider)"
check "decision-review: a null structural driver is reported as deferred, a set one as configured" \
  bash -c "test \"\$(printf 'memory:\n  structural_driver: null\n' > '$DR_FIX/def/.harness/profile.yaml'; bash '$DR_SCRIPT' '$DR_FIX/def' | awk -F'\t' '\$1==\"memory\"{print \$2}')\" = deferred && test \"\$(printf 'memory:\n  structural_driver: Graphify\n' > '$DR_FIX/def/.harness/profile.yaml'; bash '$DR_SCRIPT' '$DR_FIX/def' | awk -F'\t' '\$1==\"memory\"{print \$2}')\" = configured"
mkdir -p "$DR_FIX/sg/.harness"
printf 'memory:\n  structural_driver: sourcegraph\n  sourcegraph:\n    url: "https://sg.example.com"\n    auth: token\n' > "$DR_FIX/sg/.harness/profile.yaml"
check "decision-review: sourcegraph shows its instance URL" \
  bash -c "dr='$DR_SCRIPT'; bash \"\$dr\" '$DR_FIX/sg' | awk -F'\t' '\$1==\"memory\"{print \$3}' | grep -qx 'sourcegraph @ https://sg.example.com'"
check "decision-review: token auth with no token variable is flagged" \
  bash -c "bash '$DR_SCRIPT' '$DR_FIX/sg' | awk -F'\t' '\$1==\"memory\"{print \$5}' | grep -q 'missing SOURCEGRAPH_ACCESS_TOKEN'"
printf 'SOURCEGRAPH_ACCESS_TOKEN=x\n' > "$DR_FIX/sg/.env.harness"
check "decision-review: token auth with the variable set is not flagged" \
  bash -c "! bash '$DR_SCRIPT' '$DR_FIX/sg' | awk -F'\t' '\$1==\"memory\"{print \$5}' | grep -q 'missing'"
rm -f "$DR_FIX/sg/.env.harness"
printf 'memory:\n  structural_driver: sourcegraph\n  sourcegraph:\n    url: "https://sg.example.com"\n    auth: oauth\n' > "$DR_FIX/sg/.harness/profile.yaml"
check "decision-review: OAuth never asks for a token variable" \
  bash -c "! bash '$DR_SCRIPT' '$DR_FIX/sg' | awk -F'\t' '\$1==\"memory\"{print \$5}' | grep -q 'missing'"
printf 'memory:\n  structural_driver: sourcegraph\n' > "$DR_FIX/sg/.harness/profile.yaml"
check "decision-review: sourcegraph without a URL is flagged" \
  bash -c "bash '$DR_SCRIPT' '$DR_FIX/sg' | awk -F'\t' '\$1==\"memory\"{print \$5}' | grep -q 'url not set'"
check "registry: Sourcegraph is a structural-memory choice and its note covers Cloud, self-hosted and token auth" \
  bash -c "grep -q 'Sourcegraph (sourcegraph/sourcegraph' plugins/se-harness/registry/recommendations.json && grep -q 'self-hosted' plugins/se-harness/registry/recommendations.json && grep -q 'SOURCEGRAPH_ACCESS_TOKEN' plugins/se-harness/registry/recommendations.json"
check "templates carry memory.sourcegraph (profile + workspace) and only the token variable NAME" \
  bash -c "grep -q 'sourcegraph:' plugins/se-harness/templates/profile.yaml && grep -q 'sourcegraph:' plugins/se-harness/templates/workspace.yaml && grep -qx 'SOURCEGRAPH_ACCESS_TOKEN=' plugins/se-harness/templates/env.harness.example && grep -q 'Authorization.*token \${SOURCEGRAPH_ACCESS_TOKEN}' plugins/se-harness/templates/mcp.json.tmpl"
check "mcp.json.tmpl is valid JSON and registers codebase-memory with no serve arg and codegraph with the impact tools enabled"   bash -c "python -c \"import json,sys; d=json.load(open('plugins/se-harness/templates/mcp.json.tmpl'))['mcpServers']; assert d['codebase-memory']['args']==[]; assert 'impact' in d['codegraph']['env']['CODEGRAPH_MCP_TOOLS']; assert d['sourcegraph']['type']=='http'\" 2>/dev/null || python3 -c \"import json; d=json.load(open('plugins/se-harness/templates/mcp.json.tmpl'))['mcpServers']; assert d['codebase-memory']['args']==[]; assert 'impact' in d['codegraph']['env']['CODEGRAPH_MCP_TOOLS']; assert d['sourcegraph']['type']=='http'\""
check "every structural-memory driver has a lifecycle command that confirms before installing"   bash -c "for c in codebase-memory codegraph sourcegraph graphify; do test -f plugins/se-harness/commands/harness-mem-\$c.md || exit 1; done; grep -qi 'confirm\|ask' plugins/se-harness/commands/harness-mem-codebase-memory.md && grep -qi 'telemetry' plugins/se-harness/commands/harness-mem-codegraph.md"
rm -rf "$DR_FIX"

check "profile template carries the observability decision block" \
  bash -c "grep -q '^observability:' plugins/se-harness/templates/profile.yaml && grep -q 'status: unset' plugins/se-harness/templates/profile.yaml"
check "workspace template carries shared.observability" \
  bash -c "grep -q '^    observability:' plugins/se-harness/templates/workspace.yaml"
check "workspace env template names the Langfuse keys (values empty)" \
  bash -c "grep -qx 'LANGFUSE_PUBLIC_KEY=' plugins/se-harness/templates/env.harness.workspace.example && grep -qx 'LANGFUSE_SECRET_KEY=' plugins/se-harness/templates/env.harness.workspace.example"
check "registry: every observability provider declares a kind; per-surface ones have claude and copilot" \
  "$PY" -c "
import json
o = json.load(open('plugins/se-harness/registry/recommendations.json', encoding='utf-8'))['observability']
for n, p in o['providers'].items():
    assert p['kind'] in ('plugin', 'manual', 'per-surface'), n
    if p['kind'] == 'per-surface':
        assert {'claude', 'copilot'} <= set(p['surfaces']), n
assert {'langfuse', 'dash0', 'other'} <= set(o['providers'])"
check "registry: Langfuse for Claude Code = the real marketplace + plugin, keys kept out of .env.harness" \
  "$PY" -c "
import json
p = json.load(open('plugins/se-harness/registry/recommendations.json', encoding='utf-8'))['observability']['providers']['langfuse']
c = p['surfaces']['claude']
assert p['verified'] is True and p['host_default'] == 'http://localhost:3000' and p['health_path']
assert c['marketplace'] == 'langfuse/Claude-Observability-Plugin'
assert c['plugin'] == 'langfuse-observability@langfuse-observability'
assert 'LANGFUSE_BASE_URL' in c['config_keys'] and 'LANGFUSE_HOST' not in c['config_keys']
assert c['keys_in_env_harness'] is False"
check "registry: Langfuse for Copilot is OTLP env config (no plugin), keys come from .env.harness" \
  "$PY" -c "
import json
c = json.load(open('plugins/se-harness/registry/recommendations.json', encoding='utf-8'))['observability']['providers']['langfuse']['surfaces']['copilot']
assert c['kind'] == 'otel-env' and 'plugin' not in c and c['otlp_path'] == '/api/public/otel'
assert c['env']['COPILOT_OTEL_ENABLED'] == 'true' and c['keys_in_env_harness'] is True
assert 'OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT' in c['optional'] and 'OPT-IN' in c['optional']['OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT']"
check "bootstrap documents --reconfigure for observability, memory and methodology" \
  bash -c "f=plugins/se-harness/commands/harness-bootstrap.md; grep -q -- '--reconfigure' \$f && grep -q 'Reconfigure mode' \$f && grep -q 'Observability setup' \$f && grep -q 'deferred' \$f"
check "sync re-asks deferred decisions and points at --reconfigure" \
  bash -c "f=plugins/se-harness/commands/harness-sync.md; grep -q 'decision-review.sh' \$f && grep -q -- '--reconfigure observability' \$f"
check "copilot variant carries decision-review.sh and the reconfigure docs" \
  bash -c "test -f plugins/se-harness-copilot/scripts/decision-review.sh && grep -q -- '--reconfigure' plugins/se-harness-copilot/commands/harness-bootstrap.md"

check "registry: Dash0 for Claude Code = official-marketplace plugin, user scope, token kept out of .env.harness"   "$PY" -c "
import json
p = json.load(open('plugins/se-harness/registry/recommendations.json', encoding='utf-8'))['observability']['providers']['dash0']
c = p['surfaces']['claude']
assert p['kind'] == 'per-surface' and p['verified'] is True
assert c['plugin'] == 'dash0@claude-plugins-official' and '--scope user' in c['install'][0]
assert c['keys_in_env_harness'] is False and 'AUTH_TOKEN' in c['config_keys'] and 'OTLP_URL' in c['config_keys']
assert 'worktree' in c['scope_note'] and 'twice' in c['alt_identity']
assert p['surfaces']['copilot']['kind'] == 'manual'"
check "bootstrap documents the Dash0 flow (official marketplace, one identity, keychain token)"   bash -c "f=plugins/se-harness/commands/harness-bootstrap.md; grep -q 'dash0@claude-plugins-official' \$f && grep -q 'dash0-agent-plugin@dash0' \$f && grep -q 'ingest-only' \$f && ! grep -q 'unverified plugin name' \$f"
DR_D=$(mktemp -d 2>/dev/null || mktemp -d -t seharness); mkdir -p "$DR_D/.harness"
printf 'observability:
  status: configured
  provider: dash0
  host: "https://ingress.eu-west-1.aws.dash0.com"
' > "$DR_D/.harness/profile.yaml"
check "decision-review: Dash0 says its token lives in the plugin, not .env.harness"   bash -c "bash '$DR_SCRIPT' '$DR_D' | awk -F'\t' '\$1==\"observability\"{print \$5}' | grep -q 'keychain/config'"
rm -rf "$DR_D"

# --- langfuse-otel-env.sh: Copilot CLI -> Langfuse via native OpenTelemetry (no plugin exists) ---
OT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/se-harness/scripts/langfuse-otel-env.sh"
OT_FIX=$(mktemp -d 2>/dev/null || mktemp -d -t seharness)
mkdir -p "$OT_FIX/.harness"
printf 'observability:\n  status: configured\n  provider: langfuse\n  host: "http://localhost:3000/"\n' > "$OT_FIX/.harness/profile.yaml"
printf "LANGFUSE_PUBLIC_KEY=pk-lf-aaa\nLANGFUSE_SECRET_KEY='sk-lf-bbb'\n" > "$OT_FIX/.env.harness"
OT_AUTH=$(printf '%s' 'pk-lf-aaa:sk-lf-bbb' | base64 | tr -d '\n')
ot_out() { (cd "$OT_FIX" && bash "$OT_SCRIPT" "$@" 2>/dev/null); }
check "otel-env: endpoint is the recorded host + /api/public/otel (trailing slash tolerated)" \
  bash -c "cd '$OT_FIX' && bash '$OT_SCRIPT' 2>/dev/null | grep -qx \"export OTEL_EXPORTER_OTLP_ENDPOINT='http://localhost:3000/api/public/otel'\""
check "otel-env: header is Basic base64(public:secret) plus the ingestion-version flag" \
  bash -c "cd '$OT_FIX' && bash '$OT_SCRIPT' 2>/dev/null | grep -qx \"export OTEL_EXPORTER_OTLP_HEADERS='Authorization=Basic $OT_AUTH,x-langfuse-ingestion-version=4'\""
check "otel-env: enables Copilot's exporter" \
  bash -c "cd '$OT_FIX' && bash '$OT_SCRIPT' 2>/dev/null | grep -qx 'export COPILOT_OTEL_ENABLED=true'"
check "otel-env: content capture is OFF unless asked for" \
  bash -c "cd '$OT_FIX' && ! bash '$OT_SCRIPT' 2>/dev/null | grep -q CAPTURE_MESSAGE_CONTENT"
check "otel-env: --capture-content opts in" \
  bash -c "cd '$OT_FIX' && bash '$OT_SCRIPT' --capture-content 2>/dev/null | grep -qx 'export OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true'"
check "otel-env: --host overrides the recorded host" \
  bash -c "cd '$OT_FIX' && bash '$OT_SCRIPT' --host https://langfuse.internal 2>/dev/null | grep -q \"ENDPOINT='https://langfuse.internal/api/public/otel'\""
check "otel-env: the secret never appears in clear text on stdout or stderr" \
  bash -c "cd '$OT_FIX' && ! bash '$OT_SCRIPT' --capture-content 2>&1 | grep -q 'sk-lf-bbb'"
check "otel-env: the output is eval-safe (sets exactly the documented variables)" \
  bash -c "cd '$OT_FIX' && eval \"\$(bash '$OT_SCRIPT' 2>/dev/null)\" && test \"\$COPILOT_OTEL_ENABLED\" = true && test \"\$OTEL_EXPORTER_OTLP_ENDPOINT\" = http://localhost:3000/api/public/otel"
rm -f "$OT_FIX/.env.harness"
check "otel-env: missing keys -> exit 1 and NOTHING on stdout (a failed eval is a no-op)" \
  bash -c "cd '$OT_FIX' && out=\$(bash '$OT_SCRIPT' 2>/dev/null); rc=\$?; test \$rc -eq 1 && test -z \"\$out\""
check "otel-env: keys already in the environment are honored" \
  bash -c "cd '$OT_FIX' && LANGFUSE_PUBLIC_KEY=pk-lf-aaa LANGFUSE_SECRET_KEY=sk-lf-bbb bash '$OT_SCRIPT' 2>/dev/null | grep -q 'Basic $OT_AUTH'"
rm -rf "$OT_FIX"
check "bootstrap tells Claude Code users to configure keys via /plugin configure, not .env.harness" \
  bash -c "f=plugins/se-harness/commands/harness-bootstrap.md; grep -q '/plugin configure langfuse-observability@langfuse-observability' \$f && grep -q 'langfuse/Claude-Observability-Plugin' \$f && grep -q 'no plugin' \$f && grep -q 'langfuse-otel-env.sh' \$f"

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
