# Setup Guide: se-harness with Claude Code

A step-by-step guide for bootstrapping the **se-harness** framework with **Claude Code** —
single-repo or multi-repo, new or existing project, any stack. Written for a first-time user.

> Using **GitHub Copilot** instead? See [`setup-guide-copilot.md`](./setup-guide-copilot.md) —
> same framework and artifacts, different install and enforcement mechanics.

## What is this plugin?

**se-harness** wraps an AI-agentic SDLC harness around any software project. It is a Claude
Code **plugin** distributed from this repo (which is itself a plugin **marketplace**).
Installing it gives every Claude Code session:

| Piece | What it does |
|---|---|
| **6 slash commands** | `/harness-init` (intake interview → generates all per-project artifacts), `/harness-scan` (brownfield stack + org-convention detection), `/harness-bootstrap` (recommends & installs companion plugins/MCP servers from `registry/recommendations.json`), `/harness-goal` (the delivery loop: grill → refined requirement → stories/test cases → design → implement → unit/integration/e2e → PR → deploy, with **3 human-approval gates**), `/harness-sync` (four-axis drift detection & refresh), `/harness-export` (compile the harness for Copilot/Cursor) |
| **12 SDLC agents** | architect, story-writer, implementer-backend, implementer-frontend, db-engineer, unit-tester, integration-tester, e2e-planner/generator/healer, release-manager, workspace-orchestrator (multi-component requirements only) — each with a deliberately narrow tool set |
| **8 skills** | stack-detector, requirement-grill, memory-keeper, wiki-ingest/query/lint, context-injector, coding-discipline — auto-activated by task relevance |
| **Hooks (automatic)** | `UserPromptSubmit` injects budgeted memory context; `PreToolUse` **blocks** PR/push/deploy while no requirement is `status: approved` (the HITL gate) and blocks pushes that change a provided cross-repo contract; `PostToolUse` validates edits against your org's banned-library rules and auto-logs commits/PRs to the daily memory log |
| **3-tier memory** | structural code index (rebuildable), append-only decision log with typed causal links, and a synthesized domain wiki — all plain files under `.harness/`, committed with your code |

What it writes into *your* repo: `AGENTS.md` + `CLAUDE.md` (inside `SEAA:GENERATED` markers —
your hand-written content is never touched), `.harness/` (profile, requirements, memory,
org-rules), and `.env.harness` (secrets, gitignored). All tool-agnostic plain files.

**Prerequisites**: Claude Code installed and authenticated; `git`; on Windows, **Git Bash**
(the hook/helper scripts are bash — Claude Code ships with it). For Jira/Confluence
integration, access to the Atlassian MCP server.

---

## Part 1 — Install the plugin

### 1.1 Standard install

Inside any Claude Code session:

```
/plugin marketplace add rbhattarai/se-harness
/plugin install se-harness
```

Verify:
- `/plugin` → Manage → `se-harness` shows as enabled
- `/help` lists `/harness-init`, `/harness-scan`, `/harness-bootstrap`, `/harness-goal`,
  `/harness-sync`, `/harness-export`
- Hooks are live: in a repo with a `draft` requirement, asking Claude to `git push` gets
  blocked by the gate (you'll see the gate's message).

### 1.2 If plugin install is restricted in your organization

**Preferred — internal import.** Don't hand-copy unreviewed zips into firm infrastructure.
Ask your platform/security team to import the public repo into your GitHub Enterprise as an
internal repo (GitHub "Import repository" preserves history; updates stay a `git pull`).
Then the install is the same two commands against `yourorg/<internal-repo>`.

**Last resort — offline zip / local marketplace.** If even marketplace-add-from-GitHub is
blocked:

1. On the repo page: **Code → Download ZIP** (or a tagged release zip). Put it through your
   code review/scanning process.
2. Unzip to a stable path, e.g. `C:\tools\se-harness`.
3. Claude Code accepts a **local directory** as a marketplace:
   ```
   /plugin marketplace add C:\tools\se-harness
   /plugin install se-harness
   ```
4. Caveats: no `git pull` updates — record the source commit SHA next to the copy; after
   replacing the folder with a newer zip, run `/plugin marketplace update` then
   `/plugin update se-harness` (or uninstall/reinstall) to pick up changes.

**Air-gapped fallback (no plugins at all).** The framework still works as prompted files:
clone/unzip it as a sibling folder and drive it the way the Copilot guide does
([4.1](./setup-guide-copilot.md)) — "read `../<framework>/plugins/se-harness/commands/harness-init.md`
and execute its steps". You lose the automatic hooks (gates become CI + branch protection,
see the Copilot guide Part 6) but every artifact is identical.

---

## Part 2 — Example A: single-repo project

Scenario: `task-tracker`, an existing Express + React + Postgres app in one repository.
(A brand-new empty repo works the same — `/harness-init` asks new-vs-existing first and
scaffolds instead of scanning.)

### 2.1 Bootstrap

```bash
cd task-tracker
claude
```

```
/harness-init
```

What happens, in order:

1. **New vs existing** — it detects an existing codebase and runs the scan path:
   `scan-evidence.sh` collects manifests/lockfiles/configs (read-only, bounded), the
   `stack-detector` skill reasons over the evidence (usage beats listing), and you're asked
   to **confirm** — high-confidence findings in bulk, low-confidence ones one at a time.
2. **Interview** — only for what can't be detected: methodology (BMAD / Spec Kit / OpenSpec /
   none), devops/cloud targets, and the **org-context round**: company-internal libraries
   (with registry + purpose), preferred/mandated libraries, banned libraries ("use X never Y"),
   coding-convention sources.
3. **Artifact generation** — everything rendered idempotently via the splicer
   (`render-block.sh`), never raw writes.

### 2.2 Verify (2 minutes)

| Artifact | Check |
|---|---|
| `.harness/profile.yaml` | stack says node/express/react/postgres; `org:` section filled |
| `.env.harness` | created from the example; **fill secrets locally — it's gitignored** |
| `.harness/memory/` | `MEMORY.md`, `SCRATCHPAD.md`, `daily/`, `wiki/` seeds |
| `.harness/org-rules.txt` | one `banned:<pattern>:<hint>` line per use-X-never-Y answer |
| `AGENTS.md` / `CLAUDE.md` | present, content inside `SEAA:GENERATED` markers |

Ask Claude: *"What internal libraries must this project prefer, and what's banned?"* — the
answer must come from AGENTS.md's org section, not general knowledge.

### 2.3 Optional: companion tooling

```
/harness-bootstrap
```

Recommends plugins/CLIs/MCP servers matched to your profile (methodology plugin, LSP,
code-review, context7, Atlassian MCP…). Everything is **opt-in** (multi-select); declines
are recorded in the lockfile and never re-nagged. Where no good plugin exists for a piece of
your stack, it says so honestly instead of inventing one.

### 2.4 First goal through the loop

```
/harness-goal Add CSV export to the reports page
```

1. The **requirement-grill** skill probes scope, edge cases, non-goals — answer honestly.
2. It writes `.harness/requirements/REQ-001.md` (committed, YAML frontmatter,
   `status: draft`).
3. **⛔ Gate 1 — you** review the file and flip `status: approved`. Nothing you say in chat
   substitutes: the `PreToolUse` gate hook physically blocks `gh pr create`/`git push`/deploy
   commands until an approved REQ exists.
4. Stories/test cases (to Jira/XRay if the Atlassian MCP is wired), design, implementation
   (parallel tasks in isolated worktrees via `worktree-task.sh`), unit/integration tests,
   Playwright e2e (planner → generator → healer).
5. **⛔ Gate 2** — PR with evidence; you review/merge through your normal process.
6. **⛔ Gate 3** — deploy requires in-session human approval; the release-manager agent
   hard-stops without it.
7. Close-out: decisions land in the daily log; durable domain knowledge is promoted to
   `MEMORY.md` or the wiki.

That's the entire single-repo lifecycle. Day-to-day you only ever need `/harness-goal` and,
occasionally, `/harness-sync`.

---

## Part 3 — Example B: multi-repo product

Scenario: **acme-loan-platform**, a fictional layered product split across seven repos
(`frontend` Angular/TS · `backend-core` .NET MVC · `backend-integration` .NET · `common`
.NET lib · `ui` Node lib · `config` .prop files · `database-config` MSSQL). Same shape
works for a domain-split (order/payment/inventory) product. For a real, clonable two-app
demo, see [demo-loan-app](https://github.com/rbhattarai/demo-loan-app) and the
[multi-unit walkthrough](./demo/README.md#part-2--multi-unit-walkthrough-the-loan-product).

### 3.1 Workspace layout: side-by-side clones

```bash
mkdir acme-loan-platform && cd acme-loan-platform
git clone <url>/frontend.git
git clone <url>/backend-core.git
git clone <url>/backend-integration.git
git clone <url>/common.git
git clone <url>/ui.git
git clone <url>/config.git
git clone <url>/database-config.git
```

The workspace manifest, contract-check, and cross-repo reading all assume sibling checkouts.

### 3.2 The workspace manifest

Create `acme-loan-platform/workspace.yaml` from `templates/workspace.yaml` — topology, shared org
context, and the **contracts registry** that powers deterministic cross-repo impact checks.
The full acme-loan-platform example (units, `shared.org` internal libraries, `jira_project`, and a
`contracts:` stanza with `provider`/`consumers`) is in the
[Copilot guide, Part 3](./setup-guide-copilot.md) — the file is identical on both platforms.
Two rules: keep the `contracts:` stanza shape exactly as templated (it's machine-read by
`contract-check.sh`), and commit the manifest to a small meta-repo so teammates get it by
cloning. Need component granularity finer than one unit per repo (a monorepo or modulith unit)?
`workspace.yaml` supports an optional, additive `schemaVersion: 2` block for that — see the
Copilot guide's note at the end of its Part 3, and `templates/workspace.yaml`'s commented
example. It's opt-in; `contracts:`/`contract-check.sh` are unaffected either way.

### 3.3 Per-repo bootstrap

`/harness-init` in **each code repo** (`frontend`, `backend-core`, `backend-integration`,
`common`, `ui`) — start with one, get it fully working, repeat. Init detects
`../workspace.yaml`, records the unit name in the profile, and inherits the shared org
context so you don't re-answer the org round seven times. The two non-code repos get the
light treatment: a short hand-written `AGENTS.md` in `config` (`.prop` naming scheme, which
env is which) and `database-config` (object/domain layout, migration process).

### 3.4 What multi-repo adds on Claude Code

- **Contract enforcement, automatically.** The plugin's `PreToolUse` hook runs
  `contract-check.sh` on push/PR commands: if a file listed as a provided contract changed
  (e.g. `backend-core`'s OpenAPI spec), the push is **blocked** with the consumer list
  (`frontend`) until you acknowledge the impact. Standalone check any time:
  `bash "$(git rev-parse --show-toplevel)"/../se-harness/plugins/se-harness/scripts/contract-check.sh --`
  — or just ask Claude to run the contract check.
- **Cross-repo goals** (workspace-orchestration plan, full detail in
  [`docs/workspace-orchestration-plan.md`](./workspace-orchestration-plan.md)). Run
  `/harness-goal` from the repo that owns the primary change. Step 2 builds an impact map from
  `workspace.yaml`; if it names only this repo, everything proceeds exactly as single-repo
  (no extra ceremony — this is the common case even in a multi-repo product). If it names 2+
  repos, step 3 also creates `REQ-NNN/workspace-plan.md` — one row per repo, presented
  alongside the REQ for the same approval — and step 5 hands off to the
  **workspace-orchestrator** agent, which works each row (implementing directly in this repo,
  crossing into an already-cloned sibling repo's tree for a row that lives there) rather than
  you manually re-running `/harness-goal` in each one. Before anything is reported complete,
  it also brings up the workspace-level compose and re-checks contracts across every touched
  repo — passing in each repo individually isn't the same as the combination working, so this
  combined check is a real gate, not a formality.
- **Gates are per-repo, enforced per-repo.** The REQ lives in the primary repo; PRs in the
  other repos link to it. `gate-check.sh` blocks push/PR/deploy anywhere while the REQ isn't
  `approved`, while any `workspace-plan.md` row isn't `done`, or while its combined
  `integration:` check hasn't `passed` — approving the requirement is not approving incomplete
  or unverified cross-repo work.

### 3.5 Verify the workspace

1. In `backend-core`, edit the OpenAPI contract file, then ask Claude to push — expect a
   block naming `frontend` as a consumer. Revert.
2. With no approved REQ, ask Claude to open a PR — expect the gate denial.
3. Ask in `frontend`: *"Which backend contract does this repo consume and where is it
   defined?"* — the answer should come from `workspace.yaml`.

---

## Part 3a — Example C: modulith and hybrid

Two more topologies `workspace.yaml` models (same file, same commands — no separate
machinery). Short, schema-focused walkthroughs; see
[`docs/workspace-orchestration-plan.md`](./workspace-orchestration-plan.md) §3 for the full
model if you want it.

### Modulith: one deployable repo, internal module boundaries

Scenario: a single Spring Modulith service (one deployable JAR) organized into
`billing`/`shipping`/`inventory` packages, each with its own clear boundary but no separate
deployment.

Run `/harness-init` as usual. Step 3 checks for workspace markers (mono-repo signals) first;
finding none, it looks for internal-module signals instead — `spring-modulith` on the
classpath, `@ApplicationModule`-annotated packages, a `src/modules/`-style convention. A
directory layout is a **clue, never a silent conclusion**: it asks you to confirm before
writing anything —

> *"This looks like it's organized into internal modules (evidence: `spring-modulith`
> dependency, `@ApplicationModule` on `billing`/`shipping`/`inventory`). Is this one
> deployable app with internal module boundaries, or should I treat it as a plain single
> repo?"*

Confirm, and it writes `workspace.yaml` with `topology: modulith`, a single unit (`path: .`
— the whole repo is the one deployable thing), and a `components:` entry per module
(`kind: module`), plus any evidenced `relationships:` between them (e.g. `billing` calling
`shipping`'s client, cited by the actual import). Validated with `workspace-validate.sh`
before it reports success. A goal whose impact map stays inside one module runs exactly like
single-repo; one spanning two modules gets the same `workspace-plan.md` treatment multi-repo
gets — the mechanism doesn't care whether "components" means repos or internal packages.

### Hybrid: a repo with its own internal structure, and also part of a bigger product

Scenario: `backend-core` from Part 3's acme-loan-platform example turns out to itself be a
modulith (`billing`/`shipping`/`inventory` modules) **and** a multi-repo unit alongside
`frontend`/`backend-integration`/etc.

Confirm both halves when `/harness-init` asks (the mono-repo/modulith question from above,
*and* "is this repo part of a multi-repo product?" from Part 3). `topology:` becomes
`hybrid`, not `mono-repo` or `multi-repo` alone — the manifest carries both the internal
`components:`/`relationships:` *and* the external `contracts:` registry, at the same time, in
the same file. Nothing else changes: the same impact map, the same fast path, the same
workspace-orchestrator for anything spanning 2+ components whether those components are
internal modules, sibling repos, or a mix of both.

---

## Part 4 — Keeping it healthy

- `/harness-sync` after pulling a framework update or every few weeks: diffs profile
  (re-scan), recommendations vs lockfile, template drift (hash-based), and memory health —
  then refreshes **only** generated blocks after showing you the diff.
- Memory discipline: the hooks auto-log commits/PRs; you (and the agents) add decision
  entries with typed links (`[[REQ-12]] solves [[pricing-lag]]`); `wiki-lint` keeps the
  domain wiki honest (provenance footers, contradiction blocks).
- `.env.harness` is per-machine and never committed; `.harness/` (minus memory/structural)
  is committed and shared.

---

## Part 5 — Updating or extending the plugin

### 5.1 Consuming an update

```
/plugin marketplace update se-harness
/plugin update se-harness
```

Then `/harness-sync` in each managed repo to refresh generated blocks. (Local-marketplace
installs from a zip: replace the folder first, then the same two commands.)

### 5.2 Making your own changes

The iron rule: **edit only `plugins/se-harness/`** — `plugins/se-harness-copilot/` and
`.github/plugin/marketplace.json` are build outputs and get overwritten.

1. Clone the framework repo (your fork or the internal copy).
2. Add or edit components:
   - a command → `plugins/se-harness/commands/<name>.md` (frontmatter `description`,
     `argument-hint`; reference bundled scripts as
     `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<script>.sh"` — always quoted)
   - an agent → `plugins/se-harness/agents/<name>.md` (frontmatter `name`, `description`,
     narrow `tools:` list)
   - a skill → `plugins/se-harness/skills/<name>/SKILL.md`
   - a hook → `plugins/se-harness/hooks/hooks.json` + script in `scripts/`
3. Bump `version` in `plugins/se-harness/.claude-plugin/plugin.json` (and in the generated
   plugin's heredoc inside `scripts/build-copilot-plugin.sh`) — the version field is how
   installed copies detect the update.
4. Validate and regenerate the Copilot variant:
   ```bash
   claude plugin validate plugins/se-harness --strict
   bash plugins/se-harness/scripts/build-copilot-plugin.sh
   ```
5. Test locally before pushing: `/plugin marketplace add <local-clone-path>` in a scratch
   session, install, exercise the new component.
6. Commit source **and** regenerated output, push. Consumers pick it up via 5.1.

---

## Part 6 — Publishing to the marketplaces

This repo **is** a marketplace: `.claude-plugin/marketplace.json` lists both plugins and is
read natively by Claude Code *and* Copilot CLI; the build script mirrors it to
`.github/plugin/marketplace.json` (Copilot's canonical location).

### 6.1 Your own marketplace (available today)

1. `claude plugin validate . --strict` at the repo root (validates the marketplace file too),
   run the build script, commit, push to GitHub, tag a release (`git tag v0.1.0 &&
   git push --tags`).
2. That's publication. Anyone installs with
   `/plugin marketplace add <owner>/se-harness` →
   `/plugin install se-harness`. There is no central Anthropic submission/approval step — a
   public GitHub repo with a valid marketplace manifest *is* a live marketplace.
3. **Enterprise-wide**: admins can pre-install it for every developer via managed settings
   (the `managed` plugin scope) — ask whoever owns your org's Claude Code deployment.

### 6.2 Community marketplace directories (wider discovery)

Community-curated marketplaces and plugin directories aggregate third-party plugins; getting
listed is a **PR against their repo** adding an entry to their `marketplace.json` pointing at
yours:

```json
{ "name": "se-harness",
  "source": { "source": "github", "repo": "rbhattarai/se-harness" },
  "description": "Bootstrap an AI-agentic SDLC harness around any project" }
```

Check each directory's CONTRIBUTING.md for its review bar. Before submitting anywhere:
`--strict` validation passes, README install one-liners are correct, version tagged, and the
Copilot variant rebuilt (reviewers of dual-published repos check both).

### 6.3 GitHub Copilot marketplace

Covered in [`setup-guide-copilot.md` Part 11](./setup-guide-copilot.md): your repo already
serves Copilot CLI directly, and wider discovery means PRs to the two pre-registered
marketplaces (`github/copilot-plugins`, awesome-copilot).

---

## Part 7 — Troubleshooting & FAQ

- **`/harness-*` commands missing after install** → `/plugin` → Manage → confirm
  `se-harness` is enabled; restart the session (commands register at session start).
- **Scripts fail on Windows** → they run under Git Bash via the hook commands; if running
  one manually, use Git Bash, not PowerShell/cmd.
- **Gate blocks a push you believe is legitimate** → the gate is working: check
  `.harness/requirements/` for a REQ with `status: approved`. Only a human flipping the
  frontmatter satisfies it — that's the point.
- **`render-block.sh` says "prepended block"** → the target file had no `SEAA:GENERATED`
  markers; your original content is preserved below the new block — merge once by hand.
- **Do I need the Copilot guide too?** Only if teammates use Copilot. The artifacts are
  identical; both toolchains can work in the same repos simultaneously.
- **Uninstall?** `/plugin uninstall se-harness` removes the plugin; the artifacts in your
  repos (`AGENTS.md`, `.harness/`) are plain files and remain — delete them only if you're
  abandoning the harness.
