---
name: harness-goal
description: Run the loop-engineering workflow for a user goal — grill, deep-dive, refine, story, implement, test, PR, deploy — with human gates at irreversible steps.
---


# /harness-goal — the loop-engineering workflow

Process the user's goal (`$ARGUMENTS`) through the pipeline below. You are the **supervisor**:
you orchestrate the phase agents, own the artifacts, and stop at the three ⛔ gates until the
human explicitly approves. Never skip, reorder, or merge gates. Every phase output is a file
with status frontmatter — never chat-only.

## 0. Preflight — conventions & memory  *(before anything else — cheap, read-only)*
### 0a. Conventions
Read `org.convention_docs` in `profile.yaml` — it already includes the workspace-scope docs, each
with a path relative to this repo. If `workspace.yaml` exists and its `shared.org.convention_docs`
has an area missing here, treat that as sync drift: use it for this run and suggest `/harness-sync`. From the goal text and the stack, guess the areas it will touch (UI → `angular`,
tests → `e2e-playwright`, API → `dotnet`, schema → `db-*`, plus any `lib-*` it names).
- **Every touched area has a `confirmed` doc** → read those docs now (rules + library catalog)
  and carry them into steps 1-6: the grill asks about library choices they already settle
  instead of re-asking, and the architect/implementers start from them. Say which docs you loaded.
- **Any touched area has no doc, a `draft`, or a `stale` one** → ask once (AskUserQuestion):
  run `/harness-conventions <areas>` now (recommended — then continue) / proceed without. Proceeding
  is allowed; record "no confirmed conventions for <areas>" in the REQ's impact map and repeat it
  in the PR evidence. Never block the goal on it, and don't re-ask within the same run.
- **No `org.convention_docs` at all** (never run) → same question, worded as a first-time setup.

### 0b. Memory readiness
Establish what memory actually exists, so the grill and deep-dive use it instead of discovering
mid-run that it was never built. Check, without building or ingesting anything:
- **Code memory (tier 1)** — `memory.structural_driver` (or `shared.memory.structural_driver`):
  - Graphify → `graphify-out/graph.json` + `GRAPH_REPORT.md` exist? mtime older than the latest
    commits → stale.
  - MCP drivers (codebase-memory-mcp, CodeGraph) → is that server's tool actually among your
    tools this session? Not connected → `/harness-mem-codebase-memory` / `/harness-mem-codegraph`
    (registration and restart). codebase-memory-mcp: `index_status` / `list_projects` shows whether this
    repo is indexed; its watcher only covers the project of the open session, so other repos can be
    stale — suggest `--refresh`. CodeGraph (colbymchenry): `codegraph_status`, if enabled, or a missing
    `.codegraph/` means not indexed. Note CodeGraph lists only `codegraph_explore` unless
    `CODEGRAPH_MCP_TOOLS` is set.
  - Sourcegraph → are its tools (`mcp__sourcegraph__*`: `keyword_search`, `find_references`,
    `list_repos`, ...) connected this session? If so call `list_repos` for this repo (and each
    unit in `workspace.yaml`): a repo that is **not on the instance** is a gap — Sourcegraph
    cannot answer for it. Not connected → "not connected: run `/harness-mem-sourcegraph verify`". Repo
    not on the instance → point at `/harness-mem-sourcegraph coverage`. There is no local index to be stale, but it reflects the instance's
    default branch, not this working tree.
  - `null`/deferred → "none configured" (valid; Grep/Glob fallback, said plainly later).
  - Any other memory tool the project wired in `.mcp.json` (e.g. a mem0-style server) counts as
    available if its tools are present; use it, don't assume its semantics beyond its tool docs.
- **Non-code memory (tier 3 wiki)** — workspace-root and repo `.harness/memory/wiki/index.md`
  exist and list pages? Compare with `workspace.yaml`'s `shared:` sources
  (`jira_project`, `confluence_spaces`, `sharepoint_sites`, `nas_*_paths`): sources configured
  but wiki empty/no log entry for them = never ingested.
- **Session memory (tier 2)** — `MEMORY.md`/SCRATCHPAD present (the context-injector hook already
  loads these; just note if missing).

Print one compact status (tier | driver/source | state: ready / stale / not built / not
configured). For **stale or not built** items that this goal plausibly needs, ask once
(AskUserQuestion) whether to run the fix now — `/harness-mem-graphify` (code) and/or
`/harness-mem-wiki <source>` (non-code) — or continue; both are opt-in and may be slow, so
continuing is always allowed. Don't re-ask within the run, and never build or ingest silently.
Then do a **light pre-grill lookup** with whatever is ready: a quick structural query for the
goal's key nouns and `wiki-query` on its domain terms, so the grill asks code-aware, domain-aware
questions (and skips what memory already answers) rather than interrogating from a blank slate.
Carry the status into step 2 and into the REQ's impact map ("memory gaps: ...").

## 1. Grill the requirement  *(requirement-grill skill)*
Interrogate until falsifiable: outcome, explicit scope exclusions, testable acceptance
criteria (no "fast/better/robust"), the non-functionals this change can violate, failure
behavior, conflicts with prior decisions (wiki-query + org conventions + the step 0 lookups). Batch questions,
stop when testable — over-grilling erodes trust.

## 2. Deep-dive memory — build the impact map (workspace-orchestration plan §5.2)
- **Structural**: query the configured tier-1 driver (`memory.structural_driver`) for impacted
  files, callers, blast radius — concretely, by driver, not Grep/Glob by default:
  - **Graphify** (CLI/flat-file, not MCP): read `graphify-out/graph.json` and
    `GRAPH_REPORT.md` directly, or run `graphify query <symbol-or-file>` via Bash for a
    live, targeted query. If `graphify-out/` is missing or stale (mtime older than recent
    commits), that's a gap to flag in the impact map, not a reason to stop — note it, suggest
    `/harness-mem-graphify`, and fall back to Grep/Glob for *this* goal only.
  - **codebase-memory-mcp or a CodeGraph variant** (MCP-based): look for that server's own
    tool in your available tools (`mcp__<server-name>__*`) and call it. If the configured
    driver's MCP server isn't actually connected this session, that's the same kind of gap as
    Graphify above — flag it, don't silently fall back without saying so.
  - **Sourcegraph** (remote MCP): use its tools for the impact map — `keyword_search` /
    `nls_search` for callers and usages **across every repo on the instance in one query** (this
    is its strength for a multi-repo workspace), `go_to_definition` / `find_references` for symbol
    blast radius, `read_file` / `list_files` for a repo you haven't cloned, `commit_search` /
    `diff_search` for history. Prefix queries with `memory.sourcegraph.repo_scope` if set. Treat
    results as an index of the instance's default branch: confirm against the local files before
    citing them, and say so for any repo not on the instance (Grep/Glob for those, stated plainly).
  - **`null`/deferred, or the configured driver is unavailable**: Grep/Glob is the honest
    fallback here — say so in the impact map rather than presenting it as equivalent to a real
    structural query.

  If `workspace.yaml` exists, check its `contracts:`/`relationships:` for provides/consumes
  (contract impact) and identify which declared **components/units** this goal plausibly
  touches.
- **Domain**: `wiki-query` (checks the workspace-level wiki when one exists, plus this repo's
  own — the skill handles both locations) for related PRDs, decisions, contradictions.
- **Session**: `MEMORY.md` + recent daily logs for prior attempts (`[[...]] causes [[...]]` chains).

- **Conventions**: apply the step 0 result — list the docs that govern each impacted component
  and any area still without a confirmed one.

Record each candidate component in an **impact map**: component, why it's included, evidence
source, confidence. Check current code before treating indexed memory as authoritative; drop
anything whose name merely sounds relevant with no cited evidence. No `workspace.yaml` at all
means the impact map is trivially "this repo" — one component, skip straight to step 3's fast
path. The **distinct component count** from this map feeds step 3's fast-path decision.

## 2b. Scope triage — size the change before committing to the loop
Nothing below step 2 changes code until Gate 1, but the loop *after* it runs end to end, so size
the change now, from the impact map and the grill — not from a gut feel. Score these signals
(each is evidence you can cite, not a vibe):

| Signal | Points toward large |
|---|---|
| Components / layers touched | 3+ components, or db + backend + frontend + e2e together |
| Breadth | roughly 15+ files, or a change that fans out through many callers (graph blast radius) |
| Contracts / schema | a provided contract or DB schema changes with consumers to migrate |
| Risk class | data migration, auth/permissions, payments, anything hard to reverse |
| Novelty | no existing pattern to extend; a new layer, paradigm or library |
| Clarity | 8+ acceptance criteria, or open questions about the *approach* (not just details) |

**Size**: **S** = one component, one layer, few files, clear pattern, ≤3 acceptance criteria ·
**L** = any one *critical* signal (irreversible data migration, new architectural paradigm) or
any two other signals · **M** = everything between. These thresholds are heuristics; show your
evidence and let the user overrule the size either way. Record it as `size:` in the REQ.

- **S or M** → continue to step 3 unchanged. Say the size in one line and move on; don't add
  ceremony to ordinary work.
- **L** → stop and tell the user plainly, with the signals that drove it: *"This change looks
  large/complex, so I'll do the analysis first in Plan mode — no code will be changed in the
  loop."* Ask (AskUserQuestion): **analyze first in Plan mode** (recommended) / **proceed with the
  full loop anyway** / **narrow the goal** (back to step 1).

### 2c. Plan-mode analysis (large changes only)
Enter the surface's plan mode if it has one (Claude Code: `EnterPlanMode`; Copilot: Plan mode /
the Plan agent). Without one, hold yourself to the same rule: **read-only — no edits outside
`.harness/`, no worktrees, no commands that change state.** Work from the impact map and the
step 0 conventions/memory: approach options and the chosen one, the sequence of changes, risks,
unknowns, what can ship independently. Delegate to **architect** for the design questions.
Present the analysis, get approval to leave plan mode, then write it to
`.harness/requirements/REQ-NNN/analysis.md`. Re-score the size with what the analysis learned.

- **Now S or M** → proceed to step 3 for the whole goal.
- **Still L** → break it into **phases**: each independently shippable and testable, each sized S
  or M, each with its own acceptance-criteria subset, ordered by dependency first, then value and
  risk (cheap/de-risking first). Create the parent via `new-requirement.sh` with `status: epic`
  (never `approved`: `gate-check.sh` only unlocks on approved/in-progress, so an epic can't
  unlock push/PR/deploy) and write `REQ-NNN/phases.md`: a table of phase | outcome | size | depends
  on | status (`pending`). Present it and ask which phase to implement in the loop — and which
  order, if they want to reprioritize. Phases can be dropped, merged or reordered by the user.
- **Per phase**: create a child REQ with `new-requirement.sh "<phase goal>"`, set `parent:
  REQ-NNN` and `phase:` in its frontmatter, and run steps 3-10 for it, scoped to that phase's
  acceptance criteria only. Every child has its own Gate 1, PR and deploy gates. When the child
  reaches step 10, mark the phase `done` in `phases.md`, then return here and ask whether to
  continue with the next phase, reorder, or stop. Never start the next phase without asking.
  The epic becomes `done` only when every phase is `done` or explicitly dropped.

## 3. Refined requirement  ⛔ HITL GATE 1
```
bash tools/harness/new-requirement.sh "<one-line goal>"
```

**Methodology is OpenSpec** (`methodology: openspec` in `profile.yaml`/`workspace.yaml`):
locate the installed `/opsx:propose` command definition for this client — search wherever this
surface's command files live (`.claude/commands/`, `.github/prompts/`, or equivalent) for
something matching `opsx*propose*`; `/harness-methodology-openspec` installed it. Not found →
that's a setup gap, say so and point at that command rather than guessing a path. Found → read
and follow it, passing the grilled, falsifiable goal from step 1 (not the raw `$ARGUMENTS`) as
the description. Let it write `openspec/changes/<change-id>/{proposal.md,specs/,design.md,
tasks.md}` as it normally would. Fill `REQ-NNN.md` as a **thin pointer**, not a duplicate: grill
summary, deep-dive impact map, `openspec_change_id: <change-id>` in frontmatter, status stays
`draft` — don't re-write what `proposal.md`/`specs/` already say.

**Any other methodology (including se-harness's own built-in loop)**: fill the created
`REQ-NNN.md` directly (grill output + deep-dive impact; status stays `draft`) — unchanged.

**Scale to impact size (§5.0)** — this is not an optional optimization, it is the mechanism
that keeps a single-repo goal exactly as simple as today:
- **Impact map names 0-1 components**: continue below unchanged. No workspace plan file, no
  extra ceremony, ever.
- **Impact map names 2+ components**: also render `../se-harness/plugins/se-harness/templates/workspace-plan.md` into
  `REQ-NNN/workspace-plan.md` — one row per impacted component (owner, outcome, `depends_on`,
  evidence), every row starting at `status: pending`. Present it **alongside** the REQ for the
  same approval below, not as a second gate.

**Stop and present it** (REQ, and workspace-plan.md if one was created — for OpenSpec, point at
`openspec/changes/<change-id>/proposal.md` and `specs/` alongside it, since that's where the
real spec content lives, not in the REQ itself). Only the user flips status to `approved` —
record `approved` verbatim from their reply; assumptions you made go under "resolved by agent
default" so the gate shows them. For OpenSpec, this approval **is** the review OpenSpec's own
docs say should happen before `/opsx:apply` — step 5 below deliberately never runs
`/opsx:apply` itself (se-harness's own worktree-isolated, gate-enforced implementer agents do
the actual coding, same as any other methodology, reading `tasks.md` as their task source), so
there's no second OpenSpec-side approval to collect; don't ask twice for one decision.
`gate-check.sh` blocks push/PR/deploy while nothing is approved, and — once a workspace plan
exists for this REQ — while any of its rows haven't reached `status: done` either.

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
   which.) **OpenSpec REQ** (has `openspec_change_id`): `/opsx:propose` already drafted
   `openspec/changes/<change-id>/design.md` — architect **refines** it (same "resolve open
   questions with the user" discipline, applied to what's already there) rather than authoring
   one from scratch; `REQ-NNN/design.md` stays a pointer to it, not a second copy.
2. Break the design into tasks. **OpenSpec REQ**: derive the breakdown from
   `openspec/changes/<change-id>/tasks.md`'s checklist instead of inventing one — one
   `worktree-task.sh create` per checklist item (or logical group of adjacent items), and check
   each one off in `tasks.md` as its worktree task completes, so OpenSpec's own tracking stays
   truthful. **Any other methodology**: typical order — db first, then backend ∥ frontend in
   parallel:
   ```
   bash tools/harness/worktree-task.sh create REQ-NNN db-schema
   bash tools/harness/worktree-task.sh create REQ-NNN backend-api
   bash tools/harness/worktree-task.sh create REQ-NNN frontend-ui
   ```
3. Delegate each task to its agent (**db-engineer**, **implementer-backend**,
   **implementer-frontend**) — each works only in its worktree, compose-first, tests included,
   commits tagged with the REQ id. Name the convention docs that match the task in the
   delegation message so the agent loads them first.
4. Merge task branches back sequentially into the REQ integration branch; run **unit-tester**
   then **integration-tester** on the merged result. `worktree-task.sh remove` each done task
   (it refuses on uncommitted work — that's deliberate).
5. Automated gate (no human needed): full test suite green, lint clean, org-validate clean,
   and `bash tools/harness/contract-check.sh --` clean — if a provided contract
   changed, list the impacted consumer units in the REQ and create linked consumer tasks
   before proceeding. **Convention review**: check the diff against the matching convention
   docs' MUST rules and library catalog (hand-rolled code where a catalog entry exists is a
   violation); list each finding with the rule number it cites. Red anything → back to the
   owning agent, not onward.

## 6. E2E tests  *(planner → generator → healer)*
**OpenSpec REQ**: `openspec/changes/<change-id>/specs/`'s scenarios are already written in a
WHEN/THEN shape close to test-case form — e2e-planner should read them as additional input
alongside `test-cases.md`, not ignore them in favor of re-deriving the same scenarios from
scratch. **e2e-planner** turns `test-cases.md` into `e2e-plan.md` → **e2e-generator** writes Playwright
specs against the live app (real selectors via Playwright MCP) → failures classified by
**e2e-healer** (test defects healed; app regressions reported back to step 5, never papered over).
If `workspace-plan.md` exists and the acceptance criteria span components, these specs target
the **combined** system (`workspace.yaml`'s `run.compose`), the same one
workspace-orchestrator's integration check (step 5, item 4) exercises — don't write a second,
narrower e2e suite that only covers this repo's slice.

## 7. Pull request  ⛔ HITL GATE 2
Present the evidence table: diff summary, unit/integration/e2e results, org-rule compliance, convention-doc compliance (rule numbers cited; areas with no confirmed doc),
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
Set REQ status `done`. **Child REQ** (has `parent:`): mark its phase `done` in the epic's `phases.md` and go back to step 2c's per-phase prompt before anything else. If `workspace-plan.md` exists, confirm every row is already `done` (it
must be, or gate-check.sh would have blocked step 7/9) and add a closing line to its
Integration notes. **OpenSpec REQ**: now that the change has actually shipped (deploy gate
passed), locate and follow the installed `/opsx:archive` command the same way step 3 found
`/opsx:propose` — it moves `openspec/changes/<change-id>/` to
`openspec/changes/archive/<timestamp>/` and updates the living specs; this is deliberately the
*last* thing that happens, not right after merge, since the spec should only be promoted to
canonical once the change is live. Append the day's entry: what shipped, decisions, dead ends,
typed links (`[[REQ-NNN]] solves [[...]]`). If domain knowledge changed, wiki-ingest the delta.
Commits/PRs were auto-logged by the post-commit hook — don't duplicate them.
