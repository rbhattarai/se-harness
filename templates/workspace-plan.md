<!--
workspace-plan.md — ONLY created when a requirement's impact map (workspace-orchestration
plan §5.2) spans 2+ components (§5.0's fast path). A single/few-component requirement never
gets one of these — it stays exactly today's /harness-goal flow. Lives at
.harness/requirements/REQ-NNN/workspace-plan.md, a sibling of design.md/story.md.

Row shape is intentionally a single line per task (not a markdown table) so gate-check.sh can
grep it with no YAML/table parser: every row starts with "- component:" and carries
"status: <value>" verbatim. Never reformat a row across multiple lines.

Status values: pending | in-progress | done | blocked. ALL rows must reach `done` before
gate-check.sh allows push/PR/deploy for this REQ — approving the requirement is not approving
incomplete cross-component work.

`integration:` (phase 8, workspace-orchestration plan §5.4/§12): every row reaching `done`
only means each component passed its OWN gate in isolation — it does not mean the pieces work
together. gate-check.sh also requires `integration: passed` before push/PR/deploy; the
workspace-orchestrator sets this only after running the combined check (workspace-level
docker-compose + cross-repo contract-check + any spanning e2e) against the actual combined
changes. Never hand-set this to `passed` without that check actually having run.
-->
---
req: REQ-000
created: YYYY-MM-DD
updated: YYYY-MM-DD
integration: pending   # pending | passed | failed — see Integration notes for detail
---

# Workspace plan — REQ-000

One row per impacted component (from the REQ's impact map). Serialize a row that depends on
another row's contract/schema/design decision (`depends_on:`); parallelize the rest.

- component: <id> | status: pending | owner: <agent-or-repo> | outcome: <one-line acceptance> | depends_on: <component-id-or-"-"> | evidence: <contract/doc path or "-">

## Integration notes
<Cross-boundary findings, contract changes, blockers — filled in as work proceeds. The
supervisor updates this and each row's `status:` directly; there is no separate script for it.>
