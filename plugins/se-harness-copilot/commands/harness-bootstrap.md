---
description: Recommend and install the harness components matching this project's profile — methodology, stack plugins, MCP servers, observability — opt-in per item, recorded in the lockfile.
argument-hint: [--dry-run]
---

# /harness-bootstrap — Phase 3 generator

Turn the profile into an installed harness. **Composable, opt-in** (the ECC lesson: users
cherry-pick; never install everything). Read `--dry-run` from `$ARGUMENTS`: if present, produce
the recommendation manifest and stop before installing anything.

## Step 1 — Build the recommendation manifest
Read `.harness/profile.yaml` (guard: must exist — run `/harness-init` first) and
`../se-harness/registry/recommendations.json`. Map profile → components:

- `methodology` → its entry (plugin or CLI install)
- each `stack.*` value → its `plugins` list (skip entries with empty lists; surface their
  `note` so the user knows why nothing is recommended)
- `cloud` → its plugins
- `always` + `testing.e2e` → recommended for every project
- `observability.choose_one` → ask which (or neither)
- `sources`: Jira/Confluence set → `atlassian`; GitHub remote detected → `github`;
  `org.conventions_url` on Figma-backed design orgs → `figma`
- `memory.structural` → note the A7 bake-off; offer codebase-memory-mcp's installer, one of
  the two unrelated "CodeGraph" projects (codegraph-ai/CodeGraph or colbymchenry/codegraph —
  disambiguate by repo, not name), or Graphify (Graphify-Labs/graphify — CLI + `/graphify`
  skill, not MCP-first: `uv tool install graphifyy` then `graphify install --project`), or defer

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
  executes third-party code).
- **mcp**: render the needed entries from `templates/mcp.json.tmpl` into the project's
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
3. Re-render AGENTS.md/CLAUDE.md blocks via
   `bash tools/harness/render-block.sh <target> <block-file>` so the generated
   block reflects what's now installed.

## Step 5 — Record in the lockfile
Update `.harness/agentstack.lock`: for every component — name, source, version (if known),
install method, status (`installed` / `pending-manual` / `declined`), date. Declined items are
recorded too, so `/harness-sync` doesn't re-nag about them.

## Step 6 — Report
Installed / pending-manual / declined table; exact manual commands for anything pending;
next step: `/harness-goal <your first goal>`.
