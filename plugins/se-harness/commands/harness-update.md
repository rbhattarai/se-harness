---
description: Update the se-harness plugin to the newest version (marketplace first, GitHub as fallback), then migrate this project's .harness/ data to match — without losing anything the project changed.
argument-hint: [--check]
---

# /harness-update — plugin update + project migration

Two different things get out of date, and this command handles both in order:

1. **The plugin** (commands, skills, hooks, scripts) — lives in Claude Code's plugin cache, is
   replaced wholesale on update, and only takes effect after a **restart**.
2. **This project's harness data** (`.harness/`, the generated blocks in `AGENTS.md` /
   `CLAUDE.md`) — lives in the repo, is *yours*, and must be migrated, never overwritten.

Because of the restart, the command is **re-entrant**: run it, update, restart, run it again.
`--check` in `$ARGUMENTS`: run Steps 0, 1 and the read-only `--dry-run` of Step 3, report what
is out of date and what would happen, and change nothing (Step 1's marketplace refresh only
updates the local catalog clone).

Never use `-y`/`--force`/`--force-blocks` or accept a marketplace-declared command on the
user's behalf — every one of those is an explicit confirmation from them.

## Step 0 — What is installed, what is in the project
- **Running plugin version**: `version` in the `plugin.json` of the plugin that ships this
  command (the one currently loaded).
- **Project stamp** (if `.harness/agentstack.lock` exists): `se_harness` (version that last
  wrote this project) and `schema_version` (absent = 1). At a workspace root (`workspace.yaml` /
  `repos.txt`, no lockfile of its own) the stamp lives in each bootstrapped unit — see Step 5.
- **Install scope**: from `~/.claude/plugins/installed_plugins.json`, the `se-harness@se-harness`
  entry whose `projectPath` is this project (scope `project`), else the `user`-scope entry. An
  update must target the same scope (`--scope`), or it updates a different copy than the one
  this project loads.

## Step 1 — Find the newest version (marketplace first)
1. Refresh the marketplace clone: `claude plugin marketplace update se-harness`.
2. On success, read `version` from
   `~/.claude/plugins/marketplaces/se-harness/plugins/se-harness/.claude-plugin/plugin.json`
   (the path is the `installLocation` in `~/.claude/plugins/known_marketplaces.json` — use that
   value if it differs).
3. **If the marketplace step fails** (offline, auth, marketplace not added, clone broken): fall
   back to GitHub. Fetch with WebFetch
   `https://raw.githubusercontent.com/rbhattarai/se-harness/main/plugins/se-harness/.claude-plugin/plugin.json`
   (the repo is `repository` in this plugin's `plugin.json`; use it if it differs) and read
   `version`. If that fails too, say both sources were unreachable, name each error, and stop —
   do not guess.
4. Compare with the running version (semver). Report one line:
   `installed X · newest Y (via marketplace|github) · project stamp S / schema N`.
   For a major bump, point at the release notes
   (`https://github.com/rbhattarai/se-harness/releases`) before going on.

(Plugin scripts make no network calls — `PRIVACY.md` — so every lookup above goes through the
`claude` CLI or WebFetch, here in the command, never inside `scripts/`.)

## Step 2 — Update the plugin (only if newest > running)
With `--check`: skip this step and Step 4; report only.

1. Confirm with the user (AskUserQuestion): update `se-harness` X → Y at the scope found in Step 0?
2. If the newest version was found **only via GitHub** (the marketplace step failed), the
   marketplace clone is stale and `claude plugin update` would see no change. Tell the user to
   repair it first — `claude plugin marketplace add rbhattarai/se-harness` (re-adds/refreshes),
   or `/plugin marketplace update se-harness` once connectivity is back — and re-run this command.
   Do not copy files out of a GitHub clone into the plugin cache by hand.
3. Otherwise run `claude plugin update se-harness@se-harness --scope <scope>`. If it reports a
   marketplace-declared command that needs confirmation, show that command to the user verbatim
   and let them decide; do not pass `--accept-command` yourself.
4. Tell the user plainly: **restart Claude Code, then run `/harness-update` again** — the new
   commands and scripts load only on restart, and the migration in Step 4 must be run by the
   *new* plugin's `migrate.sh`, which is why this command stops here. Stop.

(GitHub Copilot CLI variant: the same flow with that client's own plugin update command for
`se-harness-copilot` — see `docs/setup-guide-copilot.md`; the lookups in Step 1 are the same.)

## Step 3 — Running plugin is current: does this project need migrating?
(No lockfile → the project isn't bootstrapped; nothing to migrate. Say so and stop; suggest
`/harness-init` then `/harness-bootstrap`.)

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate.sh --dry-run`.
- `up to date` and `se_harness` equals the running version → "nothing to do", stop.
- `up to date` but `se_harness` is older → no data migration is needed; skip to Step 5
  (a sync refreshes the generated blocks and stamps the new version).
- Pending migrations → list them with their descriptions, and say what protects the user:
  one backup under `.harness/backup/`, whole-run rollback on any failure, hand-edited generated
  blocks never overwritten silently, user-written files never touched.
- `project schema is newer than this plugin supports` → the plugin is *older* than the project
  (someone upgraded elsewhere). Go back to Step 2.

## Step 4 — Migrate
1. If the working tree has uncommitted harness changes, `migrate.sh` refuses (exit 2). Suggest
   committing or stashing them first. Offer `--allow-dirty` only if the user insists.
2. Confirm, then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate.sh`.
3. Exit 0 → report the schema change and the backup path. Exit 3 → a generated block was
   hand-edited: for each `*.seaa.proposed` file show the user a diff against their current
   block and ask keep-mine / take-new. Keep-mine: leave it (the project stays on its old
   block; tell them the migration did not run). Take-new: re-run with `--force-blocks`
   (their edit is saved to `<file>.seaa.bak`). Exit 1 → rolled back; show the error and the
   backup path; do not retry blindly.

## Step 5 — Refresh generated content
Run `/harness-sync` (its Step 0b re-checks the stamps; it sets `se_harness` to the running
version after a clean sync). At a **workspace root**, ask once which bootstrapped units to
update (all / named / suggest), then run Steps 3–5 for each unit in turn and finish with one
table: unit | schema before → after | migrated | block conflicts | skipped.

## Step 6 — Report
Plugin: X → Y (or already current) · migrated: schema A → B (or none) · backup path ·
`.seaa.proposed`/`.seaa.bak` files left for the user to review · next: review the diff and
commit `.harness/`, `AGENTS.md`, `CLAUDE.md`; add `.harness/backup/` to `.gitignore` (or delete
the backup once satisfied).
