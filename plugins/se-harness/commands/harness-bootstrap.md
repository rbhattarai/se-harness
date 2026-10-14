---
description: Recommend and install the harness components matching this project's profile — methodology, stack plugins, MCP servers, observability — opt-in per item, recorded in the lockfile. `--reconfigure <topic>` revisits an earlier choice (observability, memory, methodology).
argument-hint: [--dry-run] [--reconfigure <observability|memory|methodology>]
---

# /harness-bootstrap — Phase 3 generator

Turn the profile into an installed harness. **Composable, opt-in** (the ECC lesson: users
cherry-pick; never install everything). Read `--dry-run` from `$ARGUMENTS`: if present, produce
the recommendation manifest and stop before installing anything. `--reconfigure <topic>` in
`$ARGUMENTS` → skip the manifest entirely and go to **Reconfigure mode** (after Step 0).

## Step 0 — Guard & workspace scope
`.harness/profile.yaml` in the current directory → normal per-repo run, continue at Step 1,
nothing below applies. Missing, but `workspace.yaml` or `repos.txt` is present instead → this
is a **workspace root**, not a repo to bootstrap directly:

1. Ask once (AskUserQuestion): run across **every** declared/listed unit that's already
   bootstrapped (has its own `.harness/profile.yaml`), **specific units** (name them), or let
   you **suggest** units — propose any unit with a profile but an empty `components:` in its
   `.harness/agentstack.lock` (never bootstrapped) or a `pending-manual` status worth
   re-checking, and confirm the proposed list before proceeding. Never default to "every unit"
   without asking.
2. Skip and report any listed unit that has no `.harness/profile.yaml` yet — point at
   `/harness-init` for it; never attempt to bootstrap an un-initialized unit.
3. For each chosen unit, in order: `cd` into it and run Steps 1-6 of this same command,
   directly — same "continue the flow yourself" approach as `/harness-init` Step 1b. Each
   unit's recommendation manifest is its own (stack-driven) — unlike `/harness-init`'s
   methodology/structural-memory choices, nothing here is shared across units, so there's no
   "ask once" shortcut; Step 2's selection still happens per unit.
4. Once every chosen unit is done, report one consolidated table across all of them — unit |
   installed | pending-manual | declined — in addition to each unit's own Step 6 report.

Neither `.harness/profile.yaml` nor a workspace manifest/inventory present → tell the user to
run `/harness-init` first and stop.

## Reconfigure mode — `--reconfigure <topic>`
Revisit a choice made earlier without re-running anything else. Topics: `observability`,
`memory` (the structural-memory driver), `methodology`. No/unknown topic → list the three and
stop. Only that topic's profile fields and components are touched — never the rest of the manifest.

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/decision-review.sh` and show the topic's row in words:
   "**Currently:** Langfuse @ http://localhost:3000 — configured 2026-10-13" (or `declined`,
   `deferred`, `unset`). If it reports `missing: …`, name the missing variables (names only; never
   read or print a secret value) — that is often the whole reason for reconfiguring.
2. Ask (AskUserQuestion): **Keep it** / **Change it** (list the registry's alternatives, current one
   marked) / **Turn it off** (`declined`) / **Decide later** (`deferred`). Keep → say so and stop.
3. Change, by topic:
   - **observability** → run **Observability setup** below with the new provider. If it replaces
     an installed provider, say the old plugin stays installed (propose the removal command, never
     run it).
   - **memory** → write `memory.structural_driver` (and `shared.memory.structural_driver` if the
     user wants the workspace default changed); Graphify → hand off to `/harness-mem-graphify`,
     others → this command's Step 3 install for that one driver.
   - **methodology** → write `methodology` (a value that differs from the workspace default gets
     the trailing "documented exception" comment); OpenSpec → hand off to
     `/harness-methodology-openspec`. Remind that only se-harness (built-in) and OpenSpec are
     delegated to by `/harness-goal`.
4. At a workspace root (no `.harness/profile.yaml`, but `workspace.yaml`): change the `shared:`
   value once, then list any unit whose own profile deviates (they keep theirs unless the user
   says otherwise) — don't loop every unit.
5. Re-render AGENTS.md/CLAUDE.md blocks (Step 4 item 4, including the exit-3 hand-edit rule), then
   record in the lockfile (Step 5) and report (Step 6). `--dry-run` → show what would change and stop.

## Observability setup
Shared by Step 2 and Reconfigure mode; `<p>` = the chosen entry in the registry's
`observability.providers`.
1. **Host** (non-secret). Offer `<p>.host_default` first (for Langfuse: the self-hosted default),
   then the `host_note` alternatives, then "other URL". Dash0/other: ask for the endpoint if
   the plugin needs one.
2. **Record the decision** in `.harness/profile.yaml` (and `shared.observability` if the user
   agreed): `observability: {status: configured, provider: <p>, host: <host>, decided: <today>}`.
3. **Secrets stay out of chat and out of git.** For each name in `<p>.env_secret`, make sure
   `.env.harness` (the workspace root's when the choice is shared, else this repo's — create it from
   the matching template if missing) has an empty `NAME=` line — append only, never touch existing
   values. Tell the user where to create the keys (Langfuse: project settings → API keys) and to fill
   them in themselves. Never ask them to paste a key here.
4. **Install** per `<p>.kind`: `plugin` → Step 3's plugin mechanics. The registry marks these names
   `verified: false`: say so, and if `claude plugin install` fails, record `pending-manual` and
   point at `/plugin` rather than guessing a marketplace. `manual` → nothing to install.
5. **Optional reachability check** (non-fatal): if `<p>.health_path` exists and the host is local
   (`localhost`/`127.0.0.1`), offer `curl -s -o /dev/null -w "%{http_code}" <host><health_path>` —
   200 means the server is up. Skip remote hosts unless the user opts in (it's a network call).
6. Lockfile: component `<p>.plugin` with its status.

## Step 1 — Build the recommendation manifest
Read `.harness/profile.yaml` (guard: must exist — run `/harness-init` first) and
`${CLAUDE_PLUGIN_ROOT}/registry/recommendations.json`. Map profile → components:

- `methodology` → its entry (plugin or CLI install) — `se-harness` ("se-harness (built-in)" to
  the user) has a `kind: native` registry entry, nothing to install; skip it silently, no
  manifest row
- each `stack.*` value → its `plugins` list (skip entries with empty lists; surface their
  `note` so the user knows why nothing is recommended)
- `cloud` → its plugins
- `always` + `testing.e2e` → recommended for every project
- `observability` → run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/decision-review.sh` and read its
  `observability` row (it resolves this repo's profile, then the workspace default). Never ask a
  question that was already answered:
  - `configured` → no question. Add that provider's `observability.providers.<provider>` entry to
    the manifest, labeled "chosen earlier (<decided date>)", and say the choice can be changed
    with `--reconfigure observability`.
  - `declined` → skip silently; one line in the Step 6 report: "observability: declined on
    <date> — `/harness-bootstrap --reconfigure observability` to change".
  - `unset` or `deferred` → ask once via AskUserQuestion: **Langfuse** / **Dash0** / **Another
    backend** / **Not yet** (records `deferred` — `/harness-sync` asks again) / **No thanks**
    (records `declined` — never re-asked). Run **Observability setup** below for a provider; for
    the last two just record the status in `profile.yaml`'s `observability:` block with today's
    date. If a workspace manifest exists, offer once to write the answer to
    `shared.observability` so every unit inherits it (same scoped-configuration rule as
    `/harness-init`'s methodology choice).
- `sources`: Jira/Confluence set → `atlassian`; GitHub remote detected → `github`;
  `org.conventions_url` on Figma-backed design orgs → `figma`
- `memory.structural` → first check `profile.yaml`'s `memory.structural_driver` (and
  `workspace.yaml`'s `shared.memory.structural_driver` if a workspace manifest exists) — if
  `/harness-init` Step 6 already recorded a non-null choice, skip the question entirely and
  add that one driver's install command straight to the manifest as `kind: cli`, labeled
  "chosen at init." Only if it's still `null`/unset, ask fresh: note the A7 bake-off; offer
  codebase-memory-mcp's installer, one of the two unrelated "CodeGraph" projects
  (codegraph-ai/CodeGraph or colbymchenry/codegraph — disambiguate by repo, not name), or
  Graphify (Graphify-Labs/graphify — CLI + `/graphify` skill, not MCP-first: `uv tool install
  graphifyy` then `graphify install --project`), or defer

Present as a table: **component | why (profile key that triggered it) | source | install method**.
Never recommend a name not present in the registry file — gaps are stated, not improvised.

## Step 2 — User selection
AskUserQuestion with multiSelect over the manifest (group: methodology / stack / cloud /
core / observability / memory). Default-recommend the `always` group; everything else neutral.

## Step 3 — Install (only selected items)
For each selected component, by `kind`:
- **plugin**: try the CLI first —
  `claude plugin marketplace add <marketplace>` (third-party only) then
  `claude plugin install <plugin>`. If the `claude` CLI is unavailable in this environment,
  print the exact `/plugin` commands for the user to run interactively and mark the item
  `pending-manual` in the lockfile.
- **cli**: run the registry's `install` command verbatim (confirm with the user first — it
  executes third-party code). **Exception: the Graphify component.** Don't run its bare
  `uv tool install graphifyy` here — hand off to `/harness-mem-graphify` instead (confirm
  first, same as any third-party install). It owns the fuller gated sequence this step doesn't
  (Python/uv prerequisite checks, an org's private package index from
  `shared.package_index` if set, the first index build, and the lockfile record) — running
  the bare command here would both duplicate and undercut it. **Exception: the OpenSpec
  component.** Same reasoning — hand off to `/harness-methodology-openspec` instead of the bare
  `npm install -g` command; it owns the gated install-plus-`openspec init` sequence and the
  lockfile record, and it's what `/harness-goal` later expects to find already set up.
- **mcp**: render the needed entries from `${CLAUDE_PLUGIN_ROOT}/templates/mcp.json.tmpl` into the project's
  `.mcp.json` (merge — never clobber existing servers; secrets stay `${VAR}` references
  to `.env.harness`).

## Step 4 — Wire the harness pieces
1. Confirm the se-harness **agents roster** is active (ships with this plugin — architect,
   story-writer, implementers, db-engineer, unit/integration testers, e2e planner/generator/
   healer, release-manager). Offer to copy any of them into `.claude/agents/` **only if** the
   user wants project-specific tuning (copied agents override plugin versions and stop
   receiving updates — say so).
2. Project-specific quality gates beyond the built-ins (gate-check, org-validate): point the
   user at the `hookify` plugin for authoring extra rules as hooks.
3. **Graphify selected and installed this run**: offer to wire
   `${CLAUDE_PLUGIN_ROOT}/scripts/graphify-update-hook.sh` as a PostToolUse(Bash) hook for this
   repo, the same way this surface registers its other project-level hooks. It only runs the
   cheap incremental `graphify update . --no-cluster` after a commit, in the background, and
   no-ops instantly for any repo that didn't choose Graphify — it's opt-in per repo
   (ECC "composable" doctrine), never bundled into the plugin's own global hooks.json.
   Mention plainly that it can't cover the workspace-level merge (a hook only sees the repo its
   session is in) — `/harness-mem-graphify`'s own "Keeping this fresh automatically" section
   covers that gap and what to do about it.
4. Re-render AGENTS.md/CLAUDE.md blocks via
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/render-block.sh <target> <block-file>` so the generated
   block reflects what's now installed.
   If it exits **3**, the generated block was hand-edited since the last render and was left
   untouched (`<target>.seaa.proposed` holds the new version): show the user a diff of the two,
   and ask keep-mine / take-new / merge. Only on take-new re-run with `--force` (the edited block
   is saved to `<target>.seaa.bak`). Never pass `--force` without asking.

## Step 5 — Record in the lockfile
Update `.harness/agentstack.lock`: for every component — name, source, version (if known),
install method, status (`installed` / `pending-manual` / `declined` / `deferred`), date. Declined items are
recorded too, so `/harness-sync` doesn't re-nag about them; `deferred` means "not yet" and
`/harness-sync` asks again. Decisions that aren't components (observability: none / not yet) live
in `profile.yaml`'s `observability:` block — the lockfile alone can't carry them.

## Step 6 — Report
Installed / pending-manual / declined table; exact manual commands for anything pending;
next step: `/harness-goal <your first goal>`.
