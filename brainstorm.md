# Multi AI Agentic Software Engineering Framework — Plan & Research Log

Working repo name: `software-engineering-ai-agents-bootstrap`

This document has two parts: **Part A** is the plan (goal, solution-scan verdict, architecture, step-by-step build). **Part B** is the research log that led to it (10 research rounds, kept as evidence and reference).

---

# Part A — The Plan

## A1. Goal (full specification)

Build a **tech-stack-agnostic, methodology-agnostic, multi-client** framework that lets anyone bootstrap an AI-agentic SDLC setup (plan → architecture → stories/tasks → code → unit tests → integration tests → e2e tests → deploy → release) for any project, new or existing, composed of AI Agents, Skills, Rules, Instructions, Plugins, Workflows, MCP, etc.

### Intake
- Ask whether the project is **new or existing**.
- **New**: ask/offer options for code repo, non-code repos (Jira/Confluence/SharePoint/etc.), methodology, tech stack, DevOps, cloud. Store in env variables / env file.
- **Existing**: ask about code repo(s), non-code repos, methodology; **scan** repos to detect tech stack, DevOps, cloud; create long-term memory; add/update env file.
- **Organization context** (before finalizing AGENTS.md/CLAUDE.md): company-developed internal libraries, preferred/mandated third-party libraries, org-specific coding conventions and guidelines. **New projects**: always ask the user. **Existing projects**: detect automatically from the scan (private package scopes/registries, lint/format configs, recurring internal imports), then confirm/supplement with the user.
- Build a comprehensive `AGENTS.md` / `CLAUDE.md` holding every important project detail; a **scan skill** keeps it updated.

### Bootstrap (creates `.claude/` + required components)
- **Long-term memory of the entire codebase**, continuously maintained through enhancements, bug fixes, hot fixes.
- **Long-term memory from enterprise artifacts**: Jira Epics/Stories, Confluence PRDs, XRay/Zephyr test cases, SharePoint pages, video recordings, Word/Excel/PDF on NAS.
- **Indexed + summarized context** from long/short-term memory fed to the LLM per request (see A5 — improved approach adopted).

### The goal workflow (loop engineering)
- Process a user goal via loop-engineering steps; **grill the user** with clarifying questions on goal/requirements.
- Deep-dive long-term memory (code + artifacts) when more detail is needed.
- Produce a **refined requirement** file (see A5 for location change from `.temp`).
- Create/update **User Story + Test Cases** from the refined requirement.
- Implement via specialized agents (backend, frontend, unit tests, integration tests, DB tables, configs, service layers).
- Convert test cases to **E2E Playwright tests** via the existing planner/generator/healer test agents.
- Raise a **GitHub PR**; deploy + run locally via **Docker Compose**; deploy to **cloud** (AWS/Azure/GCP/Vercel).
- **Human-in-the-loop** decisions throughout.

## A2. Solution scan: does anything already do this?

**Verdict: No.** Across 10 research rounds (~30 repos/products verified — Part B), nothing covers the full spec. The closest candidates and their gaps:

| Solution | Covers | Pros | Cons / gaps vs. spec |
|---|---|---|---|
| **[BMAD-METHOD](https://github.com/bmad-code-org/bmad-method)** (+ [plugin port](https://github.com/PabloLION/bmad-plugin)) | Methodology: plan→PRD→architecture→stories→dev→QA | Most mature (~49k★), 21+ agents, 50+ workflows, plugin-installable | No memory, no enterprise ingestion, no deploy, no scan/interview, single repo |
| **[GitHub Spec Kit](https://github.com/github/spec-kit)** / **[OpenSpec](https://github.com/Fission-AI/OpenSpec/)** | Lightweight SDD workflow | Simple; OpenSpec is brownfield-friendly (spec deltas), ~52k★ | Workflow only — no agents/memory/deploy |
| **[ECC](https://github.com/affaan-m/ECC)** | Breadth: 277 skills, 67 agents, rules, hooks, MCP configs, scaffolds | Huge cherry-pickable content pool; cross-harness architecture doc | Monolith; community verdict "over-engineered, cherry-pick don't adopt"; no recommender, no goal loop (B4) |
| **[gstack](https://github.com/garrytan/gstack)** | Opinionated pipeline incl. ship/deploy commands | Real methodology (Think→…→Ship), cheap multi-host adapters | All-or-nothing, opinion-locked, no memory/enterprise/interview (B5) |
| **[claude-code-setup](https://claude.com/plugins/claude-code-setup)** (Anthropic) | Analyzes repo → recommends MCP/skills/hooks/subagents/commands | Official, verified, ~179k installs — validates the recommender concept | **Read-only**: recommends, never installs/generates; no new-repo flow (B9) |
| **[agency-agents](https://github.com/msitarzewski/agency-agents)** | Multi-client picker + installer, 230+ agents, 15 clients | Proven convert/install compiler (B6) | Personas, not a workflow engine; no memory, no goal loop |
| **[agentic-sdlc-plugin](https://github.com/ajaywadhara/agentic-sdlc-plugin)** | Closest single-plugin e2e loop: 10 commands, idea→PRD→wireframes→architecture→TDD→Playwright-MCP testing→8-agent QA gate (≥85 score) | Best *pattern reference* for the goal loop + scored QA gate | 1★, single-day repo (Feb 2026); **greenfield-only**; no Jira/Confluence, no Docker/cloud deploy, gates automated-only, no brownfield scan |
| **[Claude Agent for Jira](https://www.atlassian.com/blog/company-news/claude-agent-for-jira)** + [atlassian plugin](https://claude.com/plugins/atlassian) | Assign Jira issue → agent codes → draft PR, status streamed back to Jira | Official Atlassian; covers the Jira↔PR slice with HITL (humans review/merge/deploy) | Only that slice — no bootstrap, memory, testing pipeline, or deploy |
| **[Multica](https://github.com/multica-ai/multica)** / **[OpenHands](https://github.com/OpenHands/OpenHands)** | Agent coordination board / autonomous dev platform | Production-grade execution layers (39k★ / 81k★) | Execution surfaces, not bootstrap/config layers; heavy infra (B5, B10) |
| Memory components: **[CodeGraph](https://github.com/codegraph-ai/CodeGraph)**, **[agentmemory](https://github.com/jayzeng/agentmemory)**, **[mem0](https://github.com/mem0ai/mem0)**, **[Karpathy's LLM-wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)** | The three memory tiers (structural / session / domain synthesis) | Each is the best-of-breed for its tier (B7) | Components, not solutions |

**Recommendation: hybrid.** Build one thin **harness plugin + marketplace** (the B9 architecture) whose value is the *composition layer* nothing else has — interview/scan → recommend → install → generate → goal-loop → sync — and delegate everything already solved to existing pieces: methodology to BMAD/Spec Kit/OpenSpec plugins, content to official-marketplace plugins, memory to the three-tier design, Jira↔PR to the Atlassian integrations, e2e testing to your existing Playwright agents.

## A3. Target architecture

One marketplace repo (`software-engineering-ai-agents-bootstrap`) hosting one primary plugin (`se-harness`) plus original content:

```
software-engineering-ai-agents-bootstrap/
  .claude-plugin/marketplace.json         # this repo IS a marketplace
  plugins/se-harness/
    .claude-plugin/plugin.json
    commands/    harness-init.md  harness-scan.md  harness-goal.md  harness-sync.md
    skills/      stack-detector/  recommender/  wiki-ingest/  wiki-query/  wiki-lint/
                 context-injector/  requirement-grill/
    agents/      architect.md  story-writer.md  implementer-backend.md  implementer-frontend.md
                 db-engineer.md  unit-tester.md  integration-tester.md
                 e2e-planner.md  e2e-generator.md  e2e-healer.md      # from the Playwright framework
                 release-manager.md
    hooks/       quality-gates (phase-transition blocks), memory-maintenance (post-merge updates)
    .mcp.json    # github, atlassian, codegraph, cloud provider(s)
  registry/      # recommender data: profile→plugin-ID mappings, methodology contract, client defs (tools.json pattern, B6)
  templates/     # AGENTS.md/CLAUDE.md with GENERATED blocks, profile.yaml, docker-compose snippets
```

Per-project artifacts it creates:
- `.harness/profile.yaml` (committed: stack, methodology, topology, non-secret config, and an `org:` section — internal libraries, preferred/mandated libraries, org conventions) + `.env.harness` (gitignored: tokens, URLs with credentials)
- `AGENTS.md` (universal core — Copilot/Cursor/Codex all read it, Copilot even reads CLAUDE.md directly, B10) + thin `CLAUDE.md`, both with idempotent `<!-- SEAA:GENERATED -->` blocks
- `.harness/memory/` — three tiers (B7): CodeGraph index (rebuildable, not committed), session log (MEMORY.md/daily/topics, committed), domain wiki (committed, LLM-maintained via ingest/query/lint)
- `.harness/requirements/REQ-*.md` — refined requirements (see A5)
- `agentstack.lock` — installed components + versions, drives `/harness-sync` diffs

## A4. Step-by-step build plan

**Phase 0 — Skeleton.** Install the `plugin-dev` plugin; create the marketplace repo + `se-harness` plugin scaffold; CI check (agency-agents `check-tools.sh` pattern, B6) validating marketplace.json ↔ plugin contents.

**Phase 1 — `/harness-init` (intake). ✅ IMPLEMENTED** (`plugins/se-harness/commands/harness-init.md` + `scripts/render-block.sh`, splice mechanics smoke-tested). AskUserQuestion-driven interview: new vs. existing; code repo(s); non-code sources (Jira project keys, Confluence spaces, SharePoint sites); methodology choice (BMAD / Spec Kit / OpenSpec); for new projects: stack/devops/cloud pickers with presets (Python, Node+React, Node+Angular) **plus an organization-context round before AGENTS.md/CLAUDE.md is finalized**: company-developed internal libraries (name, registry/scope, what they're for), preferred/mandated third-party libraries (e.g. "use our fork of X", "date handling = dayjs, never moment"), and org coding conventions/guidelines (naming, error handling, PR rules — or a pointer to the Confluence/SharePoint page holding them, which the wiki-ingest skill can then pull in). Answers land in `profile.yaml` under an `org:` section and render into a dedicated "Organization conventions & libraries" part of the generated block. Writes `profile.yaml` + `.env.harness`, generates AGENTS.md/CLAUDE.md generated blocks.

**Phase 2 — `/harness-scan` (brownfield). ✅ IMPLEMENTED** (`commands/harness-scan.md` + `skills/stack-detector/` + `scripts/scan-evidence.sh`, collector smoke-tested against a synthetic repo). LLM-based stack-detector skill (not regex — B2) + CodeGraph MCP indexing for structure; proposes detected stack/devops/cloud for user confirmation; merges into profile and AGENTS.md/CLAUDE.md generated blocks. Re-runnable anytime (the "scan skill" of the spec). **Also auto-detects organization context**: internal libraries via private registry config (`.npmrc` scopes, `NuGet.config`, private PyPI index, Artifactory/Nexus URLs) and recurring `@company/*`-style imports; preferred libraries via what the codebase consistently uses; conventions via lint/format configs (`.eslintrc`, `.editorconfig`, analyzers) plus the naming/error-handling/layering patterns the LLM infers from the code itself (same job as ECC's `inherit-legacy-style` skill, B4 — scan implicit conventions, resolve conflicts with the user one at a time, crystallize into enforceable rules). Detected org context is presented for confirmation — the user can correct, and add anything undetectable (e.g. an unwritten team rule) — then merged into `profile.yaml`'s `org:` section like Phase 1.

**Phase 3 — Bootstrap generator. ✅ IMPLEMENTED** (`commands/harness-bootstrap.md` + `registry/recommendations.json` + `templates/mcp.json.tmpl` + the 11-agent roster in `plugins/se-harness/agents/`; JSON + frontmatter validated). From profile: install the chosen methodology plugin; install stack-matched marketplace plugins (LSPs, `playwright`, database, `deploy-on-aws`/`azure`/`cloudflare`, `dash0`/`langfuse-observability` for the observability engine); write the SDLC phase agents (roster above); generate quality-gate hooks (via `hookify` patterns); write `.mcp.json` (github, atlassian, codegraph); write `agentstack.lock`.

**Phase 4 — Memory tiers. ✅ IMPLEMENTED** (tier 3: `skills/wiki-ingest|wiki-query|wiki-lint`; tier 2: `skills/memory-keeper` conventions + deterministic `scripts/memory-log-commit.sh` PostToolUse hook auto-logging commits/PRs/merges to the daily log — tested, incl. an escaped-quote JSON-extraction fix that also closed an under-blocking hole in gate-check.sh; tier 1 ships via Phase 3 bootstrap + A7 bake-off).
1. *Structural*: a code-graph MCP server — two candidates to evaluate (B7, B12): CodeGraph (38 languages, `pr_context` blast-radius) vs. **codebase-memory-mcp** (158 languages + hybrid LSP, Cypher queries, ADR tracking, and a **team-shareable committed graph artifact** so teammates skip reindexing). Rebuildable either way.
2. *Session/decision*: agentmemory-style committed markdown (MEMORY.md index + daily + topics), maintained by post-task/post-merge hooks.
3. *Domain wiki*: Karpathy ingest/query/lint skills running over MCP connectors — `atlassian` plugin for Jira/Confluence, SharePoint MCP; only the synthesis persists (git-committed), retrieval stays live per source. Video/NAS deferred to v2 (needs transcription/OCR infra).

**Phase 5 — `/harness-goal` (the loop-engineering workflow). ✅ IMPLEMENTED** (`commands/harness-goal.md` rewired as supervisor orchestration over the agent roster + `skills/requirement-grill/` + `scripts/new-requirement.sh` (REQ scaffolding, YAML-safe goal escaping, tested) + `scripts/worktree-task.sh` (create/remove/list, refuses dirty removal, auto-gitignores `.worktrees/`, tested)). Pipeline with status-frontmatter artifacts and gates:
1. Intake goal → **grill**: requirement-interrogation skill asks until acceptance criteria are unambiguous (AskUserQuestion).
2. **Deep-dive**: query CodeGraph (impacted code) + wiki (related PRDs/stories/decisions) + session log (prior attempts).
3. Write **refined requirement** → `.harness/requirements/REQ-x.md` (status: draft → approved). ⛔ *HITL gate: user approves requirement.*
4. **Story + test cases**: methodology plugin produces story/tasks; write to Jira + XRay/Zephyr via atlassian MCP (system of record) with local artifact copies; traceability ID threads through commits (B1 principle 2).
5. **Implement**: supervisor fans out to phase agents in **git worktrees** (isolation, B1 principle 6) — backend/frontend/DB/config/service + unit & integration tests; hooks block progression until lint/tests pass (borrow agentic-sdlc-plugin's scored-gate idea, add human review).
6. **E2E**: planner → generator → healer Playwright agents convert the test cases to running e2e specs.
7. ⛔ *HITL gate: review of diff + test evidence* → **PR** via github MCP (draft PR, story-linked).
8. **Local verify**: generate/update docker-compose; build + run the full app locally; smoke-check.
9. ⛔ *HITL gate: deploy approval* → **cloud deploy** via the profile's provider plugin. Release notes via release-manager agent.

**Phase 6 — `/harness-sync` + maintenance. ✅ IMPLEMENTED** (`commands/harness-sync.md` + `scripts/template-hash.sh`, tested: deterministic output, drift detected on template change). Four drift axes — profile (re-scan diff), recommendations (registry × profile vs. lockfile; declined items never re-nagged), templates (hash comparison vs. lockfile baseline), memory health (wiki-lint recency, MEMORY.md size) — diff-first/ask/apply, refreshing only generated blocks; `syncs:` history appended to the lockfile. Deterministic memory maintenance (commit/PR auto-logging) shipped in Phase 4.

**Phase 7 (v2+). ⚙ PARTIALLY IMPLEMENTED** — the buildable pieces are done:
- ✅ **Workspace manifest** (`templates/workspace.yaml` — units with `path:`/`repo:`, `shared:` block, machine-readable `contracts:` registry) wired into `/harness-init` topology step.
- ✅ **Multi-repo tier 2 — contract-check** (`scripts/contract-check.sh`, tested): deterministic consumer-impact flagging when a provided contract changes; dual-mode (standalone `--`/base-ref + PreToolUse hook firing only on push/PR); wired into hooks.json and the goal loop's automated gate. Two real bugs caught in testing: TTY-probe stdin hang (fixed with argument-based mode detection) and fresh-repo base-ref bail (fixed to still check working-tree changes).
- ✅ **`/harness-export`** (`commands/harness-export.md` + `scripts/export-agents.sh`, tested: 11 agents → Copilot `.github/agents/*.md` profiles and Cursor `.cursor/rules/*.mdc`, idempotent, clean-before-regenerate per B6): codex = AGENTS.md-native no-op; ends with an honest capability table. Updated 2026-07: **hooks now export to Copilot too** (coding agent + CLI) via `scripts/copilot-hook-adapter.sh` + `templates/copilot-hooks.json` (semantics translated — see B10 correction); skills remain Claude-only, so export is still a capability subset on Cursor/Codex and on VS Code Chat.
- ⏳ Still v2+: federated service graph + workspace-level goal loop (tier 3 — pending the A7 structural-memory bake-off), web UI profile-builder, swarm orchestration (Multica-style backend), video/NAS ingestion (transcription/OCR infra).

### Spec → component traceability
| Spec requirement | Delivered by |
|---|---|
| New/existing interview, env file | Phase 1 `/harness-init` |
| Org context: internal libraries, preferred libs, org conventions | Phase 1 interview (new) / Phase 2 auto-detect + confirm (existing) → `profile.yaml org:` section |
| Scan repos, detect stack, update AGENTS.md/CLAUDE.md | Phase 2 `/harness-scan` |
| `.claude/` bootstrap with agents/skills/rules/plugins/MCP | Phase 3 generator |
| Codebase long-term memory, continuously maintained | Phase 4 tier 1 + Phase 6 hooks |
| Jira/Confluence/XRay/SharePoint/NAS/video memory | Phase 4 tier 3 (video/NAS → Phase 7) |
| Indexed/summarized context per request | A5 improvement (progressive disclosure + budget) |
| Loop engineering, grilling, memory deep-dive | Phase 5 steps 1–2 |
| Refined requirement file | Phase 5 step 3 |
| User story + test cases | Phase 5 step 4 |
| Multi-agent implementation | Phase 5 step 5 |
| Playwright planner/generator/healer e2e | Phase 5 step 6 (existing agents reused) |
| GitHub PR | Phase 5 step 7 |
| Docker local deploy | Phase 5 step 8 |
| Cloud deploy | Phase 5 step 9 |
| Human-in-the-loop | Gates at steps 3, 7, 9 + plan-mode/hooks |
| Microservices / multi-repo & mono-repo support | A6 topology model: mono-repo + multi-repo tier 1 in v1; contract-check v1.5; service graph v2 |

## A5. Improvements adopted over the literal spec

> **Status: implemented** (Phase 0 skeleton + A5 artifacts, smoke-tested). See `README.md` for the
> improvement→file map: marketplace + `se-harness` plugin (`plugins/se-harness/` — harness-goal
> command, context-injector skill, three working hooks: inject-context / gate-check / org-validate)
> and `templates/` (profile.yaml, env.harness.example, requirement.md, AGENTS.md/CLAUDE.md
> templates with GENERATED blocks, gitignore.harness).

1. **Context injection — don't feed everything every request.** Instead of stuffing summarized memory into every LLM call: a compact always-loaded index (AGENTS.md + MEMORY.md index lines), **retrieval tools invoked on demand** (CodeGraph queries, wiki-query skill), and a **budgeted hot set** (agentmemory's ~16K priority pipeline: scratchpad → current story → today's log). This is how Claude Code's native memory works, avoids context rot, and cuts token cost. Three independent sources converged on this shape (B7).
2. **`.temp` → `.harness/requirements/` (committed).** Refined requirements are traceability artifacts (requirement → story → commit → test), not scratch. A `.temp` folder implies disposable; keep `.temp` only for genuine scratch.
3. **Secrets split**: `profile.yaml` committed (non-secret), `.env.harness` gitignored (tokens/credentials).
4. **Stories/test cases written to Jira/XRay via MCP as the system of record**, with local artifacts as copies — not local-only files that drift from the tracker.
5. **HITL placed at irreversible steps only** (requirement approval, PR, deploy) so the loop stays fast; everything else is gated by automated checks (hooks + scored QA), matching B1 principle 5.
6. **Defer video/NAS ingestion to v2** — transcription/OCR pipelines are real infrastructure; don't let them block the v1 memory design.
7. **Org libraries as generation target, not just context (WaveMaker pattern, B11).** The `org:` section shouldn't merely inform agents that internal libraries exist — implementer agents get a **compose-first rule**: check `@company/*` components/libraries before writing novel code; hand-roll only when nothing fits, and flag it in the PR. Pair with **machine-checkable second-pass validation** (hooks verifying internal-component usage, design tokens, lint/security) rather than relying on LLM review alone — the deterministic half of WaveMaker's two-pass system, without its DSL lock-in. Orgs with a Figma design system get the official `figma` plugin recommended as a stack pack.

## A6. Topology support: single-repo, mono-repo, multi-repo

The plan originally parked multi-repo in v2 and never addressed mono-repo. Revised after two later findings — nested `AGENTS.md`/`CLAUDE.md` is native in Claude Code *and* Copilot (B10), and `codebase-memory-mcp` already ships cross-service route linking (B12).

**Unifying model**: separate **workspace** (the product) / **unit** (buildable+deployable thing with its own stack) / **repo** (git boundary). One `workspace.yaml` schema serves all topologies — a unit declares `path:` (mono-repo) or `repo:` (multi-repo); single-repo apps omit the manifest entirely. Inheritance chain: org defaults → workspace `shared:` block → unit profile. Both user topologies (layered: ui/config/db/backend-core · domain-split: order/payment/inventory) are a `layout:` label plus per-unit `provides`/`consumes` declarations.

```yaml
workspace:
  name: acme-commerce
  topology: mono-repo | multi-repo
  layout: layered | domain
  shared: { org: {...}, mcp: [github, atlassian], jira: {project: ACME} }
  units:
    - name: order-service
      path: services/orders                            # mono-repo form
      # repo: git@github.com:acme/order-service.git    # multi-repo form
      stack: [java, spring, postgres]
      provides: [contracts/orders-api.yaml]
      consumes: [payments-api]
  run: { compose: deploy/docker-compose.workspace.yml }
```

**Mono-repo — v1 (it's the easy case).** Detection is deterministic: `/harness-scan` reads workspace markers (`pnpm-workspace.yaml`, `nx.json`, `turbo.json`, `lerna.json`, .NET `.sln`, Maven multi-module, `go.work`, Bazel) and proposes the unit list. Generation: root AGENTS.md/CLAUDE.md = workspace level (org context, architecture map, unit index); **nested per-unit AGENTS.md** = stack rules, loaded contextually by both Claude Code and Copilot — no custom machinery. **Cross-unit awareness is free**: one structural graph covers the repo, so cross-unit impact analysis falls out of the existing pipeline. Goal loop: fan-out per-unit agents in worktrees, one PR, one compose file.

**Multi-repo — three tiers:**
- **Tier 1 (v1) — independent bootstrap + shared inheritance.** `workspace.yaml` lives in a small dedicated **meta-repo** (mirrors GitHub's `.github-private` org-agents pattern, B10); each member repo's `profile.yaml` points at it; `/harness-sync` pulls the `shared:` block into each repo's generated sections. Each repo otherwise bootstraps independently.
- **Tier 2 (v1.5) — contract-registry awareness, no service graph needed.** The motivating case ("order-service changed its API — does payment-service still match?") doesn't require cross-repo code analysis: `provides`/`consumes` point at contract artifacts that already exist (OpenAPI/proto/event schemas). A `contract-check` skill/hook flags declared consumers deterministically when a provided contract changes, optionally opening linked Jira tasks / draft PRs per consumer repo. Plus a `workspace-clone` helper checking sibling repos out side-by-side so one session can read across them.
- **Tier 3 (v2) — federated service graph + workspace-level goal loop.** Coordinated multi-repo PRs and orchestrated deploys via the workspace compose file. No longer purely a research problem: `codebase-memory-mcp` indexes multiple projects and links HTTP/gRPC/GraphQL routes across services (B12) — the tier-1-engine bake-off should explicitly test this as the v2 path.

## A7. Open decisions
- Command namespace: `/harness-*` vs `/seaa-*` vs another brand — decide before Phase 0.
- **Tier-1 structural-memory engine**: CodeGraph vs. codebase-memory-mcp vs. Graphify (B12/B13) — run all three on a real repo and compare index quality, query usefulness, and the team-shared-artifact workflow before committing.
- Default methodology for users who don't care (lean: OpenSpec for brownfield, Spec Kit for greenfield; BMAD when roles/stakeholders matter).
- Whether `/harness-init` delegates analysis to Anthropic's `claude-code-setup` when present, or always uses its own scan skill.
- Methodology contract shape (artifact types + lifecycle statuses each pack must emit) — matters most for `harness-export`.
- `depends_on` for component prerequisites (check how much plugin.json already covers).
- `agentstack.lock` format + sync-conflict UX when hand-edits and changed recommendations collide.
- Remaining multi-repo questions (schema itself now designed in A6): meta-repo access/auth for `shared:` inheritance in private orgs; whether `contract-check` opens consumer PRs automatically or only flags; how the federated graph handles version skew between repos.
- Enterprise ingestion order (Jira+Confluence first, then SharePoint; XRay/Zephyr with stories).
- Monetization: hosted profiles / private org marketplaces / pro sync tier (AdSense deprioritized — poor fit for dev audiences); auth needed from day one only if gating.

---

# Part B — Research log

Ten rounds of research; every stat below was verified via the GitHub API and cross-checked against independent coverage where it looked surprising.

## B1. Full-SDLC frameworks round

**Principles established**: (1) artifacts over conversation — every phase output is a repo file; (2) traceability chain requirement→design→story→task→commit→test→deploy; (3) agents specialized by SDLC phase, not tech stack, with narrow tool access (later reinforced by SWE-agent's Agent-Computer Interface research, B10); (4) quality gates between phases; (5) human checkpoints at irreversible steps; (6) parallelism via git-worktree isolation.

**Frameworks**: [BMAD-METHOD](https://github.com/bmad-code-org/bmad-method) (~49k★, 21+ agents, 50+ workflows, `npx bmad-method install`, plus [BMAD-AT-CLAUDE](https://github.com/24601/BMAD-AT-CLAUDE) port) — most mature. [GitHub Spec Kit](https://github.com/github/spec-kit) (`/specify → /plan → /tasks → /implement`) — lightweight official. loki-mode (41 agents/8 swarms, RARV, 9 gates) — aggressive, less battle-tested. [rjmurillo/ai-agents](https://github.com/rjmurillo/ai-agents) — reference implementation with explicit handoffs. **Ruling**: avoid LangGraph/CrewAI/AutoGen for this — Python orchestration primitives duplicating what Claude Code provides natively (confirmed with data in B10).

## B2. Registry-framework vision round

Mapping the 15 proposed "engines" onto Claude Code natives cut net-new work to three things: a stack-detection/scaffolding entry point, a methodology-adapter contract, and idempotent AGENTS.md/CLAUDE.md merge (`<!-- SEAA:GENERATED -->` delimiters, Husky/direnv pattern). Key building blocks: [OpenSpec](https://github.com/Fission-AI/OpenSpec/) (~52k★, delta-based, brownfield-friendly, 30+ tools); **AGENTS.md** standard (Linux Foundation Agentic AI Foundation since Dec 2025, 28+ tools, 60k+ repos — shared rules in AGENTS.md, CLAUDE.md thin on top); [MCP Gateway Registry](https://github.com/agentic-community/mcp-gateway-registry). Stack detection should be an LLM skill, not regex. Sequencing: one vertical slice (one stack + one methodology) before generalizing.

## B3. Initializr round

Web generators ([ai-agent-md.com](https://ai-agent-md.com/), [ClaudeMDEditor](https://www.claudemdeditor.com/)) prove the pick-client→generate UX but only emit instruction files. [caliber-ai-org/ai-setup](https://github.com/caliber-ai-org/ai-setup) = CLI sync, 3 clients. [wshobson/agents](https://github.com/wshobson/agents) = content library (194 agents/158 skills, 6 clients). [agent-skill-creator](https://github.com/FrancyJGLisboa/agent-skill-creator) = one SKILL.md → 17 platforms. Complexity fork identified: one-shot generator (weeks) vs. continuous sync (a package manager). Both later resolved by the plugin ecosystem (B9). Three durable warnings: per-client capability models differ (compilers, not templates); components aren't independent (methodology constrains agents/skills); component granularity drives the data model.

## B4. ECC case study — [affaan-m/ECC](https://github.com/affaan-m/ECC)

**Star-count lesson**: API showed 226k★ on a <6-month repo; initially suspected fake; independent coverage (Medium, r/ClaudeCode, ecc.tools) shows it's real but viral-inflated — "GitHub Discussions show minimal activity… star count may not reflect actual adoption." *Process rule: verify via API + independent discourse; neither trust READMEs nor cry fake without checking.*

**Content**: 277 skills, 67 agents, per-language rules, 15+ hook types, MCP bundles, NanoClaw orchestration. **Criticisms to heed**: over-engineering ("most people just need a good CLAUDE.md"); broken one-command install; Reddit consensus *cherry-pick, don't adopt wholesale* → validates composable opt-in design.

**SKILL.md schema (from 277-file grep)**: required `name`+`description`; `metadata:{origin, author}` on 255; package-style provenance (`license`/`version`/`homepage`) on imported skills; `tools`/`allowed-tools` scoping; `argument-hint` for parameterized skills. Steal: provenance block; progressive disclosure via `references/` (SKILL.md as thin router); add the `depends_on` field ECC lacks (its motion-* chain documents prerequisites only in prose).

**Cross-harness doctrine** (`docs/architecture/cross-harness.md`): "ECC is the reusable workflow layer. Harnesses are execution surfaces… If a change requires editing three harness copies, the shared source is in the wrong place." Portability: skills/rules adapt per harness; hooks native in Claude/OpenCode/Cursor but instruction-backed in Codex; **MCP is the one genuinely portable layer**.

## B5. Six-repo round (multica, gstack, agency-agents, hybrid-agents, awesome-list, hermes)

- **[agency-agents](https://github.com/msitarzewski/agency-agents)** — closest to the Initializr vision: desktop picker app, 14+ clients, 230+ agents, real convert→install pipeline (deep dive B6).
- **[Multica](https://github.com/multica-ai/multica)** (39k★, verified) — Go+Postgres+WebSocket task board treating agents as teammates (enqueue→claim→start→complete), 10+ CLIs auto-detected. Reference for a future swarm layer, not a config layer.
- **[gstack](https://github.com/garrytan/gstack)** — Garry Tan's 23-command pipeline; real HN controversy ("prompts in a text file" vs. "process, not tools"); multi-host via one-TS-config-per-host — the benchmark for cheap adapters. All-or-nothing.
- **[hermes-agent](https://github.com/NousResearch/hermes-agent)** — general personal-assistant runtime; out of scope.
- **claude-code-hybrid-agents** — 0★ but one idea: typed JSON context-protocol for agent handoffs.
- **awesome-engineering-agents** — link list only.

## B6. agency-agents compiler deep dive (cloned)

`tools.json` registry: per-client `{detect.dirs, version.bin, format, installKind, dest templates, scope}`. **`format`** = render contract ("same format name guarantees byte-identical output"); **`installKind`** = `per-agent` | `roster` (one combined file — Aider CONVENTIONS.md, .windsurfrules) | `plugin` (opaque artifact). CI (`check-tools.sh`) fails the build if JSON and script tool-lists drift. `convert.sh` (731 lines): one shared frontmatter parser (`get_field`/`get_body`), thin per-target converters; `convert_openclaw()` proves semantic recompilation (body sections bucketed into SOUL/AGENTS/IDENTITY by header keywords); deterministic output, cleaned before regen, parallel per-tool. `install.sh` (1324 lines): three-tier selection (flags → TTY wizard → auto-detect); trivial detection (`command -v X || [[ -d ~/.X ]]`); `--link` symlink mode; lazy `ensure_converted`; upstream bugs encoded as data (OpenCode ~119-agent cap warning); defensive `rm -rf` basename checks; `--dry-run`.

## B7. Memory round: CodeGraph, agentmemory, Karpathy wiki

Three complementary tiers by **mutability model**:
1. **[CodeGraph](https://github.com/codegraph-ai/CodeGraph)** — *derived/rebuildable*: tree-sitter semantic graph (38 languages) in RocksDB, 42 MCP tools (impact analysis, hybrid search, `pr_context` blast-radius), client-agnostic (MCP + VS Code + rule files). Also: `--profile` tool-narrowing (42→8) and a 47-dir credential-exclusion list — copy both conventions.
2. **[agentmemory](https://github.com/jayzeng/agentmemory)** — *append-only session/decision log*: MEMORY.md + SCRATCHPAD + daily/ + topics/, `#tags` + `[[links]]`, optional qmd search, **budgeted ~16K context-injection pipeline** — the model for per-request context (adopted in A5).
3. **[Karpathy's LLM wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)** — *actively-rewritten synthesis*: immutable raw sources / LLM-owned wiki (entity+concept pages, `index.md`, append-only `log.md`) / schema in CLAUDE.md; ingest / query / lint workflows; contradictions resolved, not accumulated. Best fit for enterprise/domain material.

Third independent convergence on "index.md + per-topic files + append-only log" (Claude Code native, agentmemory, Karpathy) → treat it as the standard shape.

## B8. Build-strategy round (options a/b/c)

Chose (c): one shared core (profile schema → recommender → compiler), reuse existing repos. Established: unified **project profile** for new+existing flows; two-phase bootstrap+sync with lockfile; orchestration-pattern cost table (supervisor-worker / pipeline / fan-out are native; **swarm needs external infra** — Multica-shaped, v2); multi-repo = the least-solved area anywhere → `workspace.yaml` manifest, cross-repo-aware agents an open research problem; community contributions = curated PRs with provenance + CI lint, not open upload; monetization = hosted/pro tier over AdSense (dev audiences: ad-blockers, low RPM). Original build order superseded by B9's.

## B9. Plugin-ecosystem round — the architecture pivot

1. **Packaging/distribution solved**: [plugins](https://code.claude.com/docs/en/plugins-reference) bundle agents+skills+commands+hooks+MCP+LSP; [marketplaces](https://code.claude.com/docs/en/discover-plugins) are git repos (`/plugin marketplace add user/repo`), versioned updates. → component = plugin; zip idea dead; distribution machinery free.
2. **[claude-code-setup](https://claude.com/plugins/claude-code-setup)** (Anthropic, ~179k installs) already recommends across the exact five categories — but read-only. Differentiation: recommendation → installed, configured, syncable harness.
3. **Content already ships as plugins**: [official marketplace](https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json) 180+ (DBs, deploy, playwright, monitoring, LSPs, code-review/feature-dev/commit-commands, `hookify`, `dash0`/`langfuse-observability`, `context7`, `claude-md-management`, `plugin-dev`); methodology plugins exist ([bmad-plugin](https://github.com/PabloLION/bmad-plugin), BMAD [official installer issue #746](https://github.com/bmad-code-org/BMAD-METHOD/issues/746), [Spec Kit](https://www.claudedirectory.org/plugins/spec-kit)). → recommender maps profile→plugin-IDs; original content only where nothing exists.

Competitor scan: [buildmate](https://github.com/vadim7j7/buildmate), [project-bootstrapper](https://github.com/kev52/project-bootstrapper) (validates the sync loop), [dark-software-factory](https://github.com/jrhoades1/dark-software-factory), [claude-bootstrap/Maggy](https://github.com/alinaqi/claude-bootstrap) — none combine recommendation+installation+methodology+memory+multi-repo. Decisions: **Claude-Code-first** (user confirmed); other clients = export path; web UI = profile builder.

## B10. Autonomous-agent frameworks round (MetaGPT, OpenHands, SWE-agent, aider, CrewAI, Cognita, Copilot agents)

All execution engines/clients, not bootstrap layers. URL corrections: `open-devin/opendevin` is a **4★ squatter clone** — real project is [OpenHands/OpenHands](https://github.com/OpenHands/OpenHands) (80.9k★, active); `cognita-ai/cognita` 404s — real is [truefoundry/cognita](https://github.com/truefoundry/cognita) (4.4k★, slowing).

- [MetaGPT](https://github.com/FoundationAgents/MetaGPT) 69k★ but stale since Jan 2026 (pivot to MGX) — conceptual ancestor of role rosters; don't build on it. [CrewAI](https://github.com/crewAIInc/crewAI) 55.6k★ active — healthy, wrong layer. [SWE-agent](https://github.com/SWE-agent/SWE-agent) 19.8k★ — ACI research supports narrow per-agent tool interfaces. [aider](https://github.com/Aider-AI/aider) 47k★ — a client, already covered by the roster export format.
- **Copilot export target well-specified**: coding agent reads AGENTS.md (root+nested), `.github/copilot-instructions.md`, **and CLAUDE.md/GEMINI.md directly** ([changelog](https://github.blog/changelog/2025-08-28-copilot-coding-agent-now-supports-agents-md-custom-instructions/)); custom agents = `.github/agents/NAME.md` (YAML frontmatter: prompts/tools/MCP; 30k-char cap; org-wide via `.github-private`) — direct analog of `.claude/agents/*.md`, so Copilot export ≈ frontmatter mapping. [github/awesome-copilot](https://github.com/github/awesome-copilot) = Copilot-side content pool.
- **UPDATE (2026-07-16): Copilot has a full plugin ecosystem too** — [CLI plugins](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-cli-plugins) (`plugin.json`: agents as `NAME.agent.md`, skills as the **same SKILL.md standard**, commands, hooks, MCP, LSP), [marketplaces](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-marketplace) with a Claude-compatible `marketplace.json` schema — and **Copilot CLI reads `.claude-plugin/marketplace.json` natively**, so one repo dual-publishes to both ecosystems. Enterprise-managed plugins (preview 2026-05) auto-distribute org-wide. Framework refactored accordingly: `build-copilot-plugin.sh` generates `plugins/se-harness-copilot` (11 agents, 7 skills, 6 commands, deterministic); marketplace lists both plugins; verified schema notes in `docs/claude/` + `docs/copilot/` + `docs/interop-matrix.md`. Claude-side fixes from re-verifying current docs: quoted `${CLAUDE_PLUGIN_ROOT}` in shell-form hook commands, enriched plugin.json (`$schema`/license/keywords), `claude plugin validate --strict` noted for CI.
- **CORRECTION (2026-07, user-caught): Copilot DOES have hooks now** — [`.github/hooks/*.json`](https://docs.github.com/en/copilot/concepts/agents/hooks) on the coding agent + Copilot CLI, 8 events near-parallel to Claude's (preToolUse/postToolUse/userPromptSubmitted/sessionStart/End/agentStop/subagentStop/errorOccurred). **Different semantics** ([reference](https://docs.github.com/en/copilot/reference/hooks-reference)): deny = JSON `permissionDecision` output + exit 0; **exit 2 does NOT block** (inverse of Claude); other non-zero exits fail-closed; timeouts fail-open; payload casing differs between coding agent (snake_case `tool_input`) and CLI (camelCase `toolArgs` as JSON-encoded string). Earlier "hooks are Claude-only" claims (this section + B4's ECC-era portability framing as applied to Copilot) are outdated — se-harness ships `copilot-hook-adapter.sh` + `templates/copilot-hooks.json` translating the semantics. CI/branch protection remain the human-binding backstop. **Further resolved 2026-07-16** (user verification + [VS Code docs](https://code.visualstudio.com/docs/copilot/customization/hooks)): VS Code Copilot supports hooks too — with **Claude Code's conventions** (PascalCase events, exit 2 blocks, reads `.claude/settings.json` and plugin `hooks/hooks.json`); plugin-bundled Copilot hooks.json paths resolve plugin-root-relative (now bundled in se-harness-copilot); Copilot `commands` are skill-shaped (each harness command also emitted as a SKILL.md). The **deny-JSON (`permissionDecision`) is the one blocking mechanism valid on every surface**. Remaining open: exact per-surface preToolUse payload field shapes (conflicting sources — guide §4.7 capture step stays mandatory; see `docs/copilot/platform-notes.md` item 3).
- **Enterprise-memory ruling**: skip heavy RAG platforms (Cognita) — MCP connectors + LLM-wiki synthesis (B7) instead; video/NAS deferred (adopted in A4/A5).

Final solution-scan round additionally surfaced: [agentic-sdlc-plugin](https://github.com/ajaywadhara/agentic-sdlc-plugin) (verified 1★, single-day, greenfield-only — pattern reference for the goal loop and scored QA gates, not a dependency), [Claude Agent for Jira](https://www.atlassian.com/blog/company-news/claude-agent-for-jira) (official Jira-issue→draft-PR flow with human review/merge/deploy — the Jira↔PR slice of Phase 5), and the 2026 memory-framework field ([mem0](https://github.com/mem0ai/mem0), EverMind, Kage) — optional upgrades for tier-2 memory if plain markdown ever proves insufficient.

## B11. WaveMaker — proprietary "agentic architecture-first" platform (borrow patterns, not the platform)

[WaveMaker](https://wavemaker.ai/) — ~20-year low-code vendor (Java/Spring, Angular/React, React Native) that wrapped an agent harness around its decade-hardened component library; Accenture strategic partnership (2026). Proprietary/commercial; the [docs repo](https://github.com/wavemaker-ai/docs) is only the Docusaurus site source (3★). The [Medium article](https://medium.com/ai-software-engineer/the-agentic-era-of-enterprise-app-development-is-here-dont-miss-it-01dddf786b3c) that surfaced it is paywalled; details below from their public [architecture](https://wavemaker.ai/architecture/) and [agents](https://wavemaker.ai/agents-dev/) pages.

**Architecture**: multi-agent task decomposition with a unified context layer via MCP (current code, design system, platform knowledge, patterns); a governance layer enforcing OWASP/RBAC/WCAG 2.3 AA; **Two-Pass Coding System** — planning pass, then rigorous validation against a meta model; agents emit their constrained markup language (WML) which deterministic codegen compiles; design tokens auto-extracted from onboarded Figma files; custom agents supported.

**Ruling — ignore the platform, borrow three patterns**:
1. **Hardened org component library as the *generation target*** — agents compose pre-verified components instead of free-writing code; that's the enterprise-grade version of the `org:` internal-libraries feature → adopted as the compose-first rule (A5 #7).
2. **Deterministic second-pass validation** — machine checks against org rules as the gate, not LLM review alone → strengthens Phase 5 hooks (A5 #7).
3. **Figma design-token alignment** — official `figma` marketplace plugin covers this as an optional stack pack.

**Why not more**: WaveMaker's moat is owning the vertical stack (components + studio + runtime + DSL) — inherently lock-in, and a universal intermediate DSL would contradict this project's tech-stack-agnostic premise. Nothing installable or open source to reuse directly.

## B12. Memory follow-up: codebase-memory-mcp and memory-graph

### [DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) — strong tier-1 alternative to CodeGraph
Tree-sitter AST across **158 languages** + "Hybrid LSP" type resolution for 12 majors; RAM-first indexing (in-memory SQLite → single WAL dump; Linux kernel 28M LOC in ~3 min); 15 MCP tools incl. read-only **Cypher subset**, `trace_path`, dead-code detection, `manage_adr` (ADR tracking), HTTP/gRPC/GraphQL route linking; MIT, 100% local, single static signed binary (SLSA 3).

Three things CodeGraph lacks:
1. **Team-shareable committed graph** (`.codebase-memory/graph.db.zst` in git — teammates decompress instead of reindexing) — directly serves the "continuously maintained team memory" requirement.
2. **Installer does what our Phase 3 generator does**: auto-detects **43 client surfaces** and writes MCP config *plus* durable skills/hooks/agent profiles per client, with three tool-exposure tiers (Scout/Verify/Auditor). Both validation and a working reference implementation for the bootstrap generator.
3. **Published eval discipline**: 31-repo benchmark — 83% answer quality, 10× fewer tokens, 2.1× fewer tool calls vs. file-by-file exploration. Copy this pattern for our own claims.

**Caution (B4 lesson applied)**: 31.8k★ on a <5-month-old repo (created 2026-02-24); third-party writeups exist (dev.to, trendshift) but no organic HN/Reddit discussion found — substantive project, star velocity likely marketing-inflated relative to adoption. → Added to A6 as a bake-off decision vs. CodeGraph rather than an automatic swap.

### [memory-graph/memory-graph](https://github.com/memory-graph/memory-graph) — tier-2 as graph DB; keep markdown default, borrow the link taxonomy
220★ (plausible), TypeScript. Stores solutions/problems/patterns/errors/fixes/workflows as graph nodes with **typed causal relationships** (`SOLVES`, `CAUSES`, `BUILDS_ON` — e.g. `[timeout_fix] → SOLVES → [memory_leak]`), 35+ commands, five backends (embedded FalkorDBLite default). Its own docs draw the right line: markdown for static rules, graph for dynamic learnings.

**Ruling**: our tier-2 requirements (git-diffable, human-inspectable, zero infra, survives client switch — B7) are precisely what a graph DB gives up → markdown stays the v1 default; memory-graph joins mem0/EverMind/Kage on the optional-upgrade list. **One cheap borrow**: express its typed-relationship taxonomy as markdown link semantics (`[[timeout-fix]] solves [[memory-leak]]`) in the session log — causal chains without a database.

## B13. Memory follow-up: Graphify

### [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) — third tier-1 structural-memory candidate, skill-first not MCP-first
CLI (`graphifyy` on PyPI, `graphify` command) plus a `/graphify` skill across 20+ agent platforms (Claude Code, Cursor, Codex, Copilot CLI, Gemini CLI, etc.), rather than a bare MCP server. Local, deterministic tree-sitter AST across ~40 languages for code (no LLM, nothing leaves the machine); docs/PDF/image/video get a semantic pass through whichever model API the host assistant already has. Every edge tagged `EXTRACTED` vs `INFERRED` — confidence provenance that matches our own wiki tier's provenance requirement (B7). Outputs three files (`graph.html`, `GRAPH_REPORT.md`, `graph.json`) plus CLI `query`/`path`/`explain` against `graph.json` — no server required for single-developer use; an optional `graphifyy[mcp]` extra exposes `query_graph`/`get_node`/`get_neighbors`/`shortest_path` over stdio or shared HTTP if MCP access is preferred.

Two things neither CodeGraph nor codebase-memory-mcp have:
1. **Hook-enforced adoption on Claude Code**: `graphify claude install --strict` installs a PreToolUse hook that *blocks* (not just nudges) the first raw source read of a session and redirects it to the graph, then reverts to nudging — directly analogous to our own gate-check hook pattern, and the closest thing we've seen to "the agent can't skip memory."
2. **Widest platform coverage by far** (20+ assistants incl. Copilot CLI, which we already support) — sidesteps the "confirm which repo the user means" disambiguation cost that plagues the two CodeGraph namesakes.

**Caution (B4/B12 lesson applied, sharper this time)**: 121k★/11.7k forks on a repo created 2026-04-03 (under 6 months old) is an order of magnitude past codebase-memory-mcp's already-flagged 31.8k★/<5-month pattern. It's YC-backed (S26) with a paid hosted product (`app.graphify.com`, early access) behind the free CLI — plausibly a funnel, which doesn't disqualify it but raises the same "star velocity ≠ adoption" flag harder. The benchmarks in its BENCHMARKS.md (LOCOMO/LongMemEval) are self-published, not third-party verified. → Added to A7 as a third bake-off candidate; run it alongside CodeGraph and codebase-memory-mcp before picking a default — don't let platform breadth or hook-blocking alone decide it.
