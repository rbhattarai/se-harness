---
description: Run the loop-engineering workflow for a user goal — grill, deep-dive, refine, story, implement, test, PR, deploy — with human gates at irreversible steps.
argument-hint: <goal statement>
---

# /harness-goal — the loop-engineering workflow

Process the user's goal (`$ARGUMENTS`) through the pipeline below. You are the **supervisor**:
you orchestrate the phase agents, own the artifacts, and stop at the three ⛔ gates until the
human explicitly approves. Never skip, reorder, or merge gates. Every phase output is a file
with status frontmatter — never chat-only.

## 1. Grill the requirement  *(requirement-grill skill)*
Interrogate until falsifiable: outcome, explicit scope exclusions, testable acceptance
criteria (no "fast/better/robust"), the non-functionals this change can violate, failure
behavior, conflicts with prior decisions (wiki-query + org conventions). Batch questions,
stop when testable — over-grilling erodes trust.

## 2. Deep-dive memory — build the impact map (workspace-orchestration plan §5.2)
- **Structural**: the configured tier-1 driver (`memory.structural_driver`) or a code-graph
  MCP — impacted files, callers, blast radius. If the driver is Graphify and `graphify-out/`
  is missing or stale, that's a gap to flag in the impact map, not a reason to stop — note it
  and suggest `/harness-mem-graphify`, then fall back to Grep/Glob for this goal. If
  `workspace.yaml` exists, check its `contracts:`/`relationships:` for provides/consumes
  (contract impact) and identify which declared **components/units** this goal plausibly
  touches.
- **Domain**: wiki-query over `.harness/memory/wiki/` (related PRDs, decisions, contradictions).
- **Session**: `MEMORY.md` + recent daily logs for prior attempts (`[[...]] causes [[...]]` chains).

Record each candidate component in an **impact map**: component, why it's included, evidence
source, confidence. Check current code before treating indexed memory as authoritative; drop
anything whose name merely sounds relevant with no cited evidence. No `workspace.yaml` at all
means the impact map is trivially "this repo" — one component, skip straight to step 3's fast
path. The **distinct component count** from this map feeds step 3's fast-path decision.

## 3. Refined requirement  ⛔ HITL GATE 1
```
bash tools/harness/new-requirement.sh "<one-line goal>"
```
Fill the created `REQ-NNN.md` (grill output + deep-dive impact; status stays `draft`).

**Scale to impact size (§5.0)** — this is not an optional optimization, it is the mechanism
that keeps a single-repo goal exactly as simple as today:
- **Impact map names 0-1 components**: continue below unchanged. No workspace plan file, no
  extra ceremony, ever.
- **Impact map names 2+ components**: also render `templates/workspace-plan.md` into
  `REQ-NNN/workspace-plan.md` — one row per impacted component (owner, outcome, `depends_on`,
  evidence), every row starting at `status: pending`. Present it **alongside** the REQ for the
  same approval below, not as a second gate.

**Stop and present it** (REQ, and workspace-plan.md if one was created). Only the user flips
status to `approved` — record `approved` verbatim from their reply; assumptions you made go
under "resolved by agent default" so the gate shows them. `gate-check.sh` blocks push/PR/deploy
while nothing is approved, and — once a workspace plan exists for this REQ — while any of its
rows haven't reached `status: done` either.

## 4. Story + test cases  *(story-writer agent)*
Delegate to **story-writer**: Jira story + XRay/Zephyr test cases via Atlassian MCP (tracker =
system of record; local copies in `REQ-NNN/`). Story key + test-case keys land in the REQ
frontmatter. The story ID threads through branch names, commits, and the PR from here on.

## 5. Design + implement  *(architect → implementers, isolated worktrees)*

**No `workspace-plan.md`** (0-1 component, the common case): proceed with 1-5 below, unchanged.

**`workspace-plan.md` exists** (2+ components): delegate to **workspace-orchestrator** (phase
6 of the workspace-orchestration plan) rather than running 1-5 below yourself. It works the
rows in dependency order — serializing anything another row's `depends_on` names until that
dependency is `done`, parallelizing the rest — doing the work directly for a row in this repo,
crossing into a sibling repo's already-cloned tree for a row that lives there, and updating
each row's `status:` as it goes. It never bypasses a repo's own PR/deploy gates (steps 7/9
below still apply, per repo, with explicit approval each time) and never marks a row `done`
without passing that row's own automated gate. If the runtime can't actually cross into a
sibling repo from here, it says so and falls back to the step-5 handoff: tell the user to run
`/harness-goal` directly in that repo, referencing this REQ id, and leave the row
`in-progress` until that run flips it to `done`.

1. **architect** produces `REQ-NNN/design.md`; resolve its open questions with the user
   before any code. (Workspace-orchestrator follows this same step 1-5 procedure per row it
   works — one `design.md` per component, or a shared file with one section each; it states
   which.)
2. Break the design into tasks; typical order — db first, then backend ∥ frontend in parallel:
   ```
   bash tools/harness/worktree-task.sh create REQ-NNN db-schema
   bash tools/harness/worktree-task.sh create REQ-NNN backend-api
   bash tools/harness/worktree-task.sh create REQ-NNN frontend-ui
   ```
3. Delegate each task to its agent (**db-engineer**, **implementer-backend**,
   **implementer-frontend**) — each works only in its worktree, compose-first, tests included,
   commits tagged with the REQ id.
4. Merge task branches back sequentially into the REQ integration branch; run **unit-tester**
   then **integration-tester** on the merged result. `worktree-task.sh remove` each done task
   (it refuses on uncommitted work — that's deliberate).
5. Automated gate (no human needed): full test suite green, lint clean, org-validate clean,
   and `bash tools/harness/contract-check.sh --` clean — if a provided contract
   changed, list the impacted consumer units in the REQ and create linked consumer tasks
   before proceeding. Red anything → back to the owning agent, not onward.

## 6. E2E tests  *(planner → generator → healer)*
**e2e-planner** turns `test-cases.md` into `e2e-plan.md` → **e2e-generator** writes Playwright
specs against the live app (real selectors via Playwright MCP) → failures classified by
**e2e-healer** (test defects healed; app regressions reported back to step 5, never papered over).
If `workspace-plan.md` exists and the acceptance criteria span components, these specs target
the **combined** system (`workspace.yaml`'s `run.compose`), the same one
workspace-orchestrator's integration check (step 5, item 4) exercises — don't write a second,
narrower e2e suite that only covers this repo's slice.

## 7. Pull request  ⛔ HITL GATE 2
Present the evidence table: diff summary, unit/integration/e2e results, org-rule compliance,
anything hand-rolled because no internal component fit. If `workspace-plan.md` exists, include
its current row statuses **and** `integration:` result in the evidence — `gate-check.sh` blocks
the PR itself while any row isn't `done` or `integration:` isn't `passed` (phase 8, §5.4: rows
done in isolation is not the same as the pieces working together), so this is worth surfacing
before the user even asks. On approval: draft PR via GitHub MCP, titled with REQ + story key.

## 8. Local verify
Generate/update docker-compose; build and run the whole app locally — if `workspace-plan.md`
exists, this is the **same** workspace-level compose and combined system
workspace-orchestrator's step-5 integration check already brought up, re-run here as the final
pre-deploy confirmation, not a separate narrower check. Smoke-check the REQ's
acceptance criteria end-to-end. Attach results to the PR.

## 9. Cloud deploy  ⛔ HITL GATE 3  *(release-manager agent)*
Approval must be explicit **in this session** — prior approvals don't carry over. Delegate to
**release-manager**: version, release notes from the REQ/story, checklist, deploy via the
profile's provider plugin, watch rollout, documented rollback on failure.

## 10. Close the loop  *(memory-keeper skill)*
Set REQ status `done`. If `workspace-plan.md` exists, confirm every row is already `done` (it
must be, or gate-check.sh would have blocked step 7/9) and add a closing line to its
Integration notes. Append the day's entry: what shipped, decisions, dead ends, typed links
(`[[REQ-NNN]] solves [[...]]`). If domain knowledge changed, wiki-ingest the delta. Commits/PRs
were auto-logged by the post-commit hook — don't duplicate them.
