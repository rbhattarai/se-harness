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
