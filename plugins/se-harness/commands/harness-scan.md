---
description: Scan an existing repo to detect stack, devops, cloud, topology, and org conventions; confirm with the user; merge into the harness profile and regenerate AGENTS.md/CLAUDE.md.
argument-hint: [root-dir]
---

# /harness-scan — brownfield detection & profile merge

Detect what this codebase actually uses and fold it into the harness. Re-runnable anytime
(after big refactors, dependency migrations, or org-convention changes). Read-only until the
user confirms the proposal.

## Step 0 — Guard
`.harness/profile.yaml` must exist — if not, check whether this looks like a **workspace
root** instead (a `workspace.yaml` or `repos.txt` present, but no profile.yaml locally — i.e.
you're one level above the member repos, not inside one). If so, say that explicitly and point
at scanning **inside each member repo** — this command is still per-repo scoped; a true
workspace-root scan across every member repo in one pass is not yet implemented (see
`docs/workspace-orchestration-plan.md` §10). Otherwise, tell the user to run `/harness-init`
first and stop.

## Step 1 — Collect evidence
Run the deterministic collector (read-only, bounded output):
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/scan-evidence.sh ${ARGUMENTS:-.}
```
If a code-graph MCP server or the Graphify skill is available (CodeGraph / codebase-memory-mcp /
Graphify), also index and pull its architecture summary (Graphify: `graphify-out/GRAPH_REPORT.md`
or `graphify query`) — richer structure, but the scan MUST work without it.

## Step 2 — Detect (stack-detector skill)
Reason over the evidence per the **stack-detector** skill: usage beats listing; version-aware;
app vs tooling; cloud from artifacts; per-unit stacks when topology markers exist. Follow up
with targeted file reads where the evidence is ambiguous — do not skip the verification greps.

Produce the proposal table (field | proposed value | evidence | confidence) covering:
`project.topology` (+ units if mono-repo/modulith — same detection rules as `/harness-init`
Step 3, including modulith candidates and evidenced `components:`/`relationships:` entries),
`stack.*`, `devops.*`, `cloud`, and the full `org:` section (internal libraries, preferred
libraries, conventions — explicit from configs AND implicit inferred from code).

Re-scans can find **new or changed** cross-unit relationships since the last run (a new
import, a new compose `depends_on`) — propose additions/removals the same evidence-required
way as init, and flag (don't silently drop) any existing `relationships:` entry whose evidence
file no longer exists.

## Step 3 — Confirm with the user
- **High-confidence rows**: present the table, bulk-confirm.
- **Low-confidence rows and inconsistencies** (e.g. both `moment` and `dayjs` in use): ask
  one at a time via AskUserQuestion — the user decides what the standard is. Never write a
  low-confidence claim or an invented rule into the profile silently.
- Invite additions the scan can't see (unwritten team rules, internal libs not yet imported).

## Step 4 — Merge (only after confirmation)
1. **`.harness/profile.yaml`** — update detected keys. Existing user-entered values win on
   conflict unless the user explicitly approved the override in Step 3.
2. **`workspace.yaml`** — if topology/component/relationship rows changed, apply them here
   (never only to `profile.yaml`) and validate with
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/workspace-validate.sh workspace.yaml` before reporting
   success; a validation failure blocks the merge for that file, not the rest of Step 4.
3. **`.harness/org-rules.txt`** — regenerate from the confirmed `org.preferred_libraries`
   pairs (`banned:<never>:use <use> (<reason>)`).
4. **AGENTS.md / CLAUDE.md** — re-render the template inner blocks from the updated profile and
   splice via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/render-block.sh <target> <block-file>`
   (never edit these files directly).
5. **`.harness/agentstack.lock`** — set `updated` timestamp and append a `scans:` entry
   (date + one-line summary of what changed).

## Step 5 — Report
Summarize as a before → after diff of the profile (only changed keys). Flag anything deferred
(low-confidence rows the user skipped) at the end so they're findable next run. Suggest
follow-ups: `wiki-ingest` for any conventions URL; Phase 3 bootstrap to install stack-matched
plugins for newly detected tech.
