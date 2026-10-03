---
description: Scan an existing repo to detect stack, devops, cloud, topology, and org conventions; confirm with the user; merge into the harness profile and regenerate AGENTS.md/CLAUDE.md.
argument-hint: [root-dir]
---

# /harness-scan — brownfield detection & profile merge

Detect what this codebase actually uses and fold it into the harness. Re-runnable anytime
(after big refactors, dependency migrations, or org-convention changes). Read-only until the
user confirms the proposal.

## Step 0 — Guard
`.harness/profile.yaml` must exist for the per-repo path below — if not, check whether this
looks like a **workspace root** instead (a `workspace.yaml` or `repos.txt` present, but no
profile.yaml locally — i.e. you're one level above the member repos, not inside one). If so,
go to **Step 0a**. Otherwise, tell the user to run `/harness-init` first and stop.

### Step 0a — Workspace-root scan (§10)
1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/workspace-scan-evidence.sh .` — the deterministic
   collector reports, per declared unit: scanned (with that unit's own `scan-evidence.sh`
   output), `NOT-BOOTSTRAPPED` (cloned but `/harness-init` never ran there), or `NOT-CLONED`;
   plus an `UNDECLARED` section for directories that look like a unit (their own `.git` or
   `.harness/profile.yaml`) but aren't in the manifest. Never modifies anything.
2. **Units not ready**: report any `NOT-BOOTSTRAPPED`/`NOT-CLONED` units plainly and ask
   whether to (a) continue scanning only the ready units, or (b) stop so the user bootstraps/
   clones the rest first (pointing at `/harness-init` or `workspace-clone.sh`). Never silently
   scan a subset without saying so.
3. **Undeclared candidates**: for each, propose adding it as a new unit — name, resolved
   path, and the evidence that flagged it (`.git` present / already has a profile). Confirm
   before writing anything to `workspace.yaml`; an undeclared directory is a candidate, never
   an automatic addition.
4. Continue to Step 1 below treating the collected evidence as covering **every scanned
   unit** — everywhere Steps 1-5 say "this repo," read "each scanned unit," and the
   shared-vs-local reconciliation in Step 2 now runs **once across all of them**, not once per
   separate invocation. Per-unit findings (stack, devops, cloud) stay separate per unit;
   shared findings (methodology, org, non-code sources) get reconciled once against
   `workspace.yaml`'s `shared:` block.

## Step 1 — Collect evidence
**Per-repo** (the common case): run the deterministic collector (read-only, bounded output):
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/scan-evidence.sh ${ARGUMENTS:-.}
```
**Workspace-root** (from Step 0a): the evidence is already collected — `workspace-scan-
evidence.sh` called `scan-evidence.sh` once per ready unit for you; don't re-run it.

Either way, check `profile.yaml`'s `memory.structural_driver` (phase 4) first — if a specific
driver was chosen at init, look for *that one* specifically rather than probing generically
(per unit, at the workspace root). If it's still unset, fall back to checking for any
available code-graph MCP server or the Graphify skill (CodeGraph / codebase-memory-mcp /
Graphify) as before. Either way, if found, index and pull its architecture summary (Graphify:
`graphify-out/GRAPH_REPORT.md` or `graphify query`) — richer structure, but the scan MUST
work without it.

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

**Cross-repo evidence (§10, workspace-root scan only)**: with every unit's evidence in hand at
once, a relationship can be checked from **both sides**, not inferred from one — e.g. unit A's
evidence shows an API client calling `/api/cart`, and unit B's evidence shows that route
actually defined. Two-sided confirmation is materially stronger evidence than either unit
scanned alone could produce; cite both sides in the `evidence:` field when you have them. A
relationship only one side supports is still a candidate (ask, don't silently add), just a
weaker one — say so in the confidence column rather than treating both the same.

**Workspace-scoped fields (phase 3)**: `methodology` and the `sources:`/`org:` fields default
to workspace scope. If a workspace manifest exists, compare this repo's current
`profile.yaml` values against `shared.methodology`/`shared.org`/`shared.jira_project` etc.:
- Same value → nothing to report.
- Different value **with** an explanatory comment already next to it in `profile.yaml` →
  nothing to report (it's a documented exception).
- Different value **with no comment** → flag it as an **undocumented deviation** in the
  proposal table (don't auto-fix; ask whether it should inherit the workspace value or get a
  reason recorded).

## Step 3 — Confirm with the user
- **High-confidence rows**: present the table, bulk-confirm.
- **Low-confidence rows and inconsistencies** (e.g. both `moment` and `dayjs` in use): ask
  one at a time via AskUserQuestion — the user decides what the standard is. Never write a
  low-confidence claim or an invented rule into the profile silently.
- Invite additions the scan can't see (unwritten team rules, internal libs not yet imported).
- **Workspace-root scan (§10)**: present the table grouped **shared findings first** (one
  section — methodology/org/sources deviations, undeclared units, relationship proposals),
  **then per-unit findings** (one subsection per scanned unit — stack/devops/cloud). Batch
  AskUserQuestion calls by group (shared, then one unit at a time), never as one wall of
  questions spanning every unit at once.

## Step 4 — Merge (only after confirmation)
**Per-repo** (the common case) — unchanged:
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

**Workspace-root scan (§10)**: do 1-5 above **once per scanned unit**, using that unit's own
confirmed findings — each unit's `.harness/` stays its own, never shared. Shared findings
merge into `workspace.yaml` **once**: `shared:` field updates, any confirmed undeclared units
added to `units:`, confirmed relationship additions/removals — all validated with
`workspace-validate.sh` before reporting success, same as the per-repo path. A validation
failure on the shared manifest blocks that merge but never rolls back units already merged
successfully; report exactly which units succeeded and which (if any) didn't.

## Step 5 — Report
**Per-repo**: summarize as a before → after diff of the profile (only changed keys).

**Workspace-root scan**: summarize as **shared changes** (workspace.yaml diff) **then
per-unit changes** (one subsection per unit), not interleaved — mirrors Step 3's grouping.
Report any units that were skipped (not ready) and any undeclared directories the user chose
not to add yet, so they're findable next run.

Either way: flag anything deferred (low-confidence rows the user skipped) at the end so it's
findable next run. Suggest follow-ups: `wiki-ingest` for any conventions URL; Phase 3 bootstrap
to install stack-matched plugins for newly detected tech.
