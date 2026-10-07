# Setup Guide: se-harness with GitHub Copilot

A step-by-step guide for bootstrapping the **se-harness** framework in an organization that
uses **GitHub Copilot** (not Claude Code). Written for a first-time user.

> Using **Claude Code** instead? See [`setup-guide-claude.md`](./setup-guide-claude.md) —
> same framework, same artifacts, simpler install.

## What is this plugin?

**se-harness** wraps an AI-agentic SDLC harness around any software project — new or
existing, any stack. Installing it gives your Copilot sessions:

- **8 commands** — `harness-init` (intake interview → generates AGENTS.md/CLAUDE.md,
  `.harness/profile.yaml`, memory seeds), `harness-scan` (brownfield stack/org detection),
  `harness-bootstrap` (recommends & installs companion plugins/MCP servers),
  `harness-goal` (the delivery loop: grill → requirement → stories → implement → test →
  PR → deploy, with 3 human-approval gates), `harness-sync` (drift detection & refresh),
  `harness-export` (compile agents for other tools), `harness-mem-graphify` (build/maintain
  Graphify structural-memory indexes, per-repo and workspace-merged), `harness-methodology-openspec`
  (install/init OpenSpec where chosen — `harness-goal` drives its actual propose/archive lifecycle).
- **12 SDLC agents** — architect, story-writer, backend/frontend implementers, db-engineer,
  unit/integration testers, e2e planner/generator/healer, release-manager, and a
  workspace-orchestrator for multi-component requirements (used only when one applies).
- **16 skills** — stack-detector, requirement-grill, memory-keeper, wiki-ingest/query/lint,
  context-injector conventions, coding-discipline, plus the eight commands as CLI skills.
- **Enforcement hooks** — a human-in-the-loop gate that denies PR/push/deploy until a
  requirement is `approved`, org-rules validation on edits, contract-impact checking across
  repos, and automatic memory logging of commits/PRs.
- **A 3-tier memory system** — structural code index, append-only decision log, and a
  synthesized domain wiki — all plain committed files under `.harness/`.

The framework is Claude-Code-first and **dual-published**: `plugins/se-harness` is the
source of truth; `plugins/se-harness-copilot` is generated from it for Copilot CLI. The
artifacts it writes into your repos (AGENTS.md, `.harness/`) are tool-agnostic.

**Structure of this guide**: Part 1 covers getting the framework installed (including
restricted-org alternatives); Parts 2–8 walk a **multi-repo** product end-to-end;
**Part 9** is the short path for a **single-repo** project; Part 10 covers updating or
extending the plugin; Part 11 covers publishing to the marketplaces.

The multi-repo example uses a fictional product called **acme-loan-platform** with the
repos below. (For a real, clonable two-app demo, see
[demo-loan-app](https://github.com/rbhattarai/demo-loan-app) and the
[multi-unit walkthrough](./demo/README.md#part-2--multi-unit-walkthrough-the-loan-product).)

| Repo | Stack |
|---|---|
| `frontend` | Angular + TypeScript, uses company-internal UI & common libraries |
| `backend-core` | .NET Core C# MVC |
| `backend-integration` | .NET Core C# services (vendor batch/streaming integrations) |
| `common` | .NET Core shared utilities library |
| `ui` | Node.js internal UI-component library |
| `config` | per-environment `.prop` files (dev/qa/uat/prod) |
| `database-config` | MSSQL data objects & domains |

Replace names/paths with your own product's.

---

## 0. What you get on Copilot (read this first — honest expectations)

This framework is built Claude-Code-first and **dual-published for Copilot**: the same
marketplace repo serves a Copilot CLI plugin (agents + skills + commands) and repo-level
hooks. The remaining gaps are surface-specific (VS Code Chat), not wholesale:

| Piece | On Copilot |
|---|---|
| `AGENTS.md` project brief (stack, org conventions, workflow) | ✅ **Native** — Copilot coding agent reads root + nested AGENTS.md automatically |
| Agent roster (architect, implementers, testers, release-manager) | ✅ Compiled to `.github/agents/*.md` custom-agent profiles by the export script |
| Commands (`/harness-init`, `/harness-goal`, …) | ✅ Ship in the **Copilot CLI plugin** (4.2); also usable as prompt files (`.github/prompts/*.prompt.md`) in VS Code Chat (4.3) |
| Skills (stack-detector, requirement-grill, memory-keeper, wiki-*) | ✅ Same SKILL.md standard — bundled in the CLI plugin (4.2) |
| Shell scripts (scan, splice, REQ scaffolding, worktrees, contract-check) | ✅ Run in Git Bash — by you or by Copilot agent mode's terminal |
| Enforcement hooks (HITL gate, org-rules validation, memory auto-log, contract-check) | ✅ All surfaces: bundled in the CLI plugin (4.2), repo-level `.github/hooks/*.json` for the coding agent (4.7), and **VS Code loads `.github/hooks/*.json` too** (Claude-style semantics). Actions + branch protection remain the human-binding backstop (Part 6) |
| MCP servers (Atlassian/Jira, GitHub) | ✅ Portable — VS Code Copilot supports MCP via `.vscode/mcp.json` |
| `.harness/` artifacts (profile, requirements, memory) | ✅ Plain committed files — tool-agnostic |

**Prerequisites**: Windows with **Git Bash** (scripts are bash), VS Code with Copilot
(Business/Enterprise license, agent mode enabled by your admin), git access to your product
repos, and — for Jira/Confluence integration — your firm's approval to enable the Atlassian
MCP server.

---

## Part 1 — Install the framework

### 1.1 Standard install (no restrictions)

If your machine can reach public GitHub and plugin installs aren't restricted, this is a
two-liner in Copilot CLI:

```bash
copilot plugin marketplace add rbhattarai/se-harness
copilot plugin install se-harness-copilot@se-harness
```

Verify: `copilot plugin list` shows `se-harness-copilot`, and a new session can answer
"what harness commands do you have?" (or run `copilot harness-scan` in a repo).

### 1.2 Restricted org — internal import (preferred alternative)

Do **not** hand-copy an unreviewed zip from the public internet into firm infrastructure.
Follow your firm's third-party/OSS intake process:

1. The framework lives at public GitHub as `rbhattarai/se-harness`
   (it contains no company or product data — verify by reading it; it's small).
2. Request your platform/security team to **import it into GitHub Enterprise as an internal
   repo**, e.g. `yourorg/se-harness` (GitHub's "Import repository", or fork if your enterprise
   allows). This preserves history and makes future updates a `git pull`, not a re-copy.
3. Then install from the internal copy:
   ```bash
   copilot plugin marketplace add yourorg/se-harness
   copilot plugin install se-harness-copilot@se-harness
   ```
4. From now on, everything references the **internal** copy.

### 1.3 Restricted org — offline zip / local install (last resort)

If policy forces offline transfer, or `copilot plugin marketplace add` is blocked entirely:

1. On the GitHub repo page: **Code → Download ZIP** (or grab a tagged release zip). Submit
   it through your code scanning/approval process.
2. Unzip the reviewed contents somewhere stable, e.g.
   `C:\tools\se-harness` (or push them to an internal repo —
   better, because updates stay pullable).
3. Copilot CLI installs plugins from a **local path** too:
   ```bash
   copilot plugin install /c/tools/se-harness/plugins/se-harness-copilot
   ```
   Or register the unzipped folder as a local marketplace:
   ```bash
   copilot plugin marketplace add /c/tools/se-harness
   copilot plugin install se-harness-copilot@se-harness
   ```
4. Caveats of the zip route: you lose `git pull` updates — record the source commit SHA next
   to the unzipped copy; and plugin components are **cached**, so after replacing the folder
   with a newer zip, reinstall (`copilot plugin uninstall se-harness-copilot` then install
   again) to pick up changes.
5. Even if the CLI plugin can't be installed at all, Parts 2–8 still work: the repo-level
   artifacts (`.github/agents/`, `.github/prompts/`, `.github/hooks/`, vendored
   `tools/harness/` scripts) are plain files driven by prompts — no plugin required.

> One-time org customization worth doing in the internal copy: fill
> `registry/recommendations.json`'s org-specific entries later as your team learns which
> internal tools map to which stacks.

---

## Part 2 — Create the product workspace (side-by-side clones)

One folder per product, all repos cloned as siblings, the harness beside them:

```bash
mkdir acme-loan-platform && cd acme-loan-platform
git clone <internal-git-url>/frontend.git
git clone <internal-git-url>/backend-core.git
git clone <internal-git-url>/backend-integration.git
git clone <internal-git-url>/common.git
git clone <internal-git-url>/ui.git
git clone <internal-git-url>/config.git
git clone <internal-git-url>/database-config.git
git clone <internal-git-url>/se-harness.git       # the framework (internal copy)
```

Why side-by-side: the workspace manifest, contract-check, and any cross-repo reading all
assume sibling checkouts (`../workspace.yaml` lookup).

---

## Part 3 — The workspace manifest (`workspace.yaml`)

Create `acme-loan-platform/workspace.yaml` from `se-harness/templates/workspace.yaml`. This is the
product-level file: topology, shared org context, and the **contract registry** that powers
cross-repo impact checking. An acme-loan-platform-shaped example:

```yaml
workspace:
  name: acme-loan-platform
  topology: multi-repo
  layout: layered            # frontend / backend-core / backend-integration / config / db

  shared:
    org:
      internal_libraries:
        - { name: "@yourorg/ui", registry: "internal-npm", purpose: "UI components, layouts, filtering" }
        - { name: "YourOrg.Common", registry: "internal-nuget", purpose: ".NET shared utilities" }
      conventions_url: "<Confluence page with coding guidelines, if any>"
    mcp: [github, atlassian]
    jira_project: "LOAN"

  units:
    - { name: frontend,            repo: <url>/frontend.git,            stack: [angular, typescript] }
    - { name: backend-core,        repo: <url>/backend-core.git,        stack: [dotnet, csharp, mssql] }
    - { name: backend-integration, repo: <url>/backend-integration.git, stack: [dotnet, csharp] }
    - { name: common,              repo: <url>/common.git,              stack: [dotnet, csharp] }
    - { name: ui,                  repo: <url>/ui.git,                  stack: [nodejs, typescript] }
    - { name: config,              repo: <url>/config.git,              stack: [] }
    - { name: database-config,    repo: <url>/database-config.git,     stack: [mssql] }

  run:
    compose: ""                # fill when/if you have a workspace-level docker-compose

contracts:                     # keep this exact shape — machine-read by contract-check.sh
  - name: core-api
    file: docs/api/core-openapi.yaml        # path within backend-core
    provider: backend-core
    consumers: [frontend]
  - name: vendor-feed-schema
    file: schemas/vendor-feed.avsc          # path within backend-integration
    provider: backend-integration
    consumers: [backend-core]
```

Fill `contracts:` with whatever API/schema artifacts actually exist (OpenAPI specs, WSDLs,
Avro/JSON schemas). If none are written down yet, that's a finding in itself — start with the
one or two interfaces that break most often.

Commit `workspace.yaml` to a small internal meta-repo (e.g. `acme-loan-platform-harness`) so teammates
get it via clone; until then it can live uncommitted in the `acme-loan-platform/` folder.

**Finer-grained than one unit per repo?** If a unit is itself a monorepo or modulith and you need
to model components *inside* it (not just the repo as a whole), `workspace.yaml` supports an
optional, additive `schemaVersion: 2` block with `components:`/`relationships:` sections — see the
commented example at the bottom of `templates/workspace.yaml` and validate it with
`bash se-harness/plugins/se-harness/scripts/workspace-validate.sh`. This is opt-in and only needed
past the simple one-unit-per-repo case above; `contracts:`/`contract-check.sh` are unaffected
either way.

---

## Part 4 — Bootstrap each code repo

Do this for `frontend`, `backend-core`, `backend-integration`, `common`, `ui`. Start with
**one repo** (suggest `backend-core`) and get it fully working before repeating.

Two ways to drive the intake: **Copilot CLI** with the plugin installed (4.2) — run the
`harness-init` command it ships — or **VS Code Copilot Chat agent mode** with the prompt
below. Both produce identical artifacts. For VS Code: open the repo folder, open Copilot
Chat, select agent mode.

### 4.1 Run the intake as a prompt
Paste this into Copilot Chat (agent mode), adjusting the harness path:

> Read `../se-harness/plugins/se-harness/commands/harness-init.md` and execute its steps
> against this repository as an **existing project**. Also read
> `../se-harness/plugins/se-harness/commands/harness-scan.md` and
> `../se-harness/plugins/se-harness/skills/stack-detector/SKILL.md`, run
> `bash ../se-harness/plugins/se-harness/scripts/scan-evidence.sh` in the terminal, and use
> its output as the detection evidence. Interview me for anything you can't detect —
> especially organization context (internal libraries, preferred/banned libraries, coding
> conventions). Write the artifacts exactly as the command specifies. For AGENTS.md and
> CLAUDE.md, render the inner block to a temp file and splice it with
> `bash ../se-harness/plugins/se-harness/scripts/render-block.sh <target> <temp-file>` —
> never edit those files directly.

Expected results in the repo afterwards (verify each):
- `.harness/profile.yaml` — stack detected (e.g. backend-core: dotnet/csharp/mssql), org
  section filled (internal NuGet/npm libraries, conventions)
- `.env.harness` — created from the example; **fill secrets locally, never commit** (the
  gitignore lines are appended automatically)
- `.harness/memory/` — MEMORY.md, SCRATCHPAD.md, daily/, wiki/
- `.harness/org-rules.txt` — one `banned:` line per use-X-never-Y answer
- `AGENTS.md` + `CLAUDE.md` — with `SEAA:GENERATED` markers (CLAUDE.md costs nothing to keep
  and helps anyone using Claude tools later; Copilot reads both)

### 4.2 The Copilot CLI plugin (agents + skills + commands in one step)
If you followed Part 1 you already have it — the framework dual-publishes as a **Copilot CLI
plugin** ([plugins docs](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-cli-plugins));
Copilot CLI reads the same marketplace file Claude Code uses. The plugin gives every Copilot
CLI session: the **12-agent roster** (as `*.agent.md`), the **8 harness skills**
(context-injector conventions, stack-detector, requirement-grill, memory-keeper,
wiki-ingest/query/lint, coding-discipline — same SKILL.md standard as Claude), the **harness commands**
(goal/init/scan/bootstrap/sync/export, also registered as CLI skills — `copilot harness-goal …`),
and the **bundled enforcement hooks**. Note: plugin components are cached — after updating
the internal repo, run `copilot plugin update se-harness-copilot`.
*Enterprise-wide later*: admins can distribute it via
[enterprise-managed plugins](https://github.blog/changelog/2026-05-06-enterprise-managed-plugins-in-github-copilot-cli-are-now-in-public-preview/)
so it auto-installs for every developer.

### 4.3 Repo-level agent profiles + prompt files (coding agent & VS Code surfaces)
The CLI plugin doesn't cover the **coding agent on github.com** or **VS Code Chat**; give
those their repo-level equivalents:
```bash
cd frontend    # (each repo)
bash ../se-harness/plugins/se-harness/scripts/export-agents.sh copilot .   # → .github/agents/*.md
mkdir -p .github/prompts
cp ../se-harness/plugins/se-harness-copilot/commands/harness-goal.md .github/prompts/harness-goal.prompt.md
cp ../se-harness/plugins/se-harness-copilot/commands/harness-sync.md .github/prompts/harness-sync.prompt.md
```
(The `se-harness-copilot` command copies already have script paths rewritten to
`tools/harness/` — no editing needed if you vendor the scripts in 4.7.)
*Org-wide later*: your GitHub admin can move shared agent profiles into the enterprise
`.github-private` repo so every repo inherits them.

### 4.4 A thin `copilot-instructions.md`
Create `.github/copilot-instructions.md` containing just:
```markdown
Follow AGENTS.md — it is the source of truth for stack, organization conventions
(compose-first internal libraries), memory rules, and the delivery workflow.
```
Copilot merges instruction sources; keeping this thin avoids drift (AGENTS.md is regenerated
by the harness; this pointer never changes).

### 4.5 MCP (Jira/Confluence + GitHub)
With your firm's approval, add `.vscode/mcp.json` (or user-level MCP config) with the
Atlassian MCP server so story-writer flows can create Jira stories/XRay test cases. Reference:
`se-harness/templates/mcp.json.tmpl`. Secrets via environment, never in the file.

### 4.6 The two non-code repos (lighter treatment)
- `config`: no `.harness/` needed. Add a short hand-written `AGENTS.md` explaining the
  `.prop` naming scheme (`<service>-<env>.prop`), which env is which, and the change process.
  Agents working in other repos will read it when they touch config.
- `database-config`: same idea — a hand-written `AGENTS.md` describing object/domain layout
  and your migration/change process. Optionally a `.harness/profile.yaml` with `stack: [mssql]`
  if you want it in the workspace tooling.

### 4.7 Install the enforcement hooks (repo level — coding agent + VS Code)
**If you installed the CLI plugin (4.2), Copilot CLI already has the hooks** — the plugin
bundles them with plugin-root-relative paths. This step adds the **repo-level** copy that the
cloud coding agent and **VS Code** pick up (VS Code loads `.github/hooks/*.json` with
Claude-style semantics — [VS Code docs](https://code.visualstudio.com/docs/copilot/customization/hooks)).
Semantics differ per surface ([reference](https://docs.github.com/en/copilot/reference/hooks-reference)):
CLI/coding agent deny via JSON `permissionDecision` and exit 2 does **not** block there, while
VS Code honors exit 2 — the bundled adapter's deny-JSON output works on **all** surfaces, so
never wire the scripts in directly.

In each code repo:
```bash
# 1. Vendor the scripts so the repo is self-contained (CI and the cloud agent can't reach ../)
mkdir -p tools/harness
cp ../se-harness/plugins/se-harness/scripts/{copilot-hook-adapter.sh,gate-check.sh,org-validate.sh,memory-log-commit.sh,contract-check.sh} tools/harness/

# 2. Install the hook config
mkdir -p .github/hooks
cp ../se-harness/templates/copilot-hooks.json .github/hooks/se-harness.json
```
What you get: `preToolUse` — HITL gate (denies PR/push/deploy while no REQ is `approved`) and
contract-check (denies push when a provided contract changed, listing consumers);
`postToolUse` — org-rules feedback on edits and automatic commit/PR logging to the daily memory.

**Verify before trusting it** (payload field names differ between the coding agent and the
CLI): with a `draft` REQ, ask Copilot CLI (or the coding agent) to open a PR — it must be
denied with the gate's message. If it isn't, capture the real payload
(`"bash": "cat > /tmp/hook-payload.json"` temporarily) and adjust the scripts' field greps.
Hooks don't run in VS Code Chat — Part 6's CI checks cover that surface.

Commit everything except `.env.harness` in each repo via your normal PR process.

---

## Part 5 — Verify the bootstrap (10 minutes, per repo)

1. Open the repo in VS Code → Copilot Chat → ask: *"What internal libraries must this project
   prefer, and what's banned?"* — the answer must come from AGENTS.md's org section.
2. Ask: *"What is the workflow for implementing a new requirement here?"* — expect the
   goal-loop summary (REQ → approval → story → implement → tests → PR gates).
3. Run `bash ../se-harness/plugins/se-harness/scripts/scan-evidence.sh | head -40` in Git
   Bash — confirm it sees your manifests and internal package scopes.
4. On github.com, assign a trivial issue to the Copilot coding agent in that repo and confirm
   its PR description reflects AGENTS.md conventions.

---

## Part 6 — Enforcement: defense in depth (hooks + GitHub-native controls)

With 4.7 installed, agent-level enforcement runs via Copilot hooks on the coding agent and
CLI. Keep the **GitHub-native layer as well** — it binds humans (hooks only constrain the
agent), covers VS Code Chat (where hooks aren't documented), and survives a repo where
someone deleted `.github/hooks/`:

1. **HITL gates** — hook layer: 4.7's `preToolUse` gate denies PR/push/deploy without an
   approved REQ. Human layer: branch protection on every repo — require PR review (CODEOWNERS
   for sensitive paths like `database-config` and `config`), require status checks green, no
   direct pushes to main; PR template requires linking the `status: approved`
   `.harness/requirements/REQ-*.md`.
2. **Org-rules validation** — hook layer: `postToolUse` feedback on every agent edit. CI
   layer: an Actions job grepping the diff against `.harness/org-rules.txt` (same logic as
   `org-validate.sh`), so human-authored PRs are checked too.
3. **Contract impact** — hook layer: `preToolUse` contract-check denies push when a provided
   contract changed. CI layer: an Actions job in each *provider* repo running
   `contract-check.sh <base-sha>` against the workspace manifest (meta-repo as a second
   checkout); failure posts the consumer list on the PR.
4. **Memory logging** — hook layer: `postToolUse` auto-logs the agent's commits/PRs to the
   daily log. Human layer: adopt the `memory-keeper` conventions for your own work
   (end-of-task daily entry, typed links like `[[REQ-12]] solves [[pricing-lag]]`); a one-line
   PR-template reminder helps.

(Writing the two CI workflows is a small task — treat it as your first REQ.)

---

## Part 7 — Daily workflow (the goal loop on Copilot)

For a new feature/fix in, say, `backend-core`:

1. In VS Code (backend-core), Copilot Chat agent mode → run the `/harness-goal` prompt file
   with your goal. It will grill you (answer honestly, including what's out of scope), read
   memory, then create `.harness/requirements/REQ-NNN.md` via `new-requirement.sh`.
2. **You** review the REQ and flip `status: approved` — that is gate 1, and the PR template
   asks for this file.
3. Continue: story/test cases to Jira (Atlassian MCP), design, implementation (worktrees via
   `worktree-task.sh` if parallel tasks), tests. Cross-repo impact: run
   `bash ../se-harness/plugins/se-harness/scripts/contract-check.sh --` before pushing —
   CI re-checks it anyway.
4. PR through your normal review (gate 2 = human review + green checks).
5. Deploy per your firm's release process (gate 3) — the release-manager agent profile helps
   draft notes/checklists, but your existing change-management process is the authority.
6. Close the loop: daily-log entry; if domain knowledge changed (vendor spec, Confluence PRD),
   run a wiki-ingest prompt (paste `skills/wiki-ingest/SKILL.md` content as the instruction).

---

## Part 8 — Maintenance, troubleshooting, FAQ

**Framework updates**: pull the internal `se-harness` repo, then per repo run the
`/harness-sync` prompt file — it diffs profile/recommendations/templates (template drift is
detected via `template-hash.sh`) and refreshes only the `SEAA:GENERATED` blocks. Hand-written
content outside the markers is never touched.

**Troubleshooting**
- Scripts fail on Windows → run them from **Git Bash**, not PowerShell/cmd.
- `render-block.sh` "prepended block" message on a file you expected updated → the target had
  no `SEAA:GENERATED` markers; your content is preserved below the new block — merge manually once.
- Copilot ignores conventions → check AGENTS.md exists at repo root and nested where needed;
  large monolithic instruction files degrade — keep AGENTS.md tight, details in `.harness/memory/wiki/`.
- `contract-check.sh` silent → is `workspace.yaml` at `../workspace.yaml` relative to the repo,
  or set `WORKSPACE_MANIFEST=<path>`? Is the `contracts:` stanza shape exactly as templated?

**FAQ**
- *Should I download a public zip and copy it in?* Only as a last resort with security review;
  prefer an internal GitHub import (Part 1) so updates are pullable.
- *One folder with all repos cloned inside?* Yes — Part 2's side-by-side layout is assumed by
  the tooling.
- *Do I run an init in every repo?* Every **code** repo gets the full Part 4 treatment
  (`frontend`, `backend-core`, `backend-integration`, `common`, `ui`); `config` and
  `database-config` get the light treatment (4.6). Copilot's own "generate instructions"
  feature is optional — AGENTS.md is already the cross-tool source of truth.
- *Do we need Claude Code at all?* No — everything in this guide runs on Copilot. If the org
  later allows Claude Code, the same repos gain the full automation (hooks, gates, slash
  commands) with zero migration: the artifacts are identical.

---

## Part 9 — Example: single-repo project (the short path)

If your project is one repository (say `task-tracker`, an Express + React + Postgres app),
skip the workspace machinery entirely — no `workspace.yaml`, no contracts registry, no
side-by-side clone layout. You need the plugin (Part 1) and one bootstrap pass:

```bash
cd task-tracker
copilot            # start a CLI session in the repo
```

1. **Bootstrap** — run the init command (it's a CLI skill):
   ```
   copilot harness-init
   ```
   or in the session/VS Code Chat, use the intake prompt from 4.1. For an **existing** repo
   it runs the scan first (evidence collection + stack detection) and only interviews you for
   what it can't detect — expect questions about methodology, org/internal libraries, banned
   libraries, and conventions. For a **new** repo it interviews first, then scaffolds.
2. **Verify the artifacts** (same list as 4.1): `.harness/profile.yaml`, `.env.harness`
   (fill locally, never commit), `.harness/memory/`, `.harness/org-rules.txt`, `AGENTS.md` +
   `CLAUDE.md` with `SEAA:GENERATED` markers.
3. **Optional extras from Part 4**, all still apply per-repo: `.github/agents/` +
   `.github/prompts/` for the coding agent / VS Code (4.3), the thin
   `copilot-instructions.md` (4.4), MCP (4.5), repo-level hooks (4.7 — the CLI already has
   them from the plugin; vendor `tools/harness/` + `.github/hooks/` for the cloud coding
   agent and VS Code).
4. **First goal**:
   ```
   copilot harness-goal "Add CSV export to the reports page"
   ```
   It grills, writes `.harness/requirements/REQ-001.md`, waits for **you** to flip
   `status: approved`, then walks story → implement → test → PR with the gates enforced.

That's the whole difference: single-repo = Part 1 + this section; multi-repo = Parts 2–8.

---

## Part 10 — Updating or extending the plugin

Two situations: consuming an update someone else published, or making changes yourself.

### 10.1 Consuming an update
```bash
git -C se-harness pull                        # if you cloned the framework repo (Part 2)
copilot plugin update se-harness-copilot      # refresh the cached plugin
```
Then per managed repo, run the `harness-sync` command (or the `/harness-sync` prompt file) —
it diffs profile/recommendations/templates and refreshes **only** the `SEAA:GENERATED`
blocks; hand-written content is never touched. If you vendored scripts (4.7), re-copy them:
`cp ../se-harness/plugins/se-harness/scripts/*.sh tools/harness/`.

### 10.2 Making your own changes
The iron rule: **edit only `plugins/se-harness/` (the Claude-first source)** —
`plugins/se-harness-copilot/` and `.github/plugin/marketplace.json` are generated and will
be overwritten. To add e.g. a new agent or skill:

1. Add/edit files under `plugins/se-harness/` (`agents/*.md`, `skills/<name>/SKILL.md`,
   `commands/*.md`, `scripts/*.sh`).
2. Bump `version` in `plugins/se-harness/.claude-plugin/plugin.json` **and** in the
   `plugin.json` heredoc inside `scripts/build-copilot-plugin.sh` (the generated plugin's
   version) — version changes are how both ecosystems detect updates.
3. Regenerate the Copilot variant and the marketplace mirror:
   ```bash
   bash plugins/se-harness/scripts/build-copilot-plugin.sh
   ```
4. Sanity-check: `python -c "import json; json.load(open('plugins/se-harness-copilot/plugin.json'))"`,
   and if you have Claude Code, `claude plugin validate plugins/se-harness --strict`.
5. Commit both the source and the regenerated output, push, then reinstall/update the plugin
   (10.1). For a local-path install, uninstall + reinstall (components are cached).

---

## Part 11 — Publishing to the marketplaces

This repo **is already a marketplace** — `.claude-plugin/marketplace.json` (read by both
ecosystems) plus the generated mirror at `.github/plugin/marketplace.json` (Copilot's
canonical location). Publishing therefore has two tiers:

### 11.1 Your own marketplace (available today)
1. Run the build script (regenerates the Copilot plugin + mirrors the marketplace file).
2. Commit, push to GitHub (public, or internal for enterprise), and tag a release
   (`git tag v0.1.0 && git push --tags`) so zip-route users get a stable snapshot.
3. Anyone can now install with
   `copilot plugin marketplace add <owner>/<repo>` → `copilot plugin install se-harness-copilot@se-harness`.
4. **Enterprise-wide**: ask your GitHub admin to distribute it via
   [enterprise-managed plugins](https://github.blog/changelog/2026-05-06-enterprise-managed-plugins-in-github-copilot-cli-are-now-in-public-preview/) —
   auto-installed for every developer, hooks/MCP can be forced always-on for governance.

### 11.2 Community marketplaces (wider discovery)
Every Copilot CLI ships with two marketplaces pre-registered: **`github/copilot-plugins`**
(official) and **awesome-copilot** (community). Getting listed means opening a **PR against
their repo** adding an entry to their `marketplace.json` that points at yours:
```json
{ "name": "se-harness-copilot",
  "source": { "source": "github", "repo": "rbhattarai/se-harness", "path": "plugins/se-harness-copilot" } }
```
Read the target repo's CONTRIBUTING.md first — each has its own review/quality bar. Once
merged, users install with zero setup: `copilot plugin install se-harness-copilot`.
(The Claude-side equivalent is covered in [`setup-guide-claude.md`](./setup-guide-claude.md).)
