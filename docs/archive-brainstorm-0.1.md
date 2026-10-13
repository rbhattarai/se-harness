# Brainstorm: Software Engineering AI Agents Bootstrap

Working title for the repo: `software-engineering-ai-agents-bootstrap`

Goal: build a tech-stack-agnostic, methodology-agnostic, multi-client framework that lets anyone bootstrap an AI-agentic SDLC setup (plan → architecture → stories/tasks → code → unit tests → integration tests → e2e tests → deploy → release) for any project, new or existing, regardless of language/framework — inspired by having already built a Playwright-based multi-agent test automation framework using Claude Code's agents/skills/MCP/rules/prompts/workflows.

---

## 1. Original scope: full-SDLC agentic framework

Wanted capabilities: high-level plan → architecture/design → detailed design → user stories/tasks → implementation + unit tests → integration tests → e2e tests → cloud deployment → release maintenance.

### Key principles identified
1. **Artifacts over conversation** — every phase output (PRD, architecture doc, ADRs, stories, tasks, test plans) should be a file in the repo, not something that only lives in chat history. Makes the pipeline auditable and resumable.
2. **Traceability chain** — requirement → design → story → task → commit → test → deployment should be linkable (e.g. story ID in commit messages).
3. **Specialize agents by SDLC phase**, not by tech stack (architect, story-writer, implementer, unit-tester, integration-tester, e2e-tester, release-manager), each with narrow tool access.
4. **Quality gates between phases**, enforced by hooks/reviewer subagents — most "agentic SDLC" demos fail because they skip gates.
5. **Human checkpoints at irreversible steps** — plan/design/coding/testing can run fairly autonomously; cloud deployment/release/infra changes should always have an explicit human approval gate.
6. **Parallelism via isolation** — separate git worktrees/branches per story/task so agents don't clobber each other.

### Production-ready full-SDLC frameworks found
| Framework | Notes |
|---|---|
| **[BMAD-METHOD](https://github.com/bmad-code-org/bmad-method)** | Most mature (~49k stars as of ~June 2026, up from 37k in Feb). 21+ specialized agents (PM, Architect, Dev, QA, UX...), 50+ workflows, brainstorm→PRD→architecture→stories→dev→QA→deploy, scale-adaptive. Installs into Claude Code via `npx bmad-method install`. Also a Claude-Code-native port: [BMAD-AT-CLAUDE](https://github.com/24601/BMAD-AT-CLAUDE). **Recommended starting point** if adopting an existing framework wholesale.
| **[GitHub Spec Kit](https://github.com/github/spec-kit)** | Official GitHub project. Lightweight: `/specify` → `/plan` → `/tasks` → `/implement`. Less opinionated about agent roles. Good if BMAD feels too heavyweight.
| **loki-mode** | 41 agents / 8 swarms, PRD-to-deployed-product, RARV cycles, 9 quality gates. Newer, less battle-tested, more aggressive automation (incl. ops/growth) — riskier for production reliance.
| **[rjmurillo/ai-agents](https://github.com/rjmurillo/ai-agents)** | Similar phase-based roster (vision→architecture→implementation→QA) with explicit handoff protocols. Smaller, more reference implementation than polished product.

Avoid general orchestration libraries (LangGraph/CrewAI/AutoGen) for this — they're Python orchestration primitives you'd have to wire up yourself, duplicating what BMAD/Spec Kit already give you natively inside Claude Code (subagents/skills/hooks).

---

## 2. Own vision: tech-agnostic, methodology-agnostic registry framework

User's idea: a set of **registries** — Agents, Skills, MCP, Prompts, Rules, Workflow, Memory, Planning Engine, Task Engine, Execution Engine, Evaluation Engine, Human Approval Engine, Release Engine, Knowledge Base, Observability — such that the same framework scaffolds a React/Node/Postgres/Redis project or a .NET Core/MSSQL/Kafka project, updating `AGENTS.md`/`CLAUDE.md` per project automatically. Should support brownfield (existing) and greenfield (new) projects, and let the user pick which SDLC methodology to use (BMAD, Spec Kit, OpenSpec, or others) as a swappable choice.

### Key insight: most of the 15 "engines" aren't new software
Map each concept onto what Claude Code already provides natively — cuts real net-new build surface to ~3 things.

| Concept | Maps to (already exists) | Net-new work |
|---|---|---|
| Agents Registry | `.claude/agents/*.md` | none — curate a catalog |
| Skills Registry | `.claude/skills/*/SKILL.md` | none — skills are already a discoverable registry |
| MCP Registry | `.mcp.json` + MCP registry spec | none — curate vetted servers per stack |
| Prompts/Rules | `CLAUDE.md` / `AGENTS.md` layering | none — organize into generated + human sections |
| Workflow/Planning/Task Engine | BMAD / Spec Kit / OpenSpec commands | **this is the pluggable methodology layer** |
| Execution Engine | Claude Code's own agent loop | none |
| Evaluation Engine | code-review skill + test runners + Playwright agents | thin glue |
| Human Approval Engine | plan mode / hooks / PR review gates | thin glue |
| Release Engine | release-manager subagent + CI + gated deploy | thin glue |
| Knowledge Base | `docs/` + memory system | none |
| Observability | hook that logs tool calls/costs | small custom script |

Net-new work: **(1)** a stack-detection/scaffolding CLI, **(2)** a methodology-adapter contract, **(3)** an idempotent template-merge mechanism for AGENTS.md/CLAUDE.md that won't clobber human edits on re-run.

### Existing building blocks found (no single project does all of this)
- **[OpenSpec](https://github.com/Fission-AI/OpenSpec/)** — tool-agnostic SDD (propose→apply→archive), explicitly good for brownfield/existing codebases (spec *deltas* not full upfront spec), 30+ tool integrations, ~52k stars (June 2026). Closest thing to a drop-in "methodology pack."
- **AGENTS.md** — emerging cross-tool standard (OpenAI-initiated Aug 2025, moved under Linux Foundation's Agentic AI Foundation Dec 2025, backed by OpenAI/Anthropic/Google/AWS). 28+ tools support it natively; 60,000+ repos use it. Practical pattern: put shared rules in `AGENTS.md`, keep `CLAUDE.md` thin (Claude-only permission boundaries, MCP servers, subdirectory overrides); Claude reads `AGENTS.md` when `CLAUDE.md` is absent.
- **[MCP Gateway Registry](https://github.com/agentic-community/mcp-gateway-registry)** — enterprise-flavored registry/discovery for MCP servers and skills; closest existing "skill/MCP registry" concept, though governance-oriented not scaffolding-oriented.
- **specs.md** — "AI-native development framework with pluggable flows" — less adopted/documented than BMAD/Spec Kit/OpenSpec, worth a look but unproven.

### Recommended 3-layer architecture (if built from scratch)
Separate **core bootstrap engine** (stack-agnostic scaffolding CLI) / **stack packs** (skills+rules per tech, e.g. react/, dotnet/, postgres/, kafka/) / **methodology packs** (BMAD, Spec Kit, OpenSpec as swappable adapters — pick exactly one per project).

```
software-engineering-ai-agents-bootstrap/
  bin/seaa.js                     # CLI: init / analyze / add-stack / add-methodology
  registry/
    stacks/                       # independent, composable packs
      react/{skills/, rules.md, mcp.json}
      dotnet/{skills/, rules.md, mcp.json}
      postgres/, redis/, kafka/, mssql/, node-express/, angular/...
    methodologies/                # swappable SDLC adapters — exactly one per project
      bmad/ spec-kit/ openspec/
    agents/                       # cross-cutting, stack-independent (reviewer, release-manager, evaluator)
  templates/
    CLAUDE.md.tmpl                # clearly delimited GENERATED block
    AGENTS.md.tmpl
  docs/methodology-contract.md    # interface every methodology pack must satisfy
```

**Methodology contract**: define it as "a methodology pack must produce these artifacts at these lifecycle stages" (PRD → architecture → story → task → test-plan → release-note), each a file with status frontmatter. BMAD/Spec Kit/OpenSpec all already roughly produce this shape — write a thin adapter per pack to normalize into your convention.

**Stack detection should be a skill, not a regex script** — an LLM-based `stack-detector` skill handles brownfield repos (e.g. recognizing Kafka usage from code, not just a package name) better than pattern matching, and can propose a stack-pack list for user confirmation.

**AGENTS.md/CLAUDE.md updates must be idempotent** — wrap generated content in delimiters (`<!-- SEAA:GENERATED:START -->...<!-- SEAA:GENERATED:END -->`) so re-running the bootstrap only replaces that block, never touching hand-written content elsewhere (same pattern as Husky/direnv managed blocks).

### Build sequencing recommendation
Don't build all registries up front. One vertical slice first: one stack pack (React+Node+Postgres) + one methodology pack (OpenSpec — lightest/most adapter-friendly) + `init`-only CLI. Run it end-to-end on a toy project. Add the second stack (.NET/MSSQL/Kafka) and second methodology (BMAD) only after the first slice works — this is what reveals whether the contract is genuinely stack/method-agnostic or accidentally baked in React/OpenSpec assumptions. Generalize into the full registry structure last.

---

## 3. "Spring Initializr for AI agent configs" brainstorm

Idea: a web UI (like [start.spring.io](https://start.spring.io)) where the user picks client(s) (Claude Code, Copilot, Cursor, Codex, Continue.dev, etc.) and components (MCP, rules, skills, agents...), and it generates the relevant files/folders for that client.

### What already exists (narrow slices, nothing does the full thing)
- **[ai-agent-md.com](https://ai-agent-md.com/)**, **[ClaudeMDEditor](https://www.claudemdeditor.com/)** — web generators, pick your clients (Claude/Cursor/Copilot/Windsurf), answer stack questions, generate the instruction file. Proves the "pick client → generate" UI pattern, but scoped only to the instruction file (CLAUDE.md/AGENTS.md/.cursorrules) — no skills/MCP/agents.
- **[caliber-ai-org/ai-setup](https://github.com/caliber-ai-org/ai-setup)** — "Continuously sync your AI setups with one command." Full content breadth (skills+MCPs+config files) for Claude Code/Cursor/Codex, stack-aware ("codebase tailor suited"). But it's a CLI **sync** tool, not a web picker, and only 3 clients.
- **[wshobson/agents](https://github.com/wshobson/agents)** — 194 agents / 158 skills / 106 commands from one Markdown source, consumed by 6 different clients. Raw content library, not a picker UI.
- **[FrancyJGLisboa/agent-skill-creator](https://github.com/FrancyJGLisboa/agent-skill-creator)** — one SKILL.md → installs on 17 platforms. Solves the cross-compilation problem specifically.

**Verdict at the time**: nobody had built the full Initializr-style web UI over this full breadth — real gap. (Later found `agency-agents` actually already builds most of this — see §5.)

### Is it simple or complex? Depends on one scope decision
- **Simple route — one-shot generator**: pick clients + components + stack → compile → serve a zip/copy files. Genuinely Spring-Initializr-shaped: a content registry (data) + a small compiler per client + a frontend. Buildable in weeks.
- **Complex route — continuous sync**: agent config formats change monthly (AGENTS.md itself was only standardized ~Dec 2025). A one-shot zip goes stale fast. Keeping generated projects in sync with an evolving registry is a bigger system — closer to building a package manager (versioning, diffing against local edits, conflict resolution) than a generator. This is where hidden complexity actually lives, not the UI.

**Recommendation given**: build the one-shot version first, and steal the interaction model from `shadcn/ui`'s CLI (`npx shadcn add button` — copies files directly into the user's repo so they own/can edit them) rather than a hosted website serving a zip. Sidesteps hosting/infra, gives a natural upgrade path to "re-run to pull updates" later without committing to full sync semantics on day one.

### Underestimated complexity flagged
1. **Per-client output isn't just different file paths — different capability models.** Claude Code subagents have isolated context + scoped tool permissions; Cursor has no equivalent concept. Need N per-client "compilers," not one template with swapped extensions.
2. **Components aren't independent** (unlike Spring's dependencies) — picking a methodology pack constrains which agent personas/skills even apply.
3. **Decide the unit of "component" early** (one skill? a whole stack pack? a whole methodology bundle?) — drives the entire data model.

---

## 4. Case study: ECC ("Everything Claude Code") — [affaan-m/ECC](https://github.com/affaan-m/ECC)

### Important lesson on star counts (verify, don't trust at face value)
Initial GitHub API check showed **226,679 stars / 34,662 forks** on a repo created 2026-01-18 (< 6 months old) — more than the Linux kernel's all-time star count (~190k) and ~5x BMAD-METHOD's total (49k, built over ~a year as the most-discussed project in this niche). Initially flagged as likely fake/bot-farmed.

**Correction after checking independently**: it's real — genuine press coverage (Medium: *"Everything Claude Code: Inside the 82K-Star Agent Harness That's Dividing the Developer Community"*), real Reddit discussion (r/ClaudeCode), a dedicated site (ecc.tools), podcast coverage, built by Affaan Mustafa (won an Anthropic x Forum Ventures hackathon). Growth was viral (X thread driven) but not a pure scam.

**However**, the article's own reporting **independently corroborates the original suspicion in a more nuanced form**: *"the project claims 82,000 GitHub stars following a viral X thread, but GitHub Discussions show minimal activity... suggesting the star count may not reflect actual adoption."* — i.e., real project, inflated-relative-to-usage star count, not a bot scam.

**Takeaway/process lesson**: always verify surprising GitHub stats via the API directly and cross-check with independent discourse (HN/Reddit/blogs) before reporting adoption claims — don't take a repo's own README/marketing at face value, but also don't jump to "fake" without checking for real independent coverage.

### What ECC actually is
Multi-harness "agent harness performance optimization system": Claude Code (primary) + Cursor/Codex/OpenCode/Copilot/Zed/Gemini CLI adapters. ~277 skills, 67 agents, per-language rules (`common/` + TS/Python/Go/Java/Rust/etc.), 15+ hook trigger types, bundled MCP configs (GitHub/Supabase/Vercel), stack scaffolds (Next.js, Django, Spring Boot...), full SDLC coverage (plan→architect→code→test [Playwright]→security [AgentShield]→deploy), own orchestration engine (NanoClaw v2 — model routing, skill hot-loading, session mgmt), dashboard GUI.

### Real criticisms (from the community, useful as warnings for this project)
1. **"Over-engineering" is the top complaint** — 997 internal tests, multi-language rule architecture, a whole orchestration engine. *"Most people just need a good CLAUDE.md, not an entire ecosystem."* Directly relevant: this project is explicitly planning "an entire ecosystem."
2. **Broken one-command promise** — agents/skills/hooks/commands auto-install, but rules require manual setup, breaking the "one command" pitch. Lesson: don't oversell a one-shot generator you can't fully deliver.
3. **Reddit consensus: cherry-pick modules, don't install the whole framework** — validates a composable, opt-in registry design over a monolithic all-in-one framework (the direction already being leaned toward).

### SKILL.md schema extracted from ECC (277 skills)

**Documented schema** (`docs/SKILL-DEVELOPMENT-GUIDE.md`):
```yaml
---
name: skill-name           # required — lowercase, hyphenated
description: ...           # required — used for auto-activation
origin: ECC                # optional — provenance tag
tags: [...]                # optional
version: 1.0.0             # optional
---
```
Body convention: `# Title` → `When to Activate` → `Core Concepts` → `Code Examples` → `Anti-Patterns` → `Best Practices` → `Related Skills`.

**Actual usage (superset found via grep across all 277 files)**:

| Field | Count | Purpose |
|---|---|---|
| `name`, `description` | 277 | as documented |
| `metadata:` (nested) | 255 | wraps `origin`, `author`, `clawdbot: {emoji}` |
| `version` | 28 | mostly on imported/third-party skills |
| `tools` / `allowed-tools` | 11 / 2 | tool-scoping |
| `license`, `homepage` | 8 each | only on externally-imported skills |
| `author` | 5 | individual attribution |
| `tags`, `category` | 3 each | informal, inconsistent taxonomy |
| `argument-hint` | 3 | marks a skill expecting a parameter (e.g. `tdd-workflow` takes `<path/to/*.plan.md>`) |

**Patterns worth stealing**:
1. **Provenance/attribution block** for imported skills — full package-style metadata (`license`, `version`, `homepage`, `metadata.author`) on third-party skills, e.g. `skills/carrier-relationship-management/SKILL.md` pulled from an external marketplace. Treat each skill like an npm package, not just a file.
2. **Progressive disclosure via `references/`** — complex skills (e.g. `skills/angular-developer/`, 36 files) keep `SKILL.md` as a short router, push detail into `references/*.md` loaded on demand.
3. **No formal dependency graph — a real gap in ECC.** The `motion-foundations`/`motion-patterns`/`motion-advanced` chain has a real prerequisite relationship stated only in prose (`description:` text), not a machine-readable field. Recommendation: add a real `depends_on: [...]` field — cheap insurance ECC didn't bother with.

### Cross-harness architecture principle (`docs/architecture/cross-harness.md`)
> "ECC is the reusable workflow layer. Harnesses are execution surfaces... The same source skill can be installed into multiple harnesses because it is mostly instructions, constraints, and workflow shape... **If a change requires editing three harness copies of the same workflow, the shared source is in the wrong place.**"

Portability table:

| Surface | Shared source | Per-harness adapter | Status |
|---|---|---|---|
| Skills | `skills/*/SKILL.md` | Claude plugin, Codex plugin, `.agents/skills`, Cursor skill copies, OpenCode plugin | Supported |
| Rules | `rules/`, `AGENTS.md` | Claude rules install, Codex `AGENTS.md`, Cursor rules, OpenCode instructions | Supported, not identical |
| Hooks | `hooks/hooks.json` | native in Claude/OpenCode/Cursor; **instruction-backed only** in Codex | Partial parity |
| MCP | `.mcp.json`, `mcp-configs/` | native import per harness | The one genuinely portable layer |

Rule for skill authors: use YAML frontmatter with `name`/`description`/`origin`; state required tools without embedding secrets; keep examples repo-relative; avoid harness-only assumptions unless clearly labeled. This is the "compiler, not template" principle validated independently by the later `agency-agents` deep dive.

---

## 5. Six more repos checked

Checked: `multica-ai/multica`, `garrytan/gstack`, `msitarzewski/agency-agents`, `kroegha/claude-code-hybrid-agents`, `usejina/awesome-engineering-agents`, `NousResearch/hermes-agent`.

### `msitarzewski/agency-agents` — closest match to the Initializr vision found in the entire search
- **A desktop app (macOS/Linux/Windows) that IS the picker UI** — checkbox selection of tools (14+: Claude Code, Cursor, Codex, Gemini, Copilot, Aider, Windsurf...) and agents/divisions, auto-detects installed tools, "all/none/detected" presets.
- **Real generate → install pipeline**: `convert.sh` compiles markdown-source agents into each tool's native format; `install.sh` deploys to tool-specific directories. Two clearly separated phases.
- **230+ agents across the full SDLC** organized by division: planning, design, dev (per-platform), testing, deployment, security, post-launch.
- Grew organically from a Reddit thread.
- **This repo was cloned and its `convert.sh`/`install.sh` architecture fully reverse-engineered — see §6 below.**

### `multica-ai/multica` — reference for the Task/Execution/Approval Engine layer
Real production architecture: Next.js frontend + Go backend (Chi, sqlc, WebSocket) + Postgres/pgvector, local daemon per machine auto-detecting installed CLIs (Claude Code, Codex, Cursor, 10+ others). Treats agents as "teammates" with a lifecycle (enqueue→claim→start→complete/fail), assignable to individuals or "Squads." No component registry; execution/coordination-focused, doesn't model planning/architecture/testing as distinct phases. 39,286 stars (verified plausible via independent review coverage — AgentConn blog).

### `garrytan/gstack` — legitimate, single opinionated methodology bundle, real controversy
Real HN threads (3 separate discussions) and real public criticism: Mo Bitar's critique "a bunch of prompts in a text file," HN split "genius" vs. "cargo culting." Structurally: Think→Plan→Build→Review→Test→Ship→Reflect (23 commands), Claude-Code-primary but genuinely multi-client via `./setup --host <name>` (adding a new host is "one TypeScript config file, zero code changes" — a good benchmark for how cheap a well-factored adapter should be). No component picker — all-or-nothing, same bloat tension as ECC. ~97-120k stars depending on snapshot.

### `NousResearch/hermes-agent` — not relevant, correctly ruled out
A **general-purpose personal AI assistant runtime** (Telegram/Discord/Slack/CLI, self-improving memory, cron automation), not a coding/SDLC tool. Real HN coverage exists (including a plagiarism-claim controversy), but it's out of scope for this project.

### `kroegha/claude-code-hybrid-agents` — too small to trust, one idea worth noting
0 stars, 2 forks, untouched since a single day (Nov 2025). Too small/unvetted as a reference. One concrete idea: a **JSON-based "context protocol"** for inter-agent handoff between sequential workflow stages — a typed alternative to ECC's prose-only handoff descriptions.

### `usejina/awesome-engineering-agents` — link list only
Curated list across 12 categories (editors, codegen, testing, review, DevOps, security, docs, PM...), no code. Useful for discovery, not architecture.

---

## 6. Deep dive: `agency-agents` convert.sh / install.sh architecture

Cloned and reverse-engineered `scripts/lib.sh`, `scripts/convert.sh` (731 lines), `scripts/install.sh` (1324 lines), plus the registry data files `tools.json` and `divisions.json`.

### Registry data model (`tools.json`)
Each of the 15 supported clients is one JSON entry:
```json
"cursor": {"id":"cursor","label":"Cursor","kebab":"cursor",
  "scope":{"user":false,"project":true},
  "detect":{"dirs":[".cursor"],"agentsDir":null},
  "version":{"bin":"cursor","args":["--version"]},
  "format":"cursor-mdc","installKind":"per-agent","slugFrom":"name",
  "dest":{"user":[],"project":[".cursor/rules/{slug}.mdc"]}}
```
Two orthogonal fields matter most:
- **`format`** — the render contract. Explicit rule in the source comment: *"the same `format` name guarantees byte-identical output, so two tools may share a format only if their rendered files are identical."*
- **`installKind`** — disk layout mechanism: `per-agent` (one file per agent), `roster` (all agents combined into one file — Aider/Windsurf), or `plugin` (opaque built artifact, CLI-only — Hermes).

`detect.dirs` + `version.bin` drive auto-detection; `dest.{user,project}` are `{slug}`-templated path patterns. **CI enforces the JSON and hardcoded script tool-lists never drift**: `check-tools.sh` fails the build on disagreement. Same pattern for `divisions.json` via `check-divisions.sh`.

### `convert.sh` — the compiler
- Source of truth is plain markdown: YAML frontmatter (`name`, `description`, ...) + body, parsed by two generic `lib.sh` helpers (`get_field`, `get_body`) shared by every converter — exactly one place understands "what is an agent file."
- **Proof it's a real compiler, not a template swap**: `convert_openclaw()` parses the source body line-by-line and buckets `##`-header sections into three separate output files (`SOUL.md`, `AGENTS.md`, `IDENTITY.md`) by keyword matching — semantic recompilation per target.
- `installKind` drives structurally different code: `per-agent` writes one file per agent inline; `roster` tools (`accumulate_aider`, `accumulate_windsurf`) buffer into a temp file, flushed once at the end; `plugin` (hermes) is too complex for bash and shells out to `build-hermes-plugin.py`.
- **Embarrassingly parallel by construction** — each tool writes to its own `integrations/<tool>/` dir with no shared state, so `--parallel` fans out via `xargs -P`.
- **Deterministic, cleaned before regenerating** — no timestamps in output (so diffs are meaningful), `clean_tool_output()` wipes prior output first so renamed/deleted agents don't leave orphans.

### `install.sh` — installer/picker
- **Three-tier selection fallback**: explicit `--tool`/`--division`/`--agent` flags → interactive TTY wizard (`interactive_wizard`, built on `lib.sh` raw-mode `read_key`/`draw_frame` — the actual checkbox-picker UI) → non-interactive auto-detect-everything-found.
- **Detection is dead simple**: `detect_cursor() { command -v cursor || [[ -d ~/.cursor ]]; }` — binary on PATH OR config dir exists.
- **`--link` vs copy** — symlink installs make editing the installed file == editing the source (dev-loop affordance).
- **`ensure_converted()`** lazily runs `convert.sh --tool X` if that tool's integration output is missing.
- **Known upstream bugs encoded as data**: `tool_cap()` hardcodes "OpenCode silently drops agents past ~119 (upstream bug #27988)" and proactively warns if selection exceeds it.
- **Defensive deletes** — before any `rm -rf`, double-checks the resolved path's basename matches expectations, so an ambiguous env var can't cause it to wipe a shared parent directory.
- `--dry-run` prints the full plan and exits without writing.

### Takeaways to steal for this project
1. `tools.json`'s shape is close to ready-made for a client registry — extend with the methodology/stack-pack dimensions it doesn't need.
2. Keep `format` and `installKind` as separate axes — "how it renders" and "how many files it becomes" vary independently.
3. One shared frontmatter parser, many thin per-target converters — only the output side should branch per client.
4. CI-enforced registry/code consistency (`check-tools.sh`-style) is cheap insurance against drift as the client list grows.
5. Three-tier selection fallback (flags → interactive → auto-detect) beats forcing a picker every run.

---

## 7. Project memory references: CodeGraph, agentmemory, and Karpathy's LLM Wiki

Checked three references specifically for the **Memory** and **Knowledge Base** registry concepts from §2 — two repos (CodeGraph, agentmemory; both modest, plausible star counts of 34 and 9, no red flags) plus a design-pattern gist from Karpathy. Together they turn out to cover three complementary facets of "memory": what the code *is* (structural), what's been *decided/logged* over time (session memory), and what's been *synthesized* from external material (domain knowledge).

### `codegraph-ai/CodeGraph` — structural knowledge base
Builds an actual **semantic graph of the codebase** — functions, classes, imports, call chains — via tree-sitter parsers across 38 languages, persisted in RocksDB at `~/.codegraph/graph.db` for instant restart (no re-parsing/re-embedding). Exposes it through 42 MCP tools in five categories: code analysis (impact analysis, complexity, dead imports, circular deps), navigation (hybrid BM25+semantic search, caller/callee traversal), indexing, memory, and PR/change analysis (`pr_context` computes blast radius + test coverage gaps from a git diff).

Genuinely **client-agnostic**: an MCP server (works with any MCP client, not just Claude), plus a VS Code extension for Copilot, plus pre-built rule files (`codegraph-ai/codegraph-rules-for-agents`) teaching Claude/Cursor/Windsurf/Codex/Cline to query the graph before falling back to grep.

Has its own separate "Memory" tool category (7 tools: `memory_store`/`memory_get`/`memory_search`) for project-scoped insights like debugging discoveries and architectural decisions — explicitly distinct from the graph itself, which is auto-derived and rebuildable.

**Relevance**: strongest concrete reference found for the **Knowledge Base engine**. Key architectural insight worth stealing: the split between *derived* knowledge (the graph — always rebuildable from source, cached only for speed, no durability requirement) and *accumulated* knowledge (the memory tools — genuinely can't be regenerated, must persist). Also useful for the **MCP Registry**: the `--profile` flag narrows tool exposure from 42→8 for cost-conscious sessions, and it ships a 47+ directory exclusion list (`.git`, `.aws`, `.ssh`, etc.) as a security default against accidentally embedding credentials — both cheap, worth-copying conventions.

### `jayzeng/agentmemory` — cross-session decision memory
Solves "agents forget everything between sessions" with **plain markdown, git-friendly, local-first, no database**:
```
~/.agent-memory/
├── MEMORY.md          # curated long-term facts
├── SCRATCHPAD.md       # active checklist, injected first every turn
├── daily/2026-02-15.md # append-only daily logs
└── topics/auth.md      # thematic tracking, backlinked to daily entries
```
No formal schema — relies on `#tags` and `[[wiki-links]]` as searchable conventions rather than enforced structure. Optional semantic search via a companion tool (`qmd`) with three modes (keyword ~30ms, semantic ~2s, deep hybrid ~10s). Installs as `SKILL.md` into Claude Code, Cursor, Codex, and a generic Agent skills dir, and runs a priority-budgeted context-injection pipeline before every agent turn (scratchpad → topics → today's log → semantic search hits → MEMORY.md → yesterday's log, capped at 16K chars total).

**Relevance**: essentially the same pattern as Claude Code's own native memory system (a MEMORY.md index plus per-topic files with typed content), but built to be **multi-client and CLI-inspectable** rather than tied to one harness — a real validation of the "artifacts over conversation" principle from §1, operationalized specifically for cross-session memory. Strongest concrete reference found for the **Memory engine**: the daily-log + topic + scratchpad + curated-long-term split, plus the explicit context-injection budget, is a cleaner design than anything ECC or agency-agents offered (ECC only gestures at this via its "continuous-learning-v2" skill, without this level of structure).

### [Karpathy's "LLM Wiki" pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — synthesized domain knowledge, a third distinct pattern
Not a repo — a design pattern (gist). Proposes moving from RAG (search raw docs every query) to a **persistent, LLM-maintained wiki** that compounds over time: each new source is read once, and the LLM extracts key info, updates entity/concept pages, revises summaries, flags contradictions, and maintains cross-references — future queries work against this synthesis instead of re-deriving from scratch.

**Three-layer architecture**: raw sources (immutable — articles, papers, docs; LLM reads but never modifies) / the wiki (LLM-owned markdown — summaries, entity pages, concept pages, an index, a changelog) / the schema (a `CLAUDE.md`-style config encoding structural conventions and ingestion workflows, turning the LLM into a disciplined maintainer instead of a generic chatbot).

**Three workflows**:
- **Ingest** — drop a new source, the LLM reads it, discusses takeaways, writes/updates summaries and entity/concept pages, refreshes the index, logs the operation. A single source can touch 10–15 wiki pages in one pass.
- **Query** — ask questions against the wiki; the LLM searches relevant pages and synthesizes an answer with citations. Useful results get filed back in as new pages, so explorations compound.
- **Lint** — periodic health check for contradictions, stale claims, orphan pages, missing cross-references; the LLM flags gaps and suggests investigations.

**Key files**: `index.md` (content-oriented catalog, every page with a one-line summary — read first when answering queries) and `log.md` (append-only chronicle of ingests/queries/lints — audit trail, simple to parse with plain tools).

**Design rationale**: humans abandon knowledge bases because maintenance overhead grows faster than value; LLMs don't get fatigued, don't forget cross-references, and can touch 15 files in one pass — the human curates sources and asks questions, the LLM does the bookkeeping. Framed as solving what Vannevar Bush's *Memex* (1945) couldn't: an associative personal knowledge store where "the LLM handles" the maintenance problem.

**Relevance**: this is a third, genuinely distinct pattern from the two in this section — not auto-derived like CodeGraph's code graph, and not raw/append-only like agentmemory's daily logs. It's **actively rewritten synthesis**: pages get revised as understanding improves, contradictions get resolved, not just accumulated. Most relevant for a **Knowledge Base engine** that needs to digest external/domain material over a project's lifetime — requirements docs, meeting notes, research spikes, third-party API docs, ADRs-in-prose — rather than code structure or dated session logs. The `index.md` + append-only `log.md` convention is also the third independent source (alongside Claude Code's own native memory design and `agentmemory`) converging on the same shape, which is a good signal it's the right default rather than a coincidence.

### Synthesis: three complementary patterns, not competing
1. **CodeGraph** — auto-derived structural knowledge of code. Rebuild-on-demand, no durability requirement, always in sync with source because it's regenerated from source.
2. **agentmemory** — raw, append-only session/decision memory (daily logs, scratchpad, curated long-term facts). Must persist verbatim; never re-derived; a record of what happened and was decided, in order.
3. **Karpathy's LLM wiki** — synthesized, continuously-revised domain knowledge distilled from external raw sources. Must persist, but unlike agentmemory it's expected to be *rewritten* as understanding deepens, with active contradiction resolution rather than pure accumulation.

A real Memory/Knowledge Base engine probably wants all three, cleanly separated by mutability model: regenerate the code graph, append to the session log, and revise the domain wiki — each on its own cadence, not merged into one undifferentiated "memory" blob.

---

## 8. Build strategy decision: option (c) — shared core engine, CLI-first, built on existing repos

User posed three options: (a) Spring-Initializr-style web UI producing a downloadable zip, (b) CLI only, (c) CLI and/or UI built by reusing/enhancing existing GitHub repos rather than from scratch. **Decision: (c)**, architected as one shared core engine (profile schema, recommender, compiler) exposed first via CLI, with a web UI added later as a thin wrapper over the same core rather than a second implementation. Rationale: real content and a real compiler pattern already exist (BMAD's 21 agents/50 workflows, ECC's 277 skills/67 agents, agency-agents' working convert/install compiler) — the actual gap confirmed across all prior research is the **selection/recommendation layer**, not raw content. Building that from scratch while ignoring existing registries would be wasteful.

### Unifying new-repo and existing-repo bootstrap behind one "project profile"
Both flows should converge on the same normalized profile (stack, architecture shape, team size, SDLC rigor) before any files get generated:
- **Existing repo**: derive the profile via analysis. Don't build a bespoke stack-detector — `codegraph-ai/CodeGraph` (§7) already does cross-file import resolution and call-graph analysis across 38 languages; reuse it as the analyzer that feeds the profile, rather than reinventing "what stack/architecture am I looking at."
- **New repo**: no code to analyze, so an interactive intake (CLI prompts or a UI form) produces the same profile directly. **Starter presets** (Python, Node+React, Node+Angular) are just pre-filled profiles — good, scoped v1 deliverable, consistent with the "one vertical slice first" sequencing from §2.

Once a profile exists (either path), the same recommend→generate pipeline runs regardless of origin: recommend orchestration pattern, SDLC approach, agents, skills, MCP servers, memory setup; then render client-specific files.

### Two-phase bootstrap+sync model (resolves the sync question from §3/Open threads)
Adopted the user's "zip + smart /init" idea as the answer to how syncing works, not a separate problem:
- **Phase 1 (bootstrap)**: CLI or UI-generated zip installs the initial agents/skills/MCP/rules/CLAUDE.md using the idempotent `<!-- GENERATED:START/END -->` block convention (§2).
- **Phase 2 (sync)**: an in-repo command (`/agentstack-sync`) re-runs the same analysis + recommender and refreshes only the generated block, never touching hand-edited content outside it. Add an `agentstack.lock` file (npm-style) recording installed component versions so sync can show a real diff instead of blindly overwriting — the one capability gap neither `agency-agents` nor `caliber-ai-org/ai-setup` currently cover.

### Orchestration pattern picker — costs aren't equal across patterns
No reviewed repo exposes topology as a real choice; each hardcodes one. If exposing it, be honest that the options differ in what they require:

| Pattern | Requires |
|---|---|
| Supervisor-worker (1 level) | Native Claude Code subagents — zero extra infra; what BMAD/ECC/agency-agents already use |
| Sequential pipeline | Chained skills/slash commands (gstack's Think→Plan→Build→Review→Ship) — also native |
| Fan-out/parallel | Git worktree isolation + concurrent subagent runs — native, some scripting |
| Swarm (many agents + humans, shared board) | **Not native to any single client** — needs an external coordination backend; `multica-ai/multica`'s Go+Postgres+WebSocket daemon (§5) is the concrete reference if this is ever built |

v1 scope: ship the first three (all achievable within a single client's native primitives). Treat swarm as a v2 integration with something Multica-shaped, not something the generator can produce as static files.

### Microservices / multi-repo — the least-solved area in everything reviewed
Every framework reviewed (BMAD, ECC, agency-agents, Spec Kit, OpenSpec) is single-repo-scoped. User's two topologies — layered (ui/config/db/backend-core/backend-integration) vs. domain-separated (order-service/payment-service/inventory/customer-service) — need a concept above the single-repo profile: a **workspace manifest** (sibling file or meta-repo root) declaring topology type, shared org-wide overrides (common conventions, a shared Jira/Confluence MCP server, shared review-agent rules) inherited by every repo, plus per-repo stack overrides that stay local.

**Genuinely unsolved**: cross-repo-aware agents (e.g. "this API contract changed in order-service, does payment-service's consumer code still match?"). Nothing reviewed does structural cross-repo awareness — Multica's task board spans repos operationally but not structurally. Plausible v2+ direction: extend CodeGraph's graph concept across repo boundaries into a "service graph." Don't overpromise this in v1 — bootstrap each repo independently, unify only via the shared workspace manifest.

### Community contributions — curate, don't open-dump
ECC's own community criticism ("277 skills, but cherry-pick, don't install the whole thing" — §4) is a direct warning against unmoderated upload. Reuse two existing patterns instead of inventing a new one: ECC's provenance block (`license`, `version`, `homepage`, `metadata.author`) as required metadata on every submission, and `agency-agents`' CI-enforced registry-consistency pattern (`check-tools.sh`) extended to lint submissions (loads correctly, no embedded secrets, schema-valid) before merge — a verified-publisher tier rather than a free-for-all.

### Monetization reality check
Developer-tool audiences convert poorly on display ads (heavy ad-blocker usage, low RPM) — AdSense is realistically a minor secondary stream, not a primary one. A **hosted sync/pro tier** (private org registries, Phase-2 sync as a subscription, extra starter presets) is a more standard and viable path, and is also the actual justification for building a web UI beyond "nicer than a CLI." This implies needing accounts/auth in the architecture from the start if gating anything — worth deciding early rather than retrofitting.

### Recommended build order — **superseded by §9**
> Note: this build order was revised after the Claude Code plugin-ecosystem research in §9. Kept for the record; the §9 build order is current.
1. Core engine (profile schema, recommender, compiler) as a library — no UI yet.
2. CLI wrapping it; one preset each for Python / Node+React / Node+Angular; single-repo only; supervisor-worker + sequential-pipeline patterns only.
3. Phase-2 sync command + `agentstack.lock`.
4. Web UI as a thin wrapper over the same core (natural point to add accounts/monetization).
5. Workspace manifest for multi-repo; swarm pattern via Multica-style backend; community submission pipeline — all v2+.

---

## 9. Revised approach: build it as a Claude Code plugin + marketplace (plugin-ecosystem research)

Re-reviewed the whole plan against **Claude Code's native plugin system** — a gap in all prior sections (§2, §3, §8 were designed as if packaging/distribution/updating had to be built from scratch). Three findings reshape the architecture.

### Finding 1: the packaging + distribution problem is already solved
A [Claude Code plugin](https://code.claude.com/docs/en/plugins-reference) bundles agents, skills, commands, hooks, MCP configs, and LSP servers into one versioned installable unit (`.claude-plugin/plugin.json` + `commands/`, `agents/`, `skills/`, `hooks/`, `.mcp.json`). A [marketplace](https://code.claude.com/docs/en/discover-plugins) is just a git repo with `.claude-plugin/marketplace.json` — free hosting on GitHub, installed via `/plugin marketplace add user/repo`, versioned and updatable when the maintainer ships a new release.

Consequences:
- **Resolves the "unit of a component" open thread**: the component IS a plugin (for Claude Code, at least).
- **Kills the zip-download idea** from §3/§8 — install-from-git is native; nobody needs a zip.
- Replaces most of the custom CLI + distribution machinery for the Claude side. Community contribution = PRs to a marketplace repo.

### Finding 2: Anthropic already built the recommend-only half of this idea
The official [`claude-code-setup` plugin](https://claude.com/plugins/claude-code-setup) (Anthropic-verified, ~179k installs) analyzes package.json/language files/directory structure and recommends automations across exactly the five categories this project targets: **MCP servers, skills, hooks, subagents, slash commands** (top 1-2 per category by default, 3-5 on request).

But it is deliberately **read-only — it recommends and stops**. It does not: install anything, generate files, handle new repos (nothing to analyze), select orchestration patterns, select SDLC methodology, set up memory, or handle multi-repo. That's both validation (Anthropic considers the recommender valuable enough to build and verify) and a precise map of the differentiation: **recommendation → actually installed, configured, syncable harness**.

### Finding 3: the content layer already ships as plugins — recommend, don't curate
The [official marketplace](https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json) has 180+ verified plugins spanning databases (mongodb, neon, planetscale, clickhouse, cockroachdb...), deployment (azure, cloudflare, deploy-on-aws, hostinger), testing (playwright), monitoring (datadog, honeycomb, grafana, posthog), per-language LSPs (gopls, jdtls, clangd, csharp, kotlin, php, lua...), and SDLC workflow (code-review, feature-dev, commit-commands). There's also an [Anthropic community marketplace](https://claudemarketplaces.com/) with automated validation/safety screening, plus large third-party ones.

Methodology packs already exist as plugins too: [PabloLION/bmad-plugin](https://github.com/PabloLION/bmad-plugin) (BMAD v6 — 9 agents, 26 workflows, `/plugin marketplace add PabloLION/bmad-plugin`), the BMAD core team is [building an official marketplace installer (issue #746)](https://github.com/bmad-code-org/BMAD-METHOD/issues/746), and [Spec Kit has plugin setups](https://www.claudedirectory.org/plugins/spec-kit).

**Consequence**: the recommender mostly **maps a project profile to existing plugin IDs** rather than curating hundreds of skills — a dramatically smaller content burden than §2 assumed. Original content is only needed where nothing exists (SDLC phase agents, memory scaffold, workspace manifest tooling).

### Revised architecture: one plugin + one marketplace
- **`/harness-init`** (command in the plugin): interviews the user (new repo) or analyzes the codebase (existing repo — optionally delegating deep analysis to `claude-code-setup`'s approach and/or the CodeGraph MCP from §7) → writes a **project profile** artifact into the repo.
- **Recommender skill**: profile → concrete manifest: which methodology plugin (BMAD/Spec Kit/OpenSpec), which stack plugins from existing marketplaces, which orchestration pattern (§8 table), which hooks/gates, which memory scaffold (§7 three-tier design).
- **Generator**: writes `AGENTS.md`/`CLAUDE.md` generated blocks, `.mcp.json`, memory scaffolding, and a lockfile recording installed components + versions.
- **`/harness-sync`**: re-runs analysis + recommendation, diffs against the lockfile, refreshes only generated blocks. (Independently validated by the small [project-bootstrapper](https://github.com/kev52/project-bootstrapper) repo's "bootstrap then maintain with audits and syncs" loop.)
- **Own marketplace repo**: hosts original content (SDLC phase agents, memory skills, workspace-manifest tooling). Community contribution = PRs validated by CI (agency-agents `check-tools.sh` pattern, §6; Anthropic's community marketplace sets the automated-screening precedent).
- **Other clients (Cursor/Copilot/Codex) become an export path, not a parallel build**: `AGENTS.md` is the universal core 28+ tools read (§2); the agency-agents compiler pattern (§6) handles client-specific formats as a later `harness-export --client cursor` feature. **Claude-first because the rails exist there; export second.**
- **Web UI demotes to a profile builder** emitting a one-liner (`/plugin marketplace add you/harness && /harness-init --profile <url>`) — far cheaper than an Initializr-with-zip. Monetization attaches to hosted profiles / private org marketplaces rather than AdSense (consistent with §8's monetization reality check).

### Plugins directly useful for building this (from the official marketplace unless noted)
| Plugin | Use for this project |
|---|---|
| `plugin-dev` | The toolkit for authoring plugins — start here |
| `claude-code-setup` | Reference recommender to study and differentiate against (recommend-only vs. this project's install+generate+sync) |
| `claude-md-management` | Overlaps the idempotent CLAUDE.md-generated-block requirement — evaluate before building custom |
| `hookify` | Authors hooks from markdown rules — the quality-gates engine (§1 principle 4) nearly for free |
| `dash0` / `langfuse-observability` | OpenTelemetry for Claude Code sessions/tool calls — the **Observability engine (§2) solved outright** |
| LSP family (gopls, jdtls, clangd, csharp, kotlin, php...) | Per-stack recommendations the recommender maps to |
| `playwright`, `code-review`, `feature-dev`, `commit-commands` | SDLC building blocks (e2e testing, evaluation engine, traceability chain) |
| `context7` | Version-specific docs lookup — knowledge layer |
| `github` / `gitlab` / `atlassian` / `linear` | Task-engine MCP integrations |
| [PabloLION/bmad-plugin](https://github.com/PabloLION/bmad-plugin), Spec Kit plugin (third-party) | Methodology packs — already installable, no adapter authoring needed for Claude |

### Competitor scan (bootstrap-focused repos found in this round)
- [buildmate](https://github.com/vadim7j7/buildmate) — bootstraps Claude Code agent configs with stack overlays (Rails, Next.js, React Native, FastAPI) + PM workflow + quality gates. Closest small competitor.
- [project-bootstrapper](https://github.com/kev52/project-bootstrapper) — one command → composable CLAUDE.md, git hooks, scoped subagents, structured feature workflow, then maintains with audits/reviews/syncs. Validates the sync loop.
- [dark-software-factory](https://github.com/jrhoades1/dark-software-factory) — methodology-as-composable-skills (CITADEL build methodology, security hardening, HIPAA, scaffolding, onboarding).
- [alinaqi/claude-bootstrap (Maggy)](https://github.com/alinaqi/claude-bootstrap) — config pack + optional local server with multi-model routing and plugin orchestration.

**None combine recommendation + installation + methodology choice + memory + multi-repo. The gap remains open.**

### Revised build order (supersedes §8)
1. **The plugin**: `/harness-init` (interview + analyze → profile) + recommender skill + generator (AGENTS.md/CLAUDE.md blocks, `.mcp.json`, memory scaffold, lockfile). Built with `plugin-dev`.
2. **Own marketplace repo** hosting the plugin + original content (phase agents, memory skills), CI validation on PRs.
3. **`/harness-sync`** + lockfile diffing.
4. **`harness-export --client cursor|copilot|codex`** — the agency-agents-style compiler as an export feature (AGENTS.md core + per-client rendering).
5. **Web UI as profile builder** (emits the install one-liner; natural point for accounts/hosted-profile monetization).
6. **v2+**: workspace manifest for multi-repo, swarm via Multica-style backend, community submission pipeline at scale.

### Decisions taken with this revision
- **Claude-Code-first** confirmed as the strategy: build native plugin/marketplace first, treat other clients as an export feature — a deliberate narrowing vs. the earlier "all clients equal" framing, justified by the rails already existing on the Claude side. (User confirmed.)
- Component granularity resolved: **a plugin is the unit** (for Claude); the compiler decomposes it per-client on export.
- Zip distribution dropped entirely.

---

## Open threads / not yet decided
- Command naming — `/harness-init` vs `/bootstrap` vs something else; it's the product's front door, decide early.
- Whether to recommend the existing BMAD/Spec Kit plugins as-is vs. wrapping them behind the methodology contract from §2 (the contract idea still matters for `harness-export` to non-Claude clients).
- Exact shape of the "methodology contract" (artifact types + lifecycle stages every pack must satisfy).
- Whether to add a formal `depends_on` field for skill/component prerequisites (ECC and agency-agents both lack this; plugin.json may partially cover it — verify).
- How exactly `/harness-init` should relate to Anthropic's `claude-code-setup` — delegate to it, reimplement its analysis, or both (fallback if not installed).
- Whether the Memory/Knowledge Base engine should combine all three patterns from §7 (CodeGraph-style rebuildable structural index, agentmemory-style append-only session log, Karpathy-style synthesized/revised domain wiki) as separate mutability tiers, and how they'd share a single context-injection budget.
- Whether to implement Karpathy's ingest/query/lint triad as actual skills in the registry (e.g. `wiki-ingest`, `wiki-query`, `wiki-lint`), and whether `index.md`/`log.md` should be the standard convention across all three memory patterns for consistency.
- Exact schema for the `workspace.yaml` multi-repo manifest, and how far to go on cross-repo-aware agents (flagged as an open research problem, not a template-copy).
- Exact format of `agentstack.lock` and what a `sync` diff/merge UX looks like when a user has hand-edited outside the generated block but the recommendation itself changed.
- Auth/accounts architecture for a future hosted pro tier, and how much of the monetization plan (AdSense vs. subscription) to design for now vs. defer.
