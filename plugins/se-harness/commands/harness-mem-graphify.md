---
description: Build and maintain Graphify structural-memory indexes for one repo or an entire se-harness workspace — install, extract, cluster/label, export full-symbol HTML, and merge per-repo graphs into a workspace-level graph.
argument-hint: "[repo_name]"
---

# /harness-mem-graphify — Graphify index build & merge

Build and maintain [Graphify](https://github.com/Graphify-Labs/graphify) indexes for a
se-harness project or workspace. Per-repo HTML is a symbol-level visualization with
descriptive symbol names. The workspace HTML is an overview of the merged graph; Graphify may
aggregate it when it exceeds the visualization limit, but its community names must still be
descriptive — never a bare `Community 0`/`Community 1`/etc.

This command only runs `graphify`, never installs or runs anything else; it never touches
`.env.harness`, property files, or deployment values.

## Step 1 — Scope

1. **Single repo** (`$ARGUMENTS` has a `repo_name`): process that one only. Validate the name
   against `workspace.yaml`'s `units:` or `repos.txt` and resolve its path beneath the
   workspace root. Don't ask whether to process the others.
2. **No repo given**: look for `workspace.yaml` or `repos.txt` in the current directory (same
   lookup `workspace-validate.sh`/`contract-check.sh` use). If found, ask whether to process
   every unit listed there, or name one unit, or stop — don't infer consent to run the
   workspace-wide loop from silence. If neither file exists, this is a single, non-workspace
   repo: process it alone, no question needed.
3. Use the workspace root resolved from `workspace.yaml`/`repos.txt`, not wherever the plugin
   itself is installed. `repos.txt` entries may be `<git-url>` or `<name>=<git-url>` lines
   (`workspace-clone.sh`'s format).
4. Skip any unit whose directory doesn't exist and report it. Never clone anything — that's
   `/harness-init` Step 1a's job.

## Step 2 — Confirm Graphify is actually the chosen driver, then install it

Never install or run Graphify for a unit that didn't choose it:

1. Check `workspace.yaml`'s `shared.memory.structural_driver` and the target unit's
   `.harness/profile.yaml` `memory.structural_driver` / `.harness/agentstack.lock` `components`
   for a Graphify entry (match case-insensitively on "graphify" — the recorded value may be the
   registry's full label or a short form; don't assume one exact string).
2. An explicit `declined` Graphify component recorded in that unit's own lockfile overrides an
   inherited workspace default — skip that unit unless the user explicitly selects Graphify for
   it in this invocation.
3. If Graphify wasn't selected anywhere relevant, ask before installing or running it for this
   invocation. If declined, stop — this is a deliberate `/harness-init` Step 6 choice, not
   something to override silently.
4. If the `graphify` CLI already runs (`graphify --version`), reuse it — don't reinstall. On
   Windows, also check `$HOME/.local/bin/graphify.exe` when it's missing from `PATH`.
5. If it needs installing:
   - **Python 3.10+** first (`python --version` / `python3 --version` / `py -3 --version`, as
     available). Missing or below 3.10 → ask the user to install/upgrade it themselves and stop
     this run until they confirm it's ready. **Never install Python yourself.**
   - **uv** next (`uv --version`; on Windows also check `$HOME/.local/bin/uv.exe`). Missing →
     ask the user whether to install it. Only on explicit approval, install it once for the
     user (not once per unit):
     - Bash shells with `curl`: `curl -LsSf https://astral.sh/uv/install.sh | sh`
     - Bash shells with `wget` but no `curl`: `wget -qO- https://astral.sh/uv/install.sh | sh`
     - PowerShell: `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`
     - None of the above available → ask the user to install uv themselves; don't run a Bash
       installer command from PowerShell or vice versa. Verify `uv --version` after.
   - **Install Graphify**: check `workspace.yaml`'s `shared.package_index` (optional —
     `{ url: "...", allow_insecure_host: "..." }`, a sibling of `shared.org`). If set, this org
     has a private package index and Graphify must come from it, never public PyPI:
     `uv tool install graphifyy --system-certs --index-url <url> --allow-insecure-host <allow_insecure_host>`.
     If the configured index is unreachable, stop and report the blocker — don't disable TLS
     verification or silently fall back to public PyPI. If `shared.package_index` isn't
     set, plain `uv tool install graphifyy` (public PyPI) is correct.
   - **Video extra, separately, always opt-in**: check whether it's already present (e.g.
     `graphify --version --verbose` or an import check for `faster_whisper`, whichever
     `graphify install --help`/its own docs confirm as current) — skip asking if so. If not,
     ask once, explicitly: install the `graphifyy[video]` extra to transcribe and index NAS
     video recordings (pulls in faster-whisper; this is a real, non-trivial download — say so).
     Only on approval: `uv tool install "graphifyy[video]"` (same private-index handling as
     above if `shared.package_index` is set). Declining is valid and the default — this command
     still does the plain code-graph work either way; nothing below depends on this extra being
     present. Record whichever outcome (installed / declined / already present) in the unit's
     `.harness/agentstack.lock` note for the `graphify` component, so later runs don't re-ask
     after a decline without the user changing their mind explicitly.
6. Verify `graphify --version` before processing any unit.
7. For each unit missing its own project-level Graphify skill, run `graphify install --project`
   (let it auto-detect the ecosystem) — or, if auto-detection picks wrong, the explicit flag for
   this session's surface (Copilot CLI/VS Code vs Claude Code; check `graphify install --help`
   for current flag names rather than guessing — a live trial found a bare `windows` platform
   value wires Claude Code, not VS Code Copilot, so don't assume the obvious-looking name is
   right). Keep any existing skill files; never overwrite a unit's own customizations.
8. Record a successful install in that unit's `.harness/agentstack.lock` (`components`): name
   `graphify`, source `Graphify-Labs/graphify (PyPI: graphifyy)`, installed version, install
   method, today's date, status `installed`. Never flip a prior `declined` status without the
   user's explicit choice in this invocation.

## Step 3 — Index each selected unit

Process units sequentially; report progress as you go. A failure in one unit is reported and
skipped — it never aborts the remaining units.

For each unit:

1. Confirm it's a git worktree and check its current branch/status. Never switch branches,
   stage, commit, or alter the user's pre-existing changes.
2. Keep generated Graphify output out of git: if `graphify-out/graph.json` isn't already
   ignored, add `graphify-out/` to that unit's `.git/info/exclude` (local-only; never the
   tracked `.gitignore`, since this is a per-checkout cache, not a repo policy).
3. Preserve the unit's existing `.graphify_labels.json` — it may hold human-curated labels;
   never overwrite a non-placeholder label with a guess.
4. Build or update the graph: if `graphify-out/graph.json` already exists, the cheap
   incremental path — `graphify update . --no-cluster` (no semantic/API extraction). Otherwise,
   the full build — `graphify extract . --code-only --no-cluster`. Don't opt into document,
   image, video, or other LLM-backed extraction in this workflow.
5. Cluster and generate the report: `graphify cluster-only .` (never pass `--no-label` —
   Graphify can generate deterministic hub-based names without an LLM backend).
6. Check `graphify-out/graph.json` and `.graphify_labels.json` for any label still matching
   `Community <number>`. If any remain: `graphify label . --missing-only`, then re-cluster.
   Preserve existing descriptive labels. If placeholders still remain, look at each affected
   community's actual member symbols/namespaces/source paths and write a concise, factual label
   into `.graphify_labels.json` yourself — never invent a domain name the members don't
   support — then re-cluster and verify again.
7. Before replacing an existing aggregated `graph.html`, preserve it once as
   `graph-communities.html`, if that backup doesn't already exist — don't lose the prior
   community-level overview.
8. Export the full symbol-level HTML, including for large units — don't let Graphify's default
   >5,000-node aggregation kick in here. Read the node count from `graph.json` and run
   `graphify export html --graph graphify-out/graph.json --node-limit <node-count-plus-one>`.
9. Verify: `graph.json`, `GRAPH_REPORT.md`, and `graph.html` all exist; every node carries its
   real symbol/file name; `.graphify_labels.json` and graph-node `community_name` values are
   descriptive; the HTML has no generic `Community <number>` label. (Graphify's own report
   headings intentionally carry a numeric prefix, e.g. `### Community 12 - "Order Generation
   Services"` — validate the quoted title, not the prefix.) Confirm the output is still
   git-ignored. Any check failing means fixing the labeling/export for *this* unit before
   moving to the next — don't carry a half-finished unit forward.

## Step 4 — Workspace graph

Only when more than one unit was in scope (skip entirely for a single-repo run). Refresh the
shared index from every unit that actually has a graph — don't require all of them to, and
don't clone anything missing.

1. Merge every available `<unit>/graphify-out/graph.json` with `graphify merge-graphs`.
2. Write the canonical merged database to `graphify-out/graph.json` at the workspace root. If
   this is a new destination, preserve any existing differently-named merged graph already
   there rather than deleting/renaming it. If the canonical destination already exists, keep a
   dated backup before replacing it.
3. `graphify cluster-only . --graph graphify-out/graph.json` to produce the merged
   `GRAPH_REPORT.md`, labels, and workspace overview HTML. The merged HTML may use an
   aggregated community view when the combined graph is too large for individual symbols —
   those aggregate nodes still need descriptive labels, never `Community <number>`.
4. Verify the merged graph parses, contains nodes from the processed units, and has no generic
   community label anywhere (graph nodes, label sidecar, or HTML). Report which units'
   graphs were included and which were skipped (missing or failed validation).

## Step 5 — Completion report

Per unit: Graphify version, whether the video extra is installed/declined, node/edge counts,
whether community labels were verified descriptive, whether its HTML is full-symbol or a
preserved community overview. Plus, if Step 4 ran: the merged workspace graph's location and
which units it includes. Call out every skipped unit or validation failure explicitly — never
silently drop one from the report.

## Keeping this fresh automatically

Re-running this command in full (re-cluster, re-label, re-export, re-merge) on every commit
would be too slow to run inline. For the cheap part — keeping `graphify-out/graph.json` current
via `graphify update . --no-cluster` after a commit, Step 3 point 4's incremental path — see
`${CLAUDE_PLUGIN_ROOT}/scripts/graphify-update-hook.sh`, which `/harness-bootstrap` offers to
wire in as a PostToolUse hook when Graphify is the unit's chosen driver (same opt-in gating as
here: it no-ops instantly for any unit that didn't choose Graphify). It only ever does the
cheap per-unit update, in the background, never cluster/label/export/merge.

The full rebuild (this command) and the **workspace-level merge** specifically are not
something a per-repo hook can do — a hook only ever sees the one repo its session is running
in, with no visibility into siblings. Re-run `/harness-mem-graphify` with no `repo_name`
periodically, or point an external scheduler (cron, Windows Task Scheduler, a nightly CI
workflow) at it from the workspace root, outside any agent session, if you want the merged
workspace graph to stay fresh without a manual trigger.
