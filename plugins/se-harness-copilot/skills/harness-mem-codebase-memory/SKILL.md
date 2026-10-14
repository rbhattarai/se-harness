---
name: harness-mem-codebase-memory
description: Install, register, index and refresh the codebase-memory-mcp structural-memory driver for one repo or a whole workspace — optionally linking the indexed repos with its cross-repo mode. Confirms every third-party install first.
---


# /harness-mem-codebase-memory — codebase-memory-mcp install, index & refresh

[codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) is a **local** MCP server (one
native binary, no API keys, no hosted service) that indexes a repo into a persistent knowledge
graph. This command owns its lifecycle so `/harness-bootstrap` doesn't have to: install, register
with your client, index each repo, link repos, and refresh. Nothing is installed or indexed for a
repo that didn't choose this driver.

It never touches `.env.harness`, property files or deployment values, and never commits the index.

## Step 1 — Scope
Same as `/harness-mem-graphify` Step 1: a `repo_name` argument means that unit only (validate against
`workspace.yaml` `units:` / `repos.txt`); none means ask whether to process every unit, one unit, or
stop (never infer consent from silence); no workspace files means a single repo. Use the workspace
root from those files. Skip units whose directory is missing and report them; never clone.
`--refresh` skips install/registration and only re-indexes (Step 5).

## Step 2 — Confirm this is the chosen driver
Check `memory.structural_driver` (and `shared.memory.structural_driver`) and the unit's
`agentstack.lock` components for `codebase-memory-mcp` (case-insensitive; the recorded value may be
the registry label or a short form). A `declined` entry in a unit's own lockfile overrides an
inherited default. Not chosen anywhere → ask before doing anything; if declined, stop.

## Step 3 — Install (once per machine, only with confirmation)
1. If `codebase-memory-mcp --version` already runs, reuse it. Do not reinstall.
2. Otherwise show the user the exact install command and ask. It executes third-party code, so
   never run it silently:
   - macOS / Linux: `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash`
   - Windows (PowerShell): download `install.ps1`, `Unblock-File .\install.ps1`, then
     `.\install.ps1` (or `PowerShell -ExecutionPolicy Bypass -File .\install.ps1` if policy blocks).
   - Other channels exist (Homebrew, Scoop, Winget, npm, `go install`, …); offer them if the user's
     org mandates a package manager.
3. **The installer auto-configures every MCP client it detects** (about 45 surfaces, including user-level
   config files). Tell the user that before running it. Prefer the registration-free form so Step 4 is
   the single place registration happens: on Windows the documented flag is `--skip-config`; for
   `install.sh` run `bash install.sh --help` (download it first rather than piping) and use the
   equivalent if there is one; if there is none, say what will be configured and let the user decide.
4. Windows: Microsoft Defender may flag the unsigned binary (the project documents this as a known
   false positive) and SmartScreen may warn; mention it and the `checksums.txt` verification — never
   tell the user to disable protection.
5. Verify `codebase-memory-mcp --version`. Updates are a re-run of the installer; the binary never
   updates itself and makes no background network requests.

## Step 4 — Register with the client
Ask where, with AskUserQuestion:
- **User scope** (once per machine; `~/.claude.json`) — works from every repo, nothing in any repo.
- **Project `.mcp.json`** (shareable, per repo) — `{"mcpServers":{"codebase-memory-mcp":{"command":
  "codebase-memory-mcp","args":[]}}}` merged without touching other servers.
- **Copilot CLI / VS Code**: if the installer was run without `--skip-config` it has already written
  those; otherwise print the standard MCP entry for the client and have the user add it.
Restart the agent afterwards (the project says all running processes must use the same build).
`/mcp` should then list the server's tools (17 per the project's README).

## Step 5 — Index, per unit
1. Index each unit: `codebase-memory-mcp cli index_repository --repo-path <unit-path>` (or the
   `index_repository` tool when connected). Default mode is `full`; offer `moderate` / `fast` for
   very large repos. For big repos use the async form the project documents (start with `async: true`,
   poll with `status: true`) so a client timeout doesn't kill the run.
2. Confirm with `index_status` / `list_projects` and report per unit: indexed, node/edge counts if
   shown, or the error. A failed unit never stops the others.
3. **Linking repos (workspace only).** The tool has a `cross-repo-intelligence` mode that links
   services across indexed projects with `CROSS_*` edges (optionally limited with `target_projects`).
   It is the closest thing to Graphify's merged workspace graph, but it is heavier — offer it once,
   after every unit is indexed, and say what it costs. Don't run it unasked.
4. **Where the index lives**: `~/.cache/codebase-memory-mcp/` (override `CBM_CACHE_DIR`) — outside the
   repo, so nothing to gitignore. The project's opt-in shared snapshot
   (`.codebase-memory/graph.db.zst`) can bloat git history; do **not** enable it by default, and if the
   user asks, warn and suggest Git LFS or a deliberate commit cadence.
5. `codebase-memory-mcp config set auto_index true` indexes new projects on first connection — mention
   it, don't set it unasked.

## Step 6 — Freshness
A background watcher re-indexes **only the project the open MCP session is rooted in** (git projects
by default). Every other repo goes stale until re-indexed, so after large refactors or when working
across repos run `/harness-mem-codebase-memory --refresh` (Step 5 again). `/harness-goal`'s preflight
tells you when an index looks stale.

## Step 7 — Record and report
`.harness/agentstack.lock`: a `codebase-memory-mcp` component (`kind: cli`, version from `--version`,
status `installed` / `pending-manual`), plus per-unit index status and date. Report what was installed
vs reused, where it was registered, per-unit index results, whether cross-repo linking ran, and the
refresh reminder. Next: `/harness-goal`.
