---
description: Detect drift between the project and its harness — stack changes, new recommendations, template updates, memory health — and refresh only generated content after confirmation.
argument-hint: [--dry-run]
---

# /harness-sync — Phase 6 drift detection & refresh

Keep the harness aligned with reality as the project evolves. **Diff first, ask, then apply**;
generated blocks only — hand-written content is never touched. `--dry-run` in `$ARGUMENTS`:
report all drift and stop.

## Step 0 — Guard
`.harness/profile.yaml` and `.harness/agentstack.lock` must exist (run `/harness-init`, then
`/harness-bootstrap`, first) — for the per-repo path below. If neither exists in the current
directory but `workspace.yaml` or `repos.txt` does, go to Step 0a instead; otherwise tell the
user to run `/harness-init` and stop.

### Step 0a — Workspace-root sync
1. Ask once (AskUserQuestion): sync **every** bootstrapped unit (has its own
   `.harness/profile.yaml` + `.harness/agentstack.lock`), **specific units** (name them), or
   let you **suggest** units — propose any unit with no `syncs:` history yet, or whose most
   recent `syncs:` entry predates its most recent commit by a wide margin (stale), and confirm
   the proposed list before proceeding.
2. Skip and report any listed unit that isn't bootstrapped yet (not a guard failure for the
   whole run — just that unit, same as `/harness-bootstrap` Step 0's handling).
3. For each chosen unit, in order: `cd` into it and run Steps 1-4 of this same command,
   directly, same "continue the flow yourself" approach as `/harness-init` Step 1b.
4. Report one consolidated table across all processed units — unit | drift found (axes) |
   applied | skipped — in addition to each unit's own Step 5 report.

### Step 0b — Version stamp check
Read `schema_version` and `se_harness` from `.harness/agentstack.lock` and `version` from
the installed plugin's own `plugin.json` (the plugin manifest that ships this command).
- No `schema_version` (project bootstrapped before stamps existed) → it is a schema-1 project;
  record `schema_version: 1` in Step 4 and say "baseline recorded".
- `schema_version` newer than this plugin understands (1) → the plugin is older than the
  project; tell the user to update the plugin and stop.
- Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate.sh --status`. If it lists pending migrations,
  don't sync first: tell the user the data layout needs upgrading, show `--dry-run`, and on
  confirmation run `migrate.sh` (it backs up, rolls back on failure, and exits 3 on a hand-edited
  generated block — then follow the keep-mine / take-new flow below and re-run with
  `--force-blocks` only if they choose take-new). Then continue with Step 1.
- `se_harness` older than the plugin version → note it in the report; Step 4 sets it to the
  plugin version after a successful sync.

## Step 1 — Collect drift across four axes

**A. Profile drift (project changed).** Run
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/scan-evidence.sh` and compare against `profile.yaml` per
the stack-detector skill: new/removed languages, frameworks, databases, messaging; new
workspace/topology markers; new private-registry scopes or internal imports (org drift);
lint-config changes. Only *differences* matter here — don't re-litigate settled values.

**B. Recommendation drift (registry or profile changed).** Re-run the Step-1 mapping from
`/harness-bootstrap` (profile × `${CLAUDE_PLUGIN_ROOT}/registry/recommendations.json`) and diff against the lockfile:
- newly applicable components (stack additions, registry updates) → propose
- installed components no longer applicable (stack removals) → propose removal, never auto-remove
- `declined` items: **stay declined** — list them in one line at the end, don't re-nag
- `deferred` items ("not yet"): re-ask — see **Decisions** just below
- `pending-manual` items: check whether they got installed since; update status

**Decisions (part of B).** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/decision-review.sh` — one row
per revisitable choice (observability, memory driver, methodology), already resolved against the
workspace default. Projects created before a question existed have no recorded answer: that reads
as `unset`, which is how an older project gets asked about something it was never asked. Per row:
- `observability` is `unset` or `deferred` → **ask now**, once per sync (in a workspace-root run,
  once for the whole run when the unit inherits it from `shared:`): AskUserQuestion — *configure
  now* (follow `/harness-bootstrap`'s **Observability setup** directly) / *keep deferring*
  (records `deferred` + today's date) / *no thanks* (records `declined`). `--dry-run` reports only.
- `configured` or `declined` → never a question. One report line that says what is in force and how
  to change it: "observability: Langfuse @ http://localhost:3000 (configured 2026-10-13) —
  change with `/harness-bootstrap --reconfigure observability`". A `.env.harness: missing …`
  detail is only a problem on the Copilot CLI surface (the Claude Code plugin keeps its keys in the
  OS keychain) — report it as information with that qualifier (variable **names** only — never read
  a secret value).
- `memory` and `methodology` are shown the same one-line way and **never re-asked**: a `null`
  structural driver stays "valid, not nagged", as before. Only observability is re-asked today.
- `invalid(...)` → drift: show the raw value and propose the nearest valid one.

**C. Template drift (plugin updated).** Run
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/template-hash.sh` and compare with `template_hashes` in the
lockfile. Missing map (first sync) → record it now and note "baseline recorded". Changed
hashes → the corresponding generated blocks need re-rendering even if the profile is unchanged.
Also run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/render-block.sh --check <AGENTS.md|CLAUDE.md>`
for each: `modified` means the block was hand-edited — surface it in the report as a conflict
to resolve in Step 3 rather than a silent overwrite; `legacy` means no baseline yet (recorded
on the next splice).

**D. Memory health.** From `.harness/memory/wiki/log.md`: if the last `lint` entry is > 30
days old (or absent with >5 pages), recommend a wiki-lint pass. If `memory.structural_driver`
is Graphify, check `graphify-out/graph.json`'s mtime against recent commit activity — stale
next to a large refactor → recommend `/harness-mem-graphify`; Sourcegraph → nothing local to
refresh; codebase-memory-mcp / CodeGraph → `index_status` or `.codegraph/` freshness vs recent commits, and point
at `/harness-mem-codebase-memory --refresh` / `/harness-mem-codegraph --refresh` when stale; Sourcegraph → point at `/harness-mem-sourcegraph verify` (MCP tools connected?) and `coverage` (repo still on the
instance?) — run neither yourself, and surface the `decision-review.sh` detail if `memory.sourcegraph.url` is empty or the token
variable is missing; any other structural-memory
server → remind that reindexing is cheap after large refactors. Check MEMORY.md length
(> ~40 lines → memory-keeper consolidation due).

**E. Conventions & org policy.** Read-only checks; never rewrites a convention doc's content.
- *Index vs files*: every `org.convention_docs` entry's `path` must exist (relative to this repo);
  a missing file = drift (propose removing the entry or restoring the file). A file in
  `.harness/conventions/` with no index entry = propose adding it.
- *Workspace ↔ unit*: in a workspace, compare `shared.org.convention_docs` with this unit's
  `scope: workspace` entries — missing, extra, wrong relative path, or status that differs
  from the workspace copy = drift (propose the corrected entry). A unit doc that overrides a
  workspace area without `overrides: workspace` = flag.
- *Staleness*: apply `/harness-conventions` Step 5's checks (library version in the doc's
  `libraries` frontmatter vs the manifest, `evidence_hash` vs the lint/format configs,
  `applies_to` vs new top-level folders). Stale → propose `status: stale` in the index and
  recommend `/harness-conventions --refresh <area>` — sync does not redraft.
- *Coverage*: a stack area with source files and no doc at all → one line recommending
  `/harness-conventions <area>` (report once; not re-nagged if the user declined before).
- *Guardrails*: in a workspace, `shared.org.guardrails` lines missing from this unit's
  `org.guardrails` = drift (propose adding); unit-only extra lines are fine. Never ask about
  guardrails otherwise, and never infer them.

## Step 2 — Present the drift report
One table: **axis (A-E) | item | current → proposed | action**. If everything is clean, say exactly
that in one line and stop — no ceremony, no empty tables.

## Step 3 — Apply (only confirmed items; skip entirely on --dry-run)
1. Profile updates → `.harness/profile.yaml` (user-entered values win unless explicitly
   overridden in Step 2).
2. Org changes → regenerate `.harness/org-rules.txt`. Axis E fixes (convention-doc index entries,
   inherited guardrails) go to `.harness/profile.yaml` here and are rendered in step 4 below.
3. Component installs/removals → same mechanics as `/harness-bootstrap` Step 3 (CLI with
   `pending-manual` fallback; confirm before running any third-party CLI install).
4. Re-render AGENTS.md/CLAUDE.md inner blocks from the updated profile and splice:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/render-block.sh <target> <block-file>` — also when only
   template drift (axis C) triggered it.
   If it exits **3**, the generated block was hand-edited since the last render and was left
   untouched (`<target>.seaa.proposed` holds the new version): show the user a diff of the two,
   and ask keep-mine / take-new / merge. Only on take-new re-run with `--force` (the edited block
   is saved to `<target>.seaa.bak`). Never pass `--force` without asking.
5. `.mcp.json`: merge any new server entries; never remove servers the user added by hand.
6. Decision changes → write the `observability:` block in `profile.yaml` (`status`, `provider`, `host`,
   `decided`; and `shared.observability` when inherited) exactly as `/harness-bootstrap`'s
   Observability setup does, including keeping secrets out of every committed file.

## Step 4 — Update the lockfile
Set `updated`; set `schema_version` (if absent: 1) and `se_harness` to the plugin version;
refresh `template_hashes`; record convention-doc statuses seen (`conventions:` entry: date, areas, stale ones); update component statuses (`installed` / `pending-manual` / `declined` / `deferred`); append to `syncs:`
history — `{date, drift_found: [axes], applied: [...], skipped: [...]}` — so the next sync
(and the user) can see what happened last time.

## Step 5 — Report
Applied / skipped / still-pending-manual, one line each. Deferred low-confidence detections
go at the end (same convention as `/harness-scan`) so they resurface next run.
