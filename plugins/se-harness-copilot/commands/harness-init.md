---
description: Bootstrap the AI harness for this project — interview (new) or detect+confirm (existing), then generate profile, env, memory scaffold, org rules, and AGENTS.md/CLAUDE.md.
argument-hint: [--update]
---

# /harness-init — project intake & bootstrap

Set up the se-harness around the current repository. Interview the user, then generate all
per-project artifacts. **Idempotent**: re-running updates only generated content, never
hand-written files.

## Step 0 — Guard
If `.harness/profile.yaml` already exists and `$ARGUMENTS` does not contain `--update`:
show the existing profile summary and ask whether to update it or abort. Never silently
re-initialize.

## Step 0a — Make sure the harness scripts are reachable
Every step below runs a script at `tools/harness/<script>.sh`. On Copilot that
path is a repo-vendored convention (`docs/setup-guide-copilot.md` Part 1.3/4.7): it only
resolves once the scripts have actually been copied into this directory, which nothing does
automatically. Check once, up front, instead of letting an arbitrary later step fail:

1. Check whether `tools/harness/workspace-clone.sh` exists as a real file.
   - **Exists** → nothing else in this step applies; continue to Step 1.
   - **Missing** → locate where the plugin itself is actually installed and vendor from there,
     trying each of these in order, stopping at the first that finds something:
     a. The Copilot/VS Code plugin cache. Run:
        `find ~/.vscode/agent-plugins -type d -path '*/plugins/se-harness-copilot/scripts' 2>/dev/null`
        (this is `<host>/<org>/<repo>/plugins/se-harness-copilot/scripts/` under
        `~/.vscode/agent-plugins/` — confirmed present there after a normal
        `copilot plugin install`).
        - **One match** → vendor: `mkdir -p tools/harness && cp <that match>/*.sh tools/harness/`.
          Tell the user you did this, then continue to Step 1.
        - **Multiple matches** (e.g. both a public and an internal-mirror install) → list them
          and ask the user which one via AskUserQuestion — never guess.
        - **None** → try (b).
     b. A sibling framework checkout at `../se-harness/` (the side-by-side clone the setup
        guides document) → if found, vendor
        `../se-harness/plugins/se-harness-copilot/scripts/*.sh` the same way; else try (c).
     c. Neither found → stop. Tell the user plainly: the scripts this command needs aren't
        vendored here and couldn't be found automatically. Give both options, let them pick:
        (a) check their own `~/.vscode/agent-plugins/` for the install themselves (path layout
        above) and point you at it, or (b) `git clone <se-harness repo url> se-harness` right
        here as a sibling, then re-run this command — this also covers the
        `templates/`/`registry/` references used later. Never guess at an install path.

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
4. Ask once (AskUserQuestion): **bootstrap every cloned repo now too** (recommended — go to
   Step 1b), or **leave them cloned** and the user will run `/harness-init` in each one
   themselves later (valid; stop here — this step never writes `.harness/profile.yaml` itself).

### Step 1b — Bootstrap every cloned unit in one pass (opt-in, from Step 1a point 4)
This replaces 20 separate `/harness-init` invocations with one: you drive Steps 2-8 yourself,
once per unit, inside this same run. Tell the user up front this may take a while for a large
workspace and that you'll report progress as you go.

1. **Create `workspace.yaml` now, with the shared choices made once** — don't wait for Step 3
   inside some later unit to ask this; asking it here first means every unit in the loop below
   inherits silently instead of asking the same question 20 times:
   - `topology: multi-repo`, `units:` from `repos.txt` (`repo:` form, `stack: []` until a unit
     is actually bootstrapped below).
   - **Methodology** — same options and wording as Step 4 point 1 — ask once, write to
     `shared.methodology`.
   - **Structural memory** — same options and wording as Step 6 — ask once, write to
     `shared.memory.structural_driver` (`null`/defer is a valid answer).
   - **Shared org context** — same questions as Step 5, scoped to whatever's genuinely common
     across units (a shared internal UI library, a company-wide banned-library rule) — ask
     once, write to `shared.org`. Repo-specific additions still get asked per unit in the loop
     below; this only captures what's common.
   - Validate with `bash tools/harness/workspace-validate.sh workspace.yaml`
     before continuing.
2. **Workspace-level memory** — distinct from any one unit's own `.harness/memory/`; this is
   for decisions that span the whole product, starting with the choices just made. Create
   `.harness/memory/{MEMORY.md,SCRATCHPAD.md,daily/.gitkeep,wiki/index.md,wiki/log.md}` at the
   workspace root, same templates as Step 7 point 4, and log today's methodology/
   structural-memory/org decisions as the first daily entry.
3. **Loop.** For each unit, in order: `cd` into it and run Steps 2 through 8 of this same
   command, directly — you're already running the command, so continue the flow yourself
   rather than telling the user to re-invoke it. Steps 4-6's inheritance logic now finds
   everything already set in `workspace.yaml` from point 1, so each unit asks **only** what's
   genuinely unit-specific (stack details `/harness-scan` can't detect, DevOps/cloud target,
   libraries unique to that unit). If a unit has nothing left to ask, say so and go straight to
   Step 7 for it — don't manufacture a question to fill the slot. A unit that fails (directory
   missing, detection error) gets reported and skipped; it never aborts the remaining units.
4. **Finalize.** Once every unit has a real `.harness/profile.yaml`, update
   `workspace.yaml`'s `units[].stack` from what each unit actually detected, re-validate, and
   report one table: unit | bootstrapped? | stack | methodology | structural_driver | notes.
   Tell the user `/harness-bootstrap` is still **per-repo** (installs are repo-level artifacts)
   — run it in whichever unit they want companion tools installed first; its own Step 1 already
   reads `shared.memory.structural_driver` and the methodology choice from `workspace.yaml`, so
   it won't ask again.

## Step 2 — New or existing?
Look at the repo (any source files beyond scaffolding?). Propose your conclusion and confirm
with the user via AskUserQuestion — don't assume.

## Step 3 — Topology
Check for workspace markers: `pnpm-workspace.yaml`, `nx.json`, `turbo.json`, `lerna.json`,
`*.sln`, Maven multi-module `pom.xml` (`<modules>`), `go.work`, `WORKSPACE`/`MODULE.bazel` —
**or**, absent all of those, **two or more sibling directories, each with its own independent
build manifest** (`package.json`, `pom.xml`, `build.gradle`/`build.gradle.kts`, `go.mod`,
`Cargo.toml`, `*.csproj`, ...) **and no root-level aggregator of the same kind**. This second
signal matters: a real mono-repo found this way during a live trial (three sibling services,
no `nx.json`/`turbo.json`/root `pom.xml`, nothing formal at all) — relying on the formal-tool
list alone would have missed it and fallen through to "single," which is wrong. The signal is
weaker than a formal marker, so it still gets proposed and confirmed, never concluded silently
either way (principle 3) — list which manifest identified each sibling directory as part of
the evidence you present.

- **Either signal found** → propose **mono-repo**, list detected units (name each sibling
  directory and the manifest/marker that identified it), confirm. Create
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

**Workspace inheritance first** (workspace-orchestration plan §3.2, phase 3): methodology and
non-code sources default to **workspace** scope; stack and DevOps/cloud stay **repo** scope by
design (local facts, never inherited). Look for `workspace.yaml` or `../workspace.yaml` (same
lookup `contract-check.sh`/`workspace-validate.sh` use). If found, read `shared.methodology`
and `shared.jira_project`/`shared.confluence_spaces`/`shared.sharepoint_sites`:
- Any already set → **inherit silently**, tell the user what was inherited, skip asking about
  it below.
- Any empty/missing → ask as usual (below). After the user answers, offer to write it back
  into the workspace manifest's `shared:` block so every other unit in this workspace inherits
  it too — confirm first (it's a file outside this repo), then
  `bash tools/harness/workspace-validate.sh <that workspace.yaml>` before
  reporting success.

Ask only what wasn't detected and isn't already inherited. Cover:
1. **Methodology** (workspace-scoped by default): BMAD (roles/stakeholders, enterprise) /
   Spec Kit (greenfield, spec-first) / OpenSpec (brownfield, delta-based). Recommend based on
   project type; user decides. If this repo's choice **deviates** from an inherited workspace
   default, that's a documented exception: record it as an inline comment next to
   `methodology:` in this repo's `profile.yaml` (e.g. `methodology: bmad   # workspace default
   is openspec — deviates because <reason>`), never a silent divergence.
2. **Stack** — *new projects only* (existing projects get this from `/harness-scan`):
   offer presets first — `Python (FastAPI + Postgres)`, `Node + React (Express/Postgres/Redis)`,
   `Node + Angular`, `Other (specify)` — then confirm databases/messaging/devops details.
3. **DevOps + cloud**: CI system, container approach (default docker-compose), cloud target
   (aws / azure / gcp / vercel / none-yet).
4. **Non-code sources** (workspace-scoped by default): Jira project key, Confluence space keys,
   SharePoint sites (each optional — record "" when not used).

## Step 5 — Organization context (required before AGENTS.md/CLAUDE.md is finalized)

**Workspace inheritance first** (same lookup and write-back pattern as Step 4): if
`shared.org` in the workspace manifest already has `internal_libraries`/`preferred_libraries`/
`conventions`, inherit them and tell the user what was inherited — skip asking about anything
already covered. Ask only about what's missing, then offer to write new answers back into
`shared.org` (confirm first) so later repos inherit them too.

Ask explicitly — for new projects this is the only source; for existing projects collect what
the user knows now (Phase 2 `/harness-scan` will verify/extend it):
1. **Internal libraries** the company built (name, registry/scope, purpose) — these become
   *generation targets* (compose-first), not just context.
2. **Preferred/mandated libraries** — "use X, never Y" pairs with reasons.
3. **Coding conventions/guidelines** — inline rules and/or a Confluence/SharePoint URL
   (the wiki-ingest skill will pull the URL's content into domain memory later).
None of these are required — record empty lists if the org has none; don't nag.

## Step 6 — Structural memory (tier 1 only — workspace-orchestration plan §4.5)

This step records a **choice**, never an installation — running the actual installer (e.g.
`uv tool install graphifyy`) is `/harness-bootstrap`'s job, not init's; init never executes
third-party code. It also touches **tier 1 only**. Tiers 2 (session log) and 3 (domain wiki)
are always plain markdown under `.harness/memory/`, at every topology — nothing here changes
that; Step 7's memory scaffold below is unconditional and identical regardless of this choice.

**Workspace inheritance first** (same lookup and write-back pattern as Steps 4-5): if
`shared.memory.structural_driver` in the workspace manifest is already set (non-null), inherit
it silently, tell the user what was inherited, and skip the question below.

Otherwise, ask once: offer the `memory.structural.choose_one` list from
`registry/recommendations.json` (currently CodeGraph — two unrelated repos, disambiguate by
URL, not name — codebase-memory-mcp, or Graphify), summarizing each option's tradeoff from the
registry's `note` field in a sentence or two, plus an explicit **defer** choice (valid; this is
an open bake-off, not a requirement — don't nag about it later). Record the answer:
- **Workspace exists** → write it to `shared.memory.structural_driver` in the workspace
  manifest (confirm first, it's a file outside this repo) so every unit inherits the same
  choice; echo it into this repo's `profile.yaml` too (`memory.structural_driver`) for local
  visibility.
- **No workspace** (single repo) → write directly to this repo's `profile.yaml`
  (`memory.structural_driver`).

A deferred choice is recorded as `null`, not skipped silently — `/harness-bootstrap` and
`/harness-scan` both check this field before falling back to asking or probing generically.

## Step 7 — Generate artifacts
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
   cloud, topology, `memory.structural_driver`), `components: {}` (Phase 3 fills this).

## Step 8 — Report & next steps
Summarize what was created vs. skipped (already existed). Then:
- **Existing project** → "run `/harness-scan` to detect stack/devops/org conventions from the
  code" (Phase 2 — if not yet available, say so and note the profile can be completed manually).
- Both → next: Phase 3 bootstrap (methodology + stack plugins + the structural-memory driver
  chosen in Step 6, if any), then `/harness-goal <goal>`.
- Remind: fill `.env.harness`, commit `.harness/` + AGENTS.md/CLAUDE.md, DON'T commit `.env.harness`.
