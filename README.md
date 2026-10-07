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
  causal links, and a provenance-tracked domain wiki (ingest/query/lint skills).
- **Multi-repo aware** — declare products in `workspace.yaml` with a contracts registry;
  `contract-check.sh` blocks pushes that change a provided contract and names the consumer
  repos that would break.
- **Workspace-level orchestration** — `workspace.yaml` models single repo, mono-repo,
  modulith, multi-repo, and hybrid topologies in one additive schema (older manifests work
  unchanged). `/harness-init` can bootstrap a whole product from a `repos.txt` inventory
  (opt-in, confirmed cloning — never a silent overwrite); `/harness-scan` can scan every
  declared unit in one pass. A change spanning 2+ repos gets a real plan
  (`workspace-plan.md`), a `workspace-orchestrator` agent to work it, and a combined
  integration check before `gate-check.sh` allows push/PR/deploy — full detail in
  [`docs/workspace-orchestration-plan.md`](./docs/workspace-orchestration-plan.md).
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
workspace folder with a `repos.txt` listing the repos — it'll offer to clone them for you
(opt-in, shows the plan, never overwrites). Either way, run `/harness-init` again inside
each code repo to bootstrap it.

**Want to try it without risking your own repo?** The companion demo repo
[**demo-loan-app**](https://github.com/rbhattarai/demo-loan-app) is a live two-app loan
product — `loan-webapp` + `lending-webapp` syncing in real time over a shared data
store — with a ready-made `workspace.yaml` and contract registry. Clone it,
`docker compose up --build`, then follow the
[multi-unit walkthrough](./docs/demo/README.md#part-2--multi-unit-walkthrough-the-loan-product):
init per unit, watch `contract-check` name the consumer that a schema change would break,
and run a cross-unit goal end to end.

### Commands

| Command | What it does |
|---|---|
| `/harness-init` | Intake interview (+ scan for existing repos) → generates all per-project artifacts |
| `/harness-scan` | Brownfield detection: evidence collector → confirm → merge into profile |
| `/harness-bootstrap` | Recommends companion plugins/CLIs/MCP servers from your profile; opt-in install + lockfile |
| `/harness-goal` | The goal loop: supervisor over the agent roster, 3 hook-enforced approval gates |
| `/harness-sync` | Four-axis drift detection → diff-first report → confirmed refresh of generated blocks |
| `/harness-export` | Compile agents + hooks for Copilot / Cursor (Codex reads `AGENTS.md` natively) |
| `/harness-mem-graphify` | Build/maintain Graphify structural-memory indexes — per-repo, and merged at workspace level |
| `/harness-methodology-openspec` | Install/init OpenSpec where chosen — `/harness-goal` drives its actual propose/archive lifecycle |

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

**[v1.0.0](https://github.com/rbhattarai/se-harness/releases/tag/v1.0.0) is out**: all six
commands, the 12-agent roster, the memory tiers, the hooks, and the Copilot export are
implemented and script-tested (199-test suite in CI). **Workspace-level orchestration** —
single repo → mono-repo → modulith → multi-repo → hybrid, one goal loop that coordinates
across repos, with the orchestration overhead scaling to zero for the common single/
few-component case — is **complete**: see
[`docs/workspace-orchestration-plan.md`](./docs/workspace-orchestration-plan.md) for the
full phase-by-phase breakdown, including the handful of open design decisions it was honest
enough to leave unresolved rather than claim done (per-component scoping of non-code
sources; true parallel execution of independent workspace-plan rows, which today are worked
in correct dependency order but one at a time). Not yet been run against a real multi-repo
product in practice — if you try it, that's the gap most likely to surface something the
test suite couldn't catch. Also on the roadmap: a web profile-builder and a structural-memory
driver bake-off (CodeGraph vs. codebase-memory-mcp vs. Graphify). Details:
[development history](./docs/development-history.md) · plan and research log in
[`docs/brainstorm.md`](./docs/brainstorm.md).

## Repo layout

```
.claude-plugin/marketplace.json      # this repo IS a marketplace — read by Claude Code AND Copilot CLI
.github/plugin/marketplace.json      # GENERATED mirror (Copilot canonical location) — never edit
plugins/se-harness/                  # the harness plugin (source of truth)
  commands/                          # the six /harness-* commands
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
tests/                               # 199-test suite run in CI
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
