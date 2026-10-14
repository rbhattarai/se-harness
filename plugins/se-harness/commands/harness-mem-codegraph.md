---
description: Install, register, index and refresh the CodeGraph structural-memory driver (colbymchenry/codegraph, or codegraph-ai/CodeGraph) for one repo or a whole workspace. Confirms every third-party install and the telemetry choice first.
argument-hint: "[repo_name] [--refresh]"
---

# /harness-mem-codegraph — CodeGraph install, index & refresh

"CodeGraph" is the name of **two unrelated projects**. Never proceed on the name alone: confirm which
one, by repository, and record it as `memory.codegraph.variant`:
- **`colbymchenry`** — [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph): lightweight
  pre-built graph in a local SQLite file (`.codegraph/`), CLI-installed, file-watcher auto-sync, MIT.
  **Fully supported here.**
- **`codegraph-ai`** — [codegraph-ai/CodeGraph](https://github.com/codegraph-ai/CodeGraph): tree-sitter
  semantic graph with embeddings, 42 MCP tools, RocksDB under `~/.codegraph/`, Apache-2.0 (a paid Pro
  tier adds tools). **Register and verify only** — its engine ships as a VS Code extension / downloaded
  native binary / cargo build, so the user installs it and this command never downloads one.

Nothing is installed or indexed for a repo that didn't choose CodeGraph. It never touches
`.env.harness` and never commits an index.

## Step 1 — Scope
Same as `/harness-mem-graphify` Step 1: `repo_name` argument = that unit only; none = ask whether to
process every unit, one unit, or stop; no workspace files = single repo. Use the workspace root from
`workspace.yaml` / `repos.txt`. Skip missing directories and report them; never clone. `--refresh`
skips install and registration and only re-syncs (Step 6).

## Step 2 — Confirm the driver and the variant
Check `memory.structural_driver` (and the shared one) and the unit's lockfile for CodeGraph
(case-insensitive). Not chosen → ask before doing anything. Read `memory.codegraph.variant`; if unset,
ask which project (show the two links above) and record it (workspace: `shared.memory.codegraph`). A
`declined` lockfile entry in a unit overrides an inherited default.

## Step 3 — colbymchenry/codegraph: install (once per machine, with confirmation)
1. If `codegraph version` already runs, reuse it (`codegraph upgrade --check` reports updates).
2. Otherwise show the exact command and ask — it executes third-party code:
   - macOS / Linux: `curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh`
   - Windows (PowerShell): `irm https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.ps1 | iex`
   - Any OS with Node: `npm i -g @colbymchenry/codegraph`
   Open a new terminal afterwards (the installer doesn't change the current shell).
3. **Do not run `codegraph install` by default.** It writes MCP config for every agent it detects and
   adds its own marker-fenced section to `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`, which would sit
   beside the harness's generated block. Register explicitly in Step 5 instead. Mention the option; if
   the user wants it, run it with `--target <agent>` and show them what it changed.
4. **Telemetry is on by default** (opt-out). Ask the user — and say the org's policy may decide it —
   whether to run `codegraph telemetry off` (or set `CODEGRAPH_TELEMETRY=0` / `DO_NOT_TRACK=1`). Record
   the answer in `memory.codegraph.telemetry`; never change it silently.

## Step 4 — colbymchenry: index, per unit
1. For each unit: `codegraph init <unit-path>` — creates `.codegraph/` and builds the full graph (once
   per project). Append `.codegraph/` to that repo's `.gitignore` if absent (grep before append).
   Optional `codegraph.json` at a repo root can `exclude` committed directories or `deprioritize`
   paths; offer it only if indexing looks noisy.
2. Confirm with `codegraph status <unit-path>`; report per unit: indexed or the error. A failed unit
   never stops the others. WSL/Windows caveat: never share one `.codegraph/` between a Windows and a
   WSL checkout, and avoid network shares or `/mnt` paths (SQLite locking).
3. Each repo is indexed separately; there is no merged workspace graph. From one session an agent can
   query another indexed repo with the `projectPath` parameter, which is how multi-repo work happens.

## Step 5 — Register with the client
Ask where: **user scope** (`~/.claude.json`, once per machine) or **project `.mcp.json`** (shareable,
per repo). The entry, merged without touching other servers:
```
"codegraph": { "type": "stdio", "command": "codegraph", "args": ["serve", "--mcp"], "alwaysLoad": true,
               "env": { "CODEGRAPH_MCP_TOOLS": "explore,search,node,callers,callees,impact,files,status" } }
```
`CODEGRAPH_MCP_TOOLS` matters: by default only `codegraph_explore` is listed, and the impact map in
`/harness-goal` needs callers/callees/impact. Copilot CLI / VS Code: print the equivalent for the
client (`codegraph install --print-config <agent>` prints a snippet without writing anything).
Optionally suggest allowing `mcp__codegraph__*` in the user's permissions. Restart the agent.

**codegraph-ai variant**: the user installs the engine (VS Code extension, `cargo build --release -p
codegraph-server`, or `@astudioplus/codegraph-mcp` from npm). Then register
`{"command":"<path>/codegraph-server","args":["--mcp","--workspace","<unit-path>", ...]}` — one
`--workspace` per unit lets a single server index the whole workspace — and optionally
`CODEGRAPH_TOOL_PROFILE=core|graph`. It indexes the workspace itself on start. Note its requirements
(Linux glibc 2.30+/GCC 11+ libstdc++, ~1.5 GB free RAM or it silently runs graph-only without
semantic search) and that embedding models download on first use.

## Step 6 — Freshness
colbymchenry: with the MCP server running, a file watcher re-syncs automatically after a short debounce
and reconciles changes made while it wasn't running. Manual: `codegraph sync <path>` (or `codegraph
index --force`), and `codegraph unlock` for a stale lock. codegraph-ai: `--watch` daemon, or the
`reindex_workspace` tool. `--refresh` runs these for every chosen unit.

## Step 7 — Record and report
`.harness/agentstack.lock`: a `codegraph` component with the variant, version, registration scope and
per-unit status; profile gets `memory.codegraph.{variant,telemetry}`. Report installed vs reused,
telemetry decision, registration, per-unit index results, and (colbymchenry) the reminder that the
watcher only runs while an MCP session is open. Next: `/harness-goal`.
