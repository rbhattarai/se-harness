---
description: Capture this repo's coding conventions and internal-library usage as per-area convention docs (angular, dotnet, e2e-playwright, db, ...) the agents load before writing code. Detect → draft → confirm each rule → write. Re-runnable; flags stale docs.
argument-hint: [area ...] [--refresh] [--export-copilot]
---

# /harness-conventions — turn "how we write code here" into enforced, scoped rules

`/harness-scan` finds *facts* (stack, libraries, lint configs). This command turns those facts,
the code itself, and the internal libraries' own sources into **convention docs** under
`.harness/conventions/` that every implementer, tester and reviewer agent loads before touching
matching files. The agents stay generic; the project-specific knowledge is *data* here, so a
plugin update never clobbers it.

Read-only until the user confirms. **No rule is written without being accepted.** Never invent a
standard: where the code is inconsistent, ask which one is the standard.

`$ARGUMENTS`: area names to limit the run (e.g. `angular e2e-playwright`); `--refresh` re-checks
existing docs for staleness and proposes diffs instead of redrafting; `--export-copilot` also
runs Step 6.

## Step 0 — Guard
Needs `.harness/profile.yaml` (else: run `/harness-init` first, stop). At a **workspace root**
(`workspace.yaml`, no local profile) work unit by unit, **internal-library units first** so the
app units can reuse their catalogs.

### Workspace ↔ unit docs (how they stay in sync)
- **Two scopes.** `scope: workspace` docs describe something several units share (an internal
  library's catalog and usage rules, org-wide rules) and live once at
  `<workspace-root>/.harness/conventions/<area>.md`. `scope: repo` docs describe one unit and live
  in that unit's own `.harness/conventions/`. A library's catalog is workspace scope even when
  the library is itself one of the units.
- **Index.** Workspace docs are listed in `workspace.yaml` → `shared.org.convention_docs`
  (path relative to the manifest). Each unit's `org.convention_docs` lists them too, with
  `scope: workspace` and the path **rewritten relative to that unit** (side-by-side repos:
  `../.harness/conventions/lib-ui.md`; mono-repo unit at `packages/web`:
  `../../.harness/conventions/lib-ui.md`). That per-unit entry is what AGENTS.md renders and what
  agents and `/harness-goal` read, so a unit always works from one flat, correct list.
- **Precedence.** A unit-scope doc with the same `area` as a workspace doc overrides it for that
  unit only; say so in the doc's frontmatter (`overrides: workspace`). Never edit a workspace doc
  from inside a unit run without saying that every unit is affected.
- **Propagation.** Whenever a workspace doc is added, changed in status, or removed, update
  `shared.org.convention_docs`, validate with `workspace-validate.sh`, then add/refresh the
  inherited entry in **every** bootstrapped unit's profile and re-render each unit's AGENTS.md /
  CLAUDE.md block (Step 4.4). Units not bootstrapped yet pick the entries up at their `/harness-init`
  (Step 5 inheritance). `/harness-sync` re-checks this drift later.

## Where these docs are used
Writing them is only useful because the rest of the harness reads them. Everywhere they are consumed:
- **AGENTS.md / CLAUDE.md** — the generated "Convention docs" index (area, path, `applies_to`, status).
- **All nine implementer/tester/architect agents** — read the matching doc before writing or
  reviewing code (`implementer-frontend`, `implementer-backend`, `db-engineer`, `unit-tester`,
  `integration-tester`, `e2e-planner`, `e2e-generator`, `e2e-healer`, `architect`).
- **`/harness-goal`** — step 0a preflight (loads confirmed docs, offers this command for missing or
  stale ones), step 5 delegation (names the matching docs for each task), the automated gate
  (convention review of the diff against MUST rules and the catalog), and the PR evidence table.
- **`/harness-scan`** — reports existing instruction files and library sources as evidence for this
  command; suggests running it afterwards.
- **`/harness-init` and `/harness-bootstrap`** — init's report and bootstrap's Step 4b / "Next
  commands" point here; bootstrap can run it inline.
- **`/harness-sync`** — axis E: keeps the workspace↔unit index consistent and flags stale docs.
- **Copilot** — Step 6 exports them to `.github/instructions/*.instructions.md`.

## Step 1 — Collect evidence (read-only)
1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/scan-evidence.sh .` — includes the **EXISTING AI
   INSTRUCTION FILES** and **INTERNAL LIBRARY SOURCES** sections.
2. **Existing instruction files — optional.** A repo may have none, one or several
   (`.github/copilot-instructions.md`, `*-copilot-instructions.md`,
   `.github/instructions/*.instructions.md`, `CLAUDE.md`, `.cursorrules`, hand-written parts of
   `AGENTS.md`), depending on whether anyone ran `/init` or wrote them. **None is the normal case**:
   proceed straight to the next point without asking about them, mentioning them or treating their
   absence as a gap. If some exist, read them as *input*, not competitors; each rule becomes a
   candidate with `source: existing-instructions`. Generated harness blocks (SEAA markers) are skipped.
3. **Internal libraries** (`org.internal_libraries` in the profile plus whatever the scan
   found): locate each library's source, in this order — a sibling repo in the workspace, the
   installed package (`node_modules/<scope>/<pkg>`, NuGet cache, site-packages), then its
   README/Storybook/docs URL. From it extract the **public surface**: exported components,
   services, helpers, testing utilities — name, import path, one-line purpose, a minimal usage
   example. If a library's source is unreachable, say so and record the library as
   `catalog: unavailable` — never guess an API from its name.
4. **Usage mining**: per library, what do consumers actually call? (top imports by frequency, the
   typical call shape). A symbol imported in 30 files is the library's de-facto API.
5. **Code sampling per area**: pick 5-10 representative files per area (prefer recently
   modified, well-tested ones) and read them for implicit conventions: layering, error handling,
   naming, state management, test structure, fixture/page-object patterns, DB migration style.
   If the structural driver (Graphify etc.) is available, use it to pick representative files;
   it is optional.

## Step 2 — Decide the areas
Propose areas from the stack and structure; the user confirms the list. Typical:
`angular`, `dotnet`, `python`, `e2e-playwright`, `db-mssql`, `devops-config`, plus one
`lib-<name>` per internal library worth a catalog. Each area gets `applies_to` globs (e.g.
`**/*.component.ts`, `e2e/**`, `**/*.sql`). One area = one doc = ~100 lines max; split rather
than grow. Skip areas with no code.

## Step 3 — Draft each doc, then confirm rule by rule
Render `${CLAUDE_PLUGIN_ROOT}/templates/conventions.md` per area. Every rule needs:
a level (**MUST** = enforced / **SHOULD** = default), evidence (file, config, or
`source: org-guideline`), and confidence.

- **High-confidence** (stated in a lint config, existing instruction file, or library README, and
  consistent in code): present as a table, bulk-confirm.
- **Inferred from code only, or inconsistent** (two date libraries, two test layouts): ask one at
  a time via AskUserQuestion — accept / reject / edit, and for inconsistencies *which is the
  standard*. Record unresolved ones under **Open questions** in the doc; do not pick silently.
- **No convention exists at all for an area** (greenfield or never written down): say so, offer
  the inferred candidates as a starting draft, and invite the user's own rules. The doc is saved
  with `status: draft` until the user has confirmed it.
- Invite what the code can't show: unwritten team rules, upcoming migrations ("new code must use
  signals, old code is being migrated").
- The doc's **Library catalog** lists, per internal library, "use this for X → symbol, import
  path, example", most-used first. Anything the code hand-rolls that a catalog entry already
  covers is a candidate *anti-pattern* — propose it, with the file as evidence.
- **Golden examples**: 1-3 real files per area that exemplify the conventions (path only, never
  copied code). Agents read these instead of imitating the nearest file.

## Step 4 — Write (only after confirmation)
1. `.harness/conventions/<area>.md` — frontmatter per the template (`area`, `status`,
   `applies_to`, `libraries` with versions, `evidence_hash`, `updated`). Existing hand-written
   docs are never overwritten: for `--refresh` show a diff and ask keep / take / merge.
2. `.harness/profile.yaml` → `org.convention_docs`: one entry per doc
   `{ area, path, applies_to, status, scope }`. Existing user values win. For a
   `scope: workspace` doc also write `workspace.yaml` → `shared.org.convention_docs` and propagate
   to every bootstrapped unit's profile as described under *Workspace ↔ unit docs*.
3. `.harness/org-rules.txt` — append `banned:` lines for every accepted anti-pattern that is a
   bare import (same format `/harness-scan` writes); never drop lines already there.
4. AGENTS.md / CLAUDE.md — re-render the inner blocks from the updated profile and splice with
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/render-block.sh <target> <block-file>` (the template
   emits the convention index: area, path, applies_to — pointers only, never the rules). Handle
   exit code 3 exactly as `/harness-scan` Step 4 does.
5. `.harness/agentstack.lock` — set `updated`, append a `conventions:` entry (date, areas,
   statuses).
6. Only if existing instruction files were found in Step 1 and now duplicate a confirmed doc: do
   not delete or edit them. List them in the report and suggest replacing their body with a pointer
   to `.harness/conventions/<area>.md`, or running Step 6, so there is one source of truth. If there
   were none, skip this point silently.

## Step 5 — Staleness (`--refresh`, and every run)
For each existing doc compare against the recorded frontmatter: library major/minor version
changed, lint/format config hash changed, `applies_to` now matches new top-level folders, a
catalog symbol no longer exported. Mark the doc `status: stale` with the reason and propose the
specific rule edits — don't redraft wholesale. `/harness-scan` calls this check and only reports.

## Step 6 — Copilot export (`--export-copilot`, or offered when the surface is Copilot)
For each confirmed doc write `.github/instructions/<area>.instructions.md` with
`applyTo: "<applies_to globs, comma-separated>"` frontmatter and the doc body, preceded by a
`<!-- generated from .harness/conventions/<area>.md — edit that file, not this one -->` line.
Skip files that exist without that marker (hand-written) and list them instead.

## Step 7 — Report
Per area: status, rule counts (MUST/SHOULD), libraries catalogued vs `unavailable`, open
questions, stale docs, duplicate instruction files found. Next steps: commit
`.harness/conventions/`; run `/harness-goal`. Agents and the PR gate now use these docs.
