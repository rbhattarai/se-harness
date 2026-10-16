---
name: harness-mem-sourcegraph
description: Connect, verify and audit the Sourcegraph structural-memory driver (Cloud or self-hosted) — wire the MCP connection, check it works, and report which workspace repos the instance actually has indexed. Builds nothing; the instance does the indexing.
---


# /harness-mem-sourcegraph — Sourcegraph connection, health & coverage

The Sourcegraph counterpart of `/harness-mem-graphify`, with a very different job. Graphify is a
local tool: this harness installs it, builds the index and merges graphs. **Sourcegraph is a hosted
service**: the instance (Sourcegraph Cloud, or your own self-hosted one) already holds and
refreshes the index, and exposes it over a remote MCP endpoint. So this command **installs
nothing and builds nothing**. It does three things: wire the connection, verify it works, and
tell you which of your repos the instance can and cannot answer for.

It reads only. It never prints or reads a token value, never touches `.env.harness` contents
(variable *names* only), and never changes anything on the Sourcegraph instance.

`$ARGUMENTS`: `connect` (set up or change the connection), `verify` (is it working now), `coverage`
(which repos are on the instance). No argument: if no connection is configured run `connect`, else
run `verify` then `coverage`.

## Step 0 — Scope and guard
1. Resolve the workspace the way `/harness-mem-graphify` does: `workspace.yaml` or `repos.txt` in the
   current directory or its parent means a workspace (units come from there); neither means a single
   repo. Use the workspace root from those files, not where the plugin is installed.
2. This command is for the Sourcegraph driver. Check `memory.structural_driver` (or
   `shared.memory.structural_driver`). If it is another driver or `null`, say so and ask before
   proceeding; if the user wants Sourcegraph, record `sourcegraph` as the driver (profile, and
   `shared:` when a workspace exists — confirm first, it is outside this repo) and re-render the
   AGENTS.md / CLAUDE.md blocks via `render-block.sh` as `/harness-bootstrap` Step 4 does.
3. Requirements to state up front, once: an Enterprise plan with MCP enabled on the instance (admin
   setting `mcp.enabled`, on by default), the `MCP#ACCESS` permission for the user, and the repos
   must be connected to the instance by its admin.

## Step 1 — Connect (`connect`, or when nothing is configured)
Read `memory.sourcegraph` (workspace: `shared.memory.sourcegraph`, ask once, units inherit). Fill only
what is empty, with AskUserQuestion:
1. **Deployment** — Sourcegraph Cloud (managed instance) or self-hosted. Both are just a URL; this
   only changes the wording of any help text.
2. **Instance URL** (free text, e.g. `https://sourcegraph.acme.com`) — `https://` unless the user
   says it is an internal-only `http://` host. Strip any path. Reject anything containing a token or
   credentials.
3. **Endpoint** — `/.api/mcp` (search, navigation, repos, history — default) or `/.api/mcp/all`
   (adds Deep Search).
4. **Auth** — **OAuth** (browser login, no secret stored — recommended for people) or **access
   token** (headless or CI; scope `mcp`; the value lives in `.env.harness` as
   `SOURCEGRAPH_ACCESS_TOKEN`, only the variable *name* is recorded).
5. **Registration scope** (Claude Code) — where the connection is registered:
   - **User scope, once per machine** — `claude mcp add --scope user --transport http sourcegraph
     <url><endpoint>`. Works from every repo with nothing written into any repo. Best for OAuth.
     With token auth the header value would be written into the user's own config, so for token auth
     prefer the project option unless the user accepts that.
   - **Project `.mcp.json`, per repo** — shareable, but written into each repo (this command offers
     to do all units in one pass). Token auth uses `"Authorization": "token ${SOURCEGRAPH_ACCESS_TOKEN}"`
     (a `${VAR}` reference, never the value); OAuth omits `headers`.
   Never write a workspace-root `.mcp.json` and call it done: a session opened inside a repo does not
   read it.
6. **Repo scope** (optional) — a repo-name prefix agents add to queries, e.g. `github.com/acme/`.

Write the answers under `memory.sourcegraph` / `shared.memory.sourcegraph` (`url`, `endpoint`, `auth`,
`token_env`, `repo_scope`, `deployment`); for `.mcp.json`, merge a `sourcegraph` entry from
`tools/harness/templates/mcp.json.tmpl` without touching other servers. If token auth, make
sure `.env.harness` has the *name* `SOURCEGRAPH_ACCESS_TOKEN=` (empty is fine; the user fills it).

**Copilot CLI / VS Code**: never write a token to a file. Print `copilot mcp add --transport http
sourcegraph <url><endpoint>` and `/mcp auth sourcegraph`; for VS Code a `.vscode/mcp.json` with
`{"servers":{"sourcegraph":{"type":"http","url":"<url><endpoint>"}}}` then sign in from the MCP
view. Sourcegraph documents the token header for Claude Code but no env-var syntax for VS Code, so
token auth there is manual — say so.

## Step 2 — Verify (`verify`)
1. Are Sourcegraph's tools among yours (`mcp__sourcegraph__*` — `keyword_search`, `find_references`,
   `list_repos`, ...)? No → not connected: Claude Code `/mcp` (sign in / check status), Copilot
   `/mcp auth sourcegraph`; a freshly added server may need a session restart. Stop here and say so.
2. Connected → one cheap read-only call (`list_repos`, small page) to prove it answers. Interpret
   failures by what the docs say: `404` = MCP disabled on the instance; `403` = token lacks the `mcp`
   scope or the user lacks `MCP#ACCESS`; `invalid_scope` = pin the `mcp` scope in the client; OAuth
   access tokens expire hourly, so re-authenticate. No Enterprise plan = no MCP endpoint at all.
3. Report: URL, endpoint, auth mode, tool count, and (via `decision-review.sh`) a missing token variable
   name or an empty URL.

## Step 3 — Coverage (`coverage`)
The question that matters for a multi-repo product: **can the instance answer for each of my repos?**
1. For each unit (every unit in a workspace, else this repo): take its git remote
   (`git -C <unit> remote get-url origin`) and derive the likely Sourcegraph repo name
   (`host/org/repo`, no `.git`, no credentials; prepend `repo_scope` if the instance uses a prefix).
   No remote → mark `unknown`, don't guess.
2. Look each up with `list_repos` (name filter). Never a write, never more than a small page per unit.
3. Print one table: **unit | derived repo name | on instance? (yes / no / unknown) | note**. Repo
   names depend on how the admin configured the code host, so a "no" can be a naming difference — say
   that, and offer the closest `list_repos` match instead of declaring it missing.
4. For repos that are not on the instance: tell the user plainly that Sourcegraph can't answer for
   them (the goal loop falls back to Grep/Glob for those and says so), and that adding them is the
   instance admin's job, not something this command can do.
5. Append one line to today's `.harness/memory/daily/` log (workspace root when a workspace exists):
   date, instance host, and counts (on / not on / unknown). Never a token.

## Step 4 — Record and report
- `.harness/agentstack.lock`: a `sourcegraph` component, `kind: mcp`, status `connected` only if
  Step 2 proved it, else `pending-manual`; append a short `scans:`-style note with the coverage counts.
- Report what was configured vs already there, the verify result, the coverage table, and next steps:
  fix `pending-manual` items; then `/harness-goal`. There is nothing to refresh later — freshness is
  the instance's — but re-run `coverage` after repos are added or renamed on the instance, and
  `connect` if the URL, endpoint or auth changes (also reachable as
  `/harness-bootstrap --reconfigure memory`).
