# se-harness

![se-harness — bootstrap an AI-agentic SDLC around any project: 3 hook-enforced approval gates, 11 SDLC agents, Claude Code + Copilot CLI](./docs/assets/social-preview.png)

**An AI-agentic SDLC harness you can bootstrap around any software project — new or
existing, any stack, from a single repo to a multi-repo product. AI agents do the work;
hooks make sure they can't ship without you.**

[![release](https://img.shields.io/github/v/release/rbhattarai/se-harness?label=release&color=2ea44f)](https://github.com/rbhattarai/se-harness/releases)
[![license](https://img.shields.io/github/license/rbhattarai/se-harness?label=license&color=97ca00)](./LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/rbhattarai/se-harness/ci.yml?branch=main&label=CI)](https://github.com/rbhattarai/se-harness/actions/workflows/ci.yml)
[![tests](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Frbhattarai%2Fse-harness%2Fbadges%2Ftests.json)](https://github.com/rbhattarai/se-harness/actions/workflows/ci.yml)
[![Claude Code](https://img.shields.io/badge/Claude_Code-se--harness-D97757?logo=claude&logoColor=white)](./docs/setup-guide-claude.md)
[![Copilot CLI](https://img.shields.io/badge/Copilot_CLI-se--harness--copilot-8957e5?logo=githubcopilot&logoColor=white)](./docs/setup-guide-copilot.md)
[![agents](https://img.shields.io/badge/SDLC_agents-12-6f42c1)](./plugins/se-harness/agents)
[![HITL gates](https://img.shields.io/badge/HITL_gates-3_hook--enforced-blue)](./plugins/se-harness/hooks)
[![platforms](https://img.shields.io/badge/macOS_%7C_Linux_%7C_Windows-supported-555)](./docs)
[![privacy](https://img.shields.io/badge/telemetry-none-success)](./PRIVACY.md)

AI coding agents are good at writing code and bad at process discipline. se-harness wraps
a full software-engineering lifecycle around them: it learns your project (scan +
interview), builds a memory of your code and domain, staffs it with 12 specialized
agents, and runs each goal through
requirement → stories → implementation → tests → PR → deploy — pausing at **three
human-approval gates that are enforced by hooks, not prompts**. The agent literally cannot
open the PR, push, or deploy until *you* flip `status: approved`.

The same goal loop scales from a single repo up to a whole product: single repo, mono-repo,
modulith, multi-repo, and hybrid topologies all go through `/harness-goal` the same way. For
the common case (your change touches one repo, even in a multi-repo product) nothing extra
happens — no new files, no added ceremony. Only when a change's impact spans **2 or more**
repos/components does the harness create an inspectable `workspace-plan.md`, hand it to a
`workspace-orchestrator` agent that works it directly (crossing into an already-cloned
sibling repo when a task lives there), and require a combined integration check — not just
each piece's own tests — before the usual gates will let anything ship.

One repo serves **both ecosystems**: Claude Code and GitHub Copilot CLI read the same
plugin marketplace.

<!-- DEMO GIF — record with docs/demo/README.md, save as docs/assets/demo.gif,
     then uncomment:

![se-harness demo: /harness-init scans the repo, /harness-goal hits the approval gate](./docs/assets/demo.gif)

-->

## What you get

- **Bootstrap, not boilerplate** — `/harness-init` scans existing repos first (stack +
  org-convention detection, evidence-based, you confirm) and interviews you only for what
  it can't detect. Output: `AGENTS.md` + `CLAUDE.md` inside idempotent generated-block
  markers (your hand edits survive re-runs), a committed `.harness/` profile, and a
  gitignored `.env.harness` for secrets.
- **A goal loop with real gates** — `/harness-goal "Add CSV export"` grills you until the
  requirement is unambiguous, writes `.harness/requirements/REQ-001.md`, then drives
  stories → design → parallel implementation in isolated worktrees → unit/integration/e2e
  tests → PR → deploy. Three gates (requirement, PR evidence, deploy) are blocked by a
  `PreToolUse` hook until you approve — exit-2 block on Claude Code, `permissionDecision`
  deny on Copilot.
- **A 12-agent SDLC roster** — architect, story-writer, backend/frontend implementers,
  db-engineer, unit + integration testers, e2e planner/generator/healer, release-manager, and
  a workspace-orchestrator for multi-component requirements (used only when one applies).
  Each agent gets only the tools its job needs.
- **3-tier memory** — committed project profile, append-only daily/topic logs with typed
  causal links, and a provenance-tracked domain wiki (ingest/query/lint skills). Tier 1
  (structural/code-graph) is an opt-in driver choice — CodeGraph, codebase-memory-mcp, or
  Graphify (`/harness-mem-graphify` builds and merges its index, per repo and workspace-wide;
  `/harness-goal` queries it for blast radius instead of grepping, when one's configured).
  Tier 3's domain wiki goes beyond code too: `/harness-mem-wiki` synthesizes Jira, Confluence,
  SharePoint, and NAS documents/video (transcribed via Graphify's video extra) into the
  workspace-level wiki — synthesis only, never a raw copy; the live source stays one MCP call
  or file-open away.
- **Methodology-aware, not methodology-locked** — pick **se-harness (built-in)** (this
  framework's own loop, zero extra dependencies) or **OpenSpec**, and `/harness-goal` actually
  drives it: OpenSpec's `/opsx:propose` seeds the requirement, se-harness's own gated
  implementers still do the work, `/opsx:archive` closes it out once deployed
  (`/harness-methodology-openspec` handles setup). BMAD and Spec Kit install for your own
  parallel use — honestly labeled as not yet delegated to, rather than implying parity.
- **Multi-repo aware** — declare products in `workspace.yaml` with a contracts registry;
  `contract-check.sh` blocks pushes that change a provided contract and names the consumer
  repos that would break.
- **Workspace-level orchestration** — `workspace.yaml` models single repo, mono-repo,
  modulith, multi-repo, and hybrid topologies in one additive schema (older manifests work
  unchanged). `/harness-init` bootstraps a whole product in one pass — clone from a
  `repos.txt` inventory (opt-in, confirmed — never a silent overwrite) or detect a mono-repo's
  sibling units, ask the shared methodology/structural-memory/org choices once, then loop
  every unit's own intake itself, no re-invoking per repo. `/harness-bootstrap`, `/harness-sync`,
  and `/harness-export` offer the same workspace-wide loop — run across every unit, name
  specific ones, or let the agent suggest units from a real staleness/gap signal. A change
  spanning 2+ repos gets a real plan (`workspace-plan.md`), a `workspace-orchestrator` agent to
  work it, and a combined integration check before `gate-check.sh` allows push/PR/deploy — full
  detail in [`docs/workspace-orchestration-plan.md`](./docs/workspace-orchestration-plan.md).
- **Drift-aware sync** — `/harness-sync` detects drift on four axes (profile,
  recommendations, templates, memory health), shows the diff first, and refreshes only
  generated blocks.
- **Exportable** — `/harness-export` compiles the agents and hooks for Copilot and Cursor
  (Codex reads `AGENTS.md` natively).
- **No telemetry, ever** — see [PRIVACY.md](./PRIVACY.md).

## Install

**Claude Code** (inside a session):

```
/plugin marketplace add rbhattarai/se-harness
/plugin install se-harness
```

**GitHub Copilot CLI**:

```bash
copilot plugin marketplace add rbhattarai/se-harness
copilot plugin install se-harness-copilot@se-harness
```

**Plugin installs restricted in your org?** Both setup guides cover the alternatives —
internal GitHub Enterprise import (preferred, updates stay pullable) and offline
zip → local-path marketplace, plus a no-plugin prompt-driven fallback:
[Claude §1.2](./docs/setup-guide-claude.md) · [Copilot §1.2–1.3](./docs/setup-guide-copilot.md).

## Quickstart (5 minutes)

**Single repo** — in your project, run `/harness-init` (Claude) or `copilot harness-init`
(Copilot CLI). Existing repos get scanned first; you're interviewed only for what can't be
detected. Then `/harness-bootstrap` for opt-in companion tooling, and your first goal:

```
/harness-goal "Add CSV export to the reports page"
```

It writes `.harness/requirements/REQ-001.md` and the gate hook blocks PR/push/deploy until
**you** flip `status: approved`.

**Multi-repo product** — either clone all repos side-by-side yourself and add a
`workspace.yaml` (from [`templates/workspace.yaml`](./templates/workspace.yaml): units,
shared org context, and a `contracts:` registry), or run `/harness-init` from an empty
workspace folder with a `repos.txt` listing the repos. It clones them for you (opt-in, shows
the plan, never overwrites), then offers to bootstrap every repo in the same pass — the
methodology/structural-memory/org choices get asked once, not once per repo, and it loops the
rest itself rather than telling you to re-invoke it in each one.

**Want to try it without risking your own repo?** See the worked example below, using the
companion demo repo [**demo-loan-app**](https://github.com/rbhattarai/demo-loan-app).

## Worked example — demo-loan-app

[demo-loan-app](https://github.com/rbhattarai/demo-loan-app) is a real, live two-app loan
product used as this project's own companion demo — not a toy. `loan-webapp` (borrowers
request loans) and `lending-webapp` (lenders approve/reject them) are separate Express 5 /
TypeScript apps sharing a flat-file JSON store, syncing in real time over a webhook + SSE.
That shared surface is exactly what the contract registry below is for.

**Repo structure** (trimmed — each app also has its own `test/`, `eslint.config.js`,
`tsconfig.json`, `Dockerfile`):

```
demo-loan-app/
├── workspace.yaml              # topology: mono-repo · 2 units · 2 contracts (pre-authored)
├── docker-compose.yml          # both apps + the shared data/ volume
├── contracts/
│   ├── loan-record.md          # shared loan shape — provider: loan-webapp
│   └── notify-webhook.md       # webhook/SSE protocol — provider: lending-webapp
├── data/                       # shared JSON store — a data surface, not a unit (see contracts)
├── loan-webapp/                 # borrower side — https://localhost:3000
│   ├── package.json
│   ├── src/
│   │   ├── app.ts, server.ts, events.ts
│   │   ├── routes/{index,loan}.ts
│   │   ├── views/{index,loan}.ejs
│   │   └── data/loanStore.ts
│   └── test/
└── lending-webapp/               # lender side — https://localhost:3001
    ├── package.json
    ├── src/
    │   ├── app.ts, server.ts, events.ts
    │   ├── routes/{index,lendor,loan}.ts
    │   ├── views/{index,lendor,loan}.ejs
    │   └── data/approverStore.ts
    └── test/
```

Commands, in order, and what actually happens at each one:

1. **`git clone https://github.com/rbhattarai/demo-loan-app && cd demo-loan-app`** —
   `workspace.yaml` is already committed here (pre-authored for the demo): `topology:
   mono-repo`, both apps as `units:`, both contracts registered. Neither app has its own
   `.harness/` yet — that's what the next command creates.
2. **`docker compose up --build`** — both apps come up (`:3000`, `:3001`), sharing `data/`,
   syncing live over the webhook/SSE pair. Leave this running.
3. **`/harness-init`** (Claude Code) or `copilot harness-init` (Copilot CLI), run once **at the
   repo root**: since `workspace.yaml` already declares two sibling units, mono-repo detection
   confirms it rather than proposing it fresh, then asks once whether to bootstrap both units
   now. Say yes, and it asks the shared questions exactly once — methodology (se-harness
   built-in / OpenSpec / BMAD / Spec Kit), structural-memory driver (CodeGraph /
   codebase-memory-mcp / Graphify / defer) — then loops into `loan-webapp` (stack
   auto-detected: Node, TypeScript, Express, EJS, Docker — you confirm, nothing else to ask)
   and `lending-webapp` (same detection, shared choices inherited silently, no re-asking).
   Result: `AGENTS.md` + `CLAUDE.md` + `.harness/` in each app, plus a workspace-level
   `.harness/memory/` at the repo root logging the shared choices.
4. **`/harness-bootstrap`**, run at the repo root: offers the same once-asked workspace-wide
   question — every unit, specific ones, or let it suggest. Installs each unit's recommended
   companion tooling per its own stack (e.g. Playwright for e2e) and records it in each unit's
   lockfile.
5. **`cd lending-webapp`**, then
   `/harness-goal "When a lender rejects a loan, they must give a rejection reason, and the
   borrower must see it on the loan-webapp dashboard"` — this is the flagship cross-unit case:
   - **Grill + impact map**: interrogates the ambiguity (free text or picklist? required on
     reject only?); the deep-dive step builds an impact map from `workspace.yaml` — this touches
     both units, so the count is 2.
   - ⛔ **Gate 1**: writes `REQ-001.md` **and** `REQ-001/workspace-plan.md` (one row per unit) in
     the same stop — blocked until you flip `status: approved`, which approves both at once.
   - **`workspace-orchestrator`** works the plan directly: implements the `lending-webapp` row,
     crosses into `loan-webapp` for its row (trivial here — already checked out side by side),
     isolated worktrees and unit/integration tests either way.
   - **Contract impact, automatically**: the change adds `rejectionReason` to the loan record →
     `contract-check.sh` flags `loan-webapp` as an impacted consumer and links a task to the
     same REQ — you don't have to notice this yourself.
   - **Integration check**: brings up `docker-compose.yml` from the combined result and
     re-verifies — passing each unit's own tests isn't the same as the SSE sync actually
     working end to end. Only then does the plan reach `integration: passed`.
   - ⛔ **Gate 2** (PR evidence: both rows + integration result) → ⛔ **Gate 3** (deploy
     approval) — same hook-enforced mechanism as a single-repo goal, nothing special-cased for
     being cross-unit.

Full walkthrough with exact commands, demo-hygiene resets between takes, and smaller
single-unit goals to try first: [`docs/demo/README.md`](./docs/demo/README.md#part-2--multi-unit-walkthrough-the-loan-product).

### Commands

| Command | What it does |
|---|---|
| `/harness-init` | Intake interview (+ scan for existing repos) → generates all per-project artifacts; clones/loops a whole workspace in one pass |
| `/harness-scan` | Brownfield detection: evidence collector → confirm → merge into profile; workspace-wide in one pass |
| `/harness-bootstrap` | Recommends companion plugins/CLIs/MCP servers from your profile; opt-in install + lockfile; workspace-wide in one pass |
| `/harness-goal` | The goal loop: supervisor over the agent roster, 3 hook-enforced approval gates |
| `/harness-sync` | Four-axis drift detection → diff-first report → confirmed refresh of generated blocks; workspace-wide in one pass |
| `/harness-export` | Compile agents + hooks for Copilot / Cursor (Codex reads `AGENTS.md` natively); workspace-wide in one pass |
| `/harness-mem-graphify` | Build/maintain Graphify structural-memory indexes — per-repo, and merged at workspace level |
| `/harness-methodology-openspec` | Install/init OpenSpec where chosen — `/harness-goal` drives its actual propose/archive lifecycle |
| `/harness-mem-wiki` | Synthesize Jira/Confluence/SharePoint/NAS docs/NAS video into the workspace-level domain wiki `/harness-goal` queries |

## Documentation

- **[Claude Code setup guide](./docs/setup-guide-claude.md)** — install (+ restricted-org
  alternatives), single-repo and multi-repo worked examples, extending and publishing
- **[GitHub Copilot setup guide](./docs/setup-guide-copilot.md)** — CLI plugin, coding
  agent, VS Code, enterprise rollout, same examples
- **[Interop matrix](./docs/interop-matrix.md)** — component × platform support, plus
  verified platform schema notes in [`docs/claude/`](./docs/claude) and
  [`docs/copilot/`](./docs/copilot)
- **[Demo walkthroughs](./docs/demo/README.md)** — over the companion
  [demo-loan-app](https://github.com/rbhattarai/demo-loan-app) repo: multi-unit init,
  contract checking, cross-unit goal (and the README GIF recording guide)
- **[Workspace-orchestration plan](./docs/workspace-orchestration-plan.md)** — single repo →
  mono-repo → modulith → multi-repo → hybrid: the impact map, `workspace-plan.md`, the
  `workspace-orchestrator` agent, and the combined integration check, phase by phase

## Status

**[v1.0.0](https://github.com/rbhattarai/se-harness/releases/tag/v1.0.0)** tagged six
commands and a 199-test suite; `main` has since grown to **nine commands and a 212-test
suite** (not yet re-tagged) — `/harness-mem-graphify`, `/harness-methodology-openspec`, and
`/harness-mem-wiki`, plus the workspace-wide loop now shared by
`/harness-init`/`-bootstrap`/`-sync`/`-export`.
**Workspace-level orchestration** — single repo → mono-repo → modulith → multi-repo → hybrid,
one goal loop that coordinates across repos, with the orchestration overhead scaling to zero
for the common single/few-component case — is **complete**: see
[`docs/workspace-orchestration-plan.md`](./docs/workspace-orchestration-plan.md) for the full
phase-by-phase breakdown, including the handful of open design decisions it was honest enough
to leave unresolved rather than claim done (per-component scoping of non-code sources; true
parallel execution of independent workspace-plan rows, which today are worked in correct
dependency order but one at a time).

**Run against two real multi-repo products since v1.0.0** (not just fixtures): a mono-repo on
Claude Code, and a 20-repo multi-repo product on Copilot CLI. Both surfaced real gaps, now
fixed — a mono-repo detection heuristic that missed a legitimate sibling-directory shape with
no formal workspace-tool marker; a Copilot-specific script-vendoring gap in a brand-new
workspace root; `/harness-init`, `/harness-bootstrap`, `/harness-sync`, and `/harness-export`
all requiring manual re-invocation per repo instead of looping a whole workspace themselves;
and `/harness-goal` querying structural memory and driving a chosen methodology by name
(Graphify, OpenSpec) rather than falling back to Grep/Glob or running its own loop
undelegated.

The **structural-memory** (CodeGraph vs. codebase-memory-mcp vs. Graphify) and **methodology**
(BMAD vs. Spec Kit vs. OpenSpec vs. se-harness's own loop) bake-offs are both still open by
design — pick one, defer, or mix per project — but Graphify and OpenSpec are now the
reference implementations with real `/harness-goal` integration; the other four install but
don't change `/harness-goal`'s behavior yet. Also on the roadmap: a web profile-builder.
Full detail, including what's still an open gap: [development history](./docs/development-history.md) ·
plan and research log in [`docs/brainstorm.md`](./docs/brainstorm.md).

## Repo layout

```
.claude-plugin/marketplace.json      # this repo IS a marketplace — read by Claude Code AND Copilot CLI
.github/plugin/marketplace.json      # GENERATED mirror (Copilot canonical location) — never edit
plugins/se-harness/                  # the harness plugin (source of truth)
  commands/                          # the nine /harness-* commands
  agents/                            # 12-agent SDLC roster (narrow tools per agent)
  skills/                            # context-injector, stack-detector, memory-keeper, wiki-*,
                                      # requirement-grill, coding-discipline
  hooks/hooks.json + scripts/        # gate-check, org-validate, memory-log, contract-check,
                                      # workspace-clone/-validate/-scan-evidence, splicer
plugins/se-harness-copilot/          # Copilot CLI variant — GENERATED by build-copilot-plugin.sh
registry/recommendations.json        # profile → plugin mappings (recommender data; honest gaps)
templates/                           # profile/env/requirement/AGENTS/CLAUDE/mcp/workspace/
                                      # workspace-plan + memory seeds
docs/                                # setup guides, interop matrix, platform schema notes, demo guide
tests/                               # 212-test suite run in CI
```

## Contributing / publishing

Edit only `plugins/se-harness/` (the Claude-first source of truth); regenerate the Copilot
variant and marketplace mirror with `bash plugins/se-harness/scripts/build-copilot-plugin.sh`.
Full update/extension and marketplace-publishing instructions:
[Claude guide Parts 5–6](./docs/setup-guide-claude.md) ·
[Copilot guide Parts 10–11](./docs/setup-guide-copilot.md).

> Note: the Claude Code and Copilot plugin/hook schemas evolve quickly — verify manifests
> against the [Claude plugin docs](https://code.claude.com/docs/en/plugins-reference) and
> [Copilot plugin docs](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference)
> before releasing.
