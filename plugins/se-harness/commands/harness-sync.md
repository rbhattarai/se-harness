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
`/harness-bootstrap`, first).

## Step 1 — Collect drift across four axes

**A. Profile drift (project changed).** Run
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/scan-evidence.sh` and compare against `profile.yaml` per
the stack-detector skill: new/removed languages, frameworks, databases, messaging; new
workspace/topology markers; new private-registry scopes or internal imports (org drift);
lint-config changes. Only *differences* matter here — don't re-litigate settled values.

**B. Recommendation drift (registry or profile changed).** Re-run the Step-1 mapping from
`/harness-bootstrap` (profile × `registry/recommendations.json`) and diff against the lockfile:
- newly applicable components (stack additions, registry updates) → propose
- installed components no longer applicable (stack removals) → propose removal, never auto-remove
- `declined` items: **stay declined** — list them in one line at the end, don't re-nag
- `pending-manual` items: check whether they got installed since; update status

**C. Template drift (plugin updated).** Run
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/template-hash.sh` and compare with `template_hashes` in the
lockfile. Missing map (first sync) → record it now and note "baseline recorded". Changed
hashes → the corresponding generated blocks need re-rendering even if the profile is unchanged.

**D. Memory health.** From `.harness/memory/wiki/log.md`: if the last `lint` entry is > 30
days old (or absent with >5 pages), recommend a wiki-lint pass. If `memory.structural_driver`
is Graphify, check `graphify-out/graph.json`'s mtime against recent commit activity — stale
next to a large refactor → recommend `/harness-mem-graphify`; any other structural-memory
server → remind that reindexing is cheap after large refactors. Check MEMORY.md length
(> ~40 lines → memory-keeper consolidation due).

## Step 2 — Present the drift report
One table: **axis | item | current → proposed | action**. If everything is clean, say exactly
that in one line and stop — no ceremony, no empty tables.

## Step 3 — Apply (only confirmed items; skip entirely on --dry-run)
1. Profile updates → `.harness/profile.yaml` (user-entered values win unless explicitly
   overridden in Step 2).
2. Org changes → regenerate `.harness/org-rules.txt`.
3. Component installs/removals → same mechanics as `/harness-bootstrap` Step 3 (CLI with
   `pending-manual` fallback; confirm before running any third-party CLI install).
4. Re-render AGENTS.md/CLAUDE.md inner blocks from the updated profile and splice:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/render-block.sh <target> <block-file>` — also when only
   template drift (axis C) triggered it.
5. `.mcp.json`: merge any new server entries; never remove servers the user added by hand.

## Step 4 — Update the lockfile
Set `updated`; refresh `template_hashes`; update component statuses; append to `syncs:`
history — `{date, drift_found: [axes], applied: [...], skipped: [...]}` — so the next sync
(and the user) can see what happened last time.

## Step 5 — Report
Applied / skipped / still-pending-manual, one line each. Deferred low-confidence detections
go at the end (same convention as `/harness-scan`) so they resurface next run.
