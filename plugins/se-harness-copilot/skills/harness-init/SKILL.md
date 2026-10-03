---
name: harness-init
description: Bootstrap the AI harness for this project — interview (new) or detect+confirm (existing), then generate profile, env, memory scaffold, org rules, and AGENTS.md/CLAUDE.md.
---


# /harness-init — project intake & bootstrap

Set up the se-harness around the current repository. Interview the user, then generate all
per-project artifacts. **Idempotent**: re-running updates only generated content, never
hand-written files.

## Step 0 — Guard
If `.harness/profile.yaml` already exists and `$ARGUMENTS` does not contain `--update`:
show the existing profile summary and ask whether to update it or abort. Never silently
re-initialize.

## Step 1 — Detect the setup target (workspace-orchestration plan §4.1)
Run `git rev-parse --is-inside-work-tree`.
- **Inside a git repo** → this is the existing, unchanged per-repo path. Continue at Step 2.
- **Not inside a git repo** → this directory is a candidate **workspace root**, not a repo to
  bootstrap directly. Offer workspace-level setup instead of silently treating it as a new
  single-repo project:
  1. Look for `repos.txt` in the current directory (one repo per line: `<git-url>` or
     `<name>=<git-url>` — same format `scripts/workspace-clone.sh` reads).
     - **Found** → this is the bootstrap inventory. Go to Step 1a.
     - **Not found** → ask: provide repo URLs now (write them to `repos.txt` in the format
       above, one per line, then go to Step 1a), or "I'll clone manually" (point at the
       existing documented side-by-side-clone flow in the setup guides, then stop — nothing
       else in this step applies).
  2. Cloning is **never automatic**. If the user wants it, continue; if not, stop here —
     `repos.txt` alone is a valid, harmless artifact to leave in place.

### Step 1a — Opt-in, confirmed clone (only when the user wants it)
1. Run `bash tools/harness/workspace-clone.sh plan repos.txt .` and show the
   table verbatim — name, status (`missing` / `matches` / `collision`), destination, source URL.
   This never touches disk.
2. **Confirm before acting**: if every row is `missing`, ask once for the whole batch
   (AskUserQuestion). If any row is `collision`, call it out by name and ask per-repo whether
   to skip it (default) or that the user will resolve it manually first — never ask to
   overwrite, that option doesn't exist.
3. Run `bash tools/harness/workspace-clone.sh apply repos.txt .` for the
   confirmed names only (pass them as trailing arguments; omit them to apply every entry if
   the whole batch was confirmed). Report exactly what the script reported — cloned, skipped
   (already present), skipped (collision, not touched), or failed — per repo. A `collision` or
   a failed clone never blocks the repos that succeeded.
4. Tell the user: workspace repos are in place; run `/harness-init` again **inside each one**
   to bootstrap it — starting with whichever repo is most central (ask, or suggest the one
   with the most inbound dependencies if that's evident). This step never writes
   `.harness/profile.yaml` itself; each repo still gets its own full Step 2+ pass.

## Step 2 — New or existing?
Look at the repo (any source files beyond scaffolding?). Propose your conclusion and confirm
with the user via AskUserQuestion — don't assume.

## Step 3 — Topology
Check for workspace markers: `pnpm-workspace.yaml`, `nx.json`, `turbo.json`, `lerna.json`,
`*.sln`, Maven multi-module `pom.xml` (`<modules>`), `go.work`, `WORKSPACE`/`MODULE.bazel`.

- **Markers found** → propose **mono-repo**, list detected units, confirm. Create
  `workspace.yaml` at the repo root from `templates/workspace.yaml` (units with `path:`, one
  per detected unit).
  - Then look for cross-unit relationships with real evidence — a unit's manifest depending on
    another unit's package name, an import crossing unit directories, a `depends_on` in a
    workspace-level compose file. Propose each as a `components:`/`relationships:` entry
    (schemaVersion 2, additive — see `templates/workspace.yaml`'s commented example) **only
    with the evidence attached**; a relationship you can't cite stays an open question you
    mention in the report, never a written entry (§3.1 — no evidence, no relationship). Confirm
    the whole proposed list with the user before writing it; validate with
    `bash tools/harness/workspace-validate.sh workspace.yaml` before reporting
    success.
- **No markers, but internal module structure is evident** (Spring Modulith
  `@ApplicationModule`/`spring-modulith` dependency, NestJS feature folders each with their own
  `@Module()`, Django-style `INSTALLED_APPS` per-app folders, a `src/modules/`-or-`src/domains/`
  convention, or similar) → this is a **modulith candidate**, not proof of one. Ask explicitly:
  *"This looks like it's organized into internal modules (evidence: ...). Is this one deployable
  app with internal module boundaries, or should I treat it as a plain single repo?"* Directory
  structure is a clue, never a silent conclusion (principle 3). If confirmed: `topology:
  modulith`, one `unit` (`path: .`), and propose `components:` (`kind: module`) for each
  detected module plus any evidenced `relationships:` between them — same confirm-before-write
  and `workspace-validate.sh` check as above.
- Ask whether this repo is part of a **multi-repo product** (sibling repos forming one system).
  If yes: record the workspace meta-repo URL in the profile; if no meta-repo exists yet, offer
  to generate `workspace.yaml` from the template (units with `repo:`) for the user to place in
  a meta-repo. Ask about **contracts** (OpenAPI/proto/event schemas this repo provides or
  consumes) and fill the `contracts:` section — it powers the contract-check hook. If this repo
  *also* has mono-repo or modulith structure confirmed above, `topology:` is **hybrid**, not
  mono-repo or multi-repo alone — both halves of the manifest apply.
- Otherwise → **single** (no workspace.yaml needed).

## Step 4 — Interview (AskUserQuestion, batch related questions, max 4 per call)
Ask only what wasn't detected. Cover:
1. **Methodology**: BMAD (roles/stakeholders, enterprise) / Spec Kit (greenfield, spec-first) /
   OpenSpec (brownfield, delta-based). Recommend based on project type; user decides.
2. **Stack** — *new projects only* (existing projects get this from `/harness-scan`):
   offer presets first — `Python (FastAPI + Postgres)`, `Node + React (Express/Postgres/Redis)`,
   `Node + Angular`, `Other (specify)` — then confirm databases/messaging/devops details.
3. **DevOps + cloud**: CI system, container approach (default docker-compose), cloud target
   (aws / azure / gcp / vercel / none-yet).
4. **Non-code sources**: Jira project key, Confluence space keys, SharePoint sites (each
   optional — record "" when not used).

## Step 5 — Organization context (required before AGENTS.md/CLAUDE.md is finalized)
Ask explicitly — for new projects this is the only source; for existing projects collect what
the user knows now (Phase 2 `/harness-scan` will verify/extend it):
1. **Internal libraries** the company built (name, registry/scope, purpose) — these become
   *generation targets* (compose-first), not just context.
2. **Preferred/mandated libraries** — "use X, never Y" pairs with reasons.
3. **Coding conventions/guidelines** — inline rules and/or a Confluence/SharePoint URL
   (the wiki-ingest skill will pull the URL's content into domain memory later).
None of these are required — record empty lists if the org has none; don't nag.

## Step 6 — Generate artifacts
Order matters; use the exact mechanics below.

1. **`.harness/profile.yaml`** — render from `../se-harness/templates/profile.yaml`
   with all interview answers. Never put secrets here.
2. **`.env.harness`** — copy `templates/env.harness.example` **only if `.env.harness` doesn't
   already exist**; leave existing files untouched. Tell the user which vars to fill for the
   sources they named.
3. **`.gitignore`** — append each line of `templates/gitignore.harness` that isn't already
   present (grep before append; create `.gitignore` if missing).
4. **Memory scaffold** (skip any file that already exists):
   ```
   .harness/memory/MEMORY.md        (from templates/memory/MEMORY.md)
   .harness/memory/SCRATCHPAD.md    (from templates/memory/SCRATCHPAD.md)
   .harness/memory/daily/           (empty dir, .gitkeep)
   .harness/memory/wiki/index.md    (from templates/memory/wiki-index.md)
   .harness/memory/wiki/log.md      (from templates/memory/wiki-log.md)
   .harness/requirements/           (empty dir, .gitkeep)
   ```
5. **`.harness/org-rules.txt`** — one line per banned pair from the org answers:
   `banned:<never>:use <use> (<reason>)`. Empty file if none (the org-validate hook no-ops).
6. **AGENTS.md and CLAUDE.md** — render the *inner* content of
   `templates/AGENTS.md.tmpl` / `templates/CLAUDE.md.tmpl` (fill every `{{placeholder}}` from
   the profile; drop sections whose data is empty; **do not include the marker lines** — the
   splice script owns them). Write each rendered block to a temp file, then:
   ```
   bash tools/harness/render-block.sh AGENTS.md <temp-agents-block>
   bash tools/harness/render-block.sh CLAUDE.md <temp-claude-block>
   ```
   This is the ONLY way to touch these files — never edit them directly, so hand-written
   content outside the markers survives.
7. **`.harness/agentstack.lock`** — JSON: `se_harness` version (from plugin.json),
   `initialized`/`updated` ISO dates, `profile` echo of key choices (methodology, stack,
   cloud, topology), `components: {}` (Phase 3 fills this).

## Step 7 — Report & next steps
Summarize what was created vs. skipped (already existed). Then:
- **Existing project** → "run `/harness-scan` to detect stack/devops/org conventions from the
  code" (Phase 2 — if not yet available, say so and note the profile can be completed manually).
- Both → next: Phase 3 bootstrap (methodology + stack plugins), then `/harness-goal <goal>`.
- Remind: fill `.env.harness`, commit `.harness/` + AGENTS.md/CLAUDE.md, DON'T commit `.env.harness`.
