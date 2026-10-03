# Workspace-Level Harness: Adaptive Topology and Agentic Orchestration Plan

> Design doc for the workspace-orchestration work tracked in `brainstorm.md` A7/A8. Moved here
> from a personal working file once it started driving real implementation (phase 1 landed in
> commit `dd17e81`). Status markers below follow `brainstorm.md`'s convention.

**Status**: ✅ **All 9 phases implemented.** One-line-each summary:

1. Additive `workspace.yaml` model + `workspace-validate.sh` (`dd17e81`) — a manifest with
   none of the new keys is untouched; nothing existing breaks.
2. Workspace-level `/harness-init` entry point, opt-in confirmed cloning
   (`workspace-clone.sh`), modulith/hybrid detection (confirmed, never inferred silently),
   evidence-required `components:`/`relationships:` proposals, `/harness-scan` scope-awareness.
3. Methodology and non-code sources default to workspace scope, inherited by every unit
   unless explicitly (and visibly, via a code comment) overridden.
4. `/harness-init` records a tier-1 structural-memory driver choice (never installs it);
   `/harness-bootstrap`/`/harness-scan` read it back instead of re-asking or probing.
5. `/harness-goal` builds an evidence-backed impact map and only creates `workspace-plan.md`
   when it spans 2+ components (§5.0's fast path); `gate-check.sh` blocks push/PR/deploy
   while any row isn't `done`.
6. A `workspace-orchestrator` agent (12th in the roster) works rows directly, crossing into
   an already-cloned sibling repo's tree rather than handing that off to the human — still
   stopping at each repo's own PR/deploy gates, falling back honestly when it can't (§9).
7. The orchestrator checks cross-repo capability per surface *before* attempting it (full
   locally, never on the Copilot cloud coding agent's single-repo sandbox, conditional on VS
   Code); `gate-check.sh`'s message was reordered/capped for Copilot's 500-char deny-reason
   truncation; `copilot-hook-adapter.sh` confirmed to need no changes. `docs/interop-matrix.md`
   documents all of this.
8. `workspace-plan.md` gained `integration: pending|passed|failed` — all rows `done` means
   each passed its *own* gate in isolation, not that the pieces work together (§5.4);
   workspace-orchestrator runs a combined check (compose + cross-repo contract-check +
   spanning e2e) before `passed`, putting a contradicted row back to `blocked`.
9. Documentation/regression pass: modulith + hybrid worked examples
   ([setup guide Part 3a](./setup-guide-claude.md#part-3a--example-c-modulith-and-hybrid)),
   the demo walkthrough revised to show the actual workspace-plan/orchestrator/integration
   behavior on its real cross-unit goal, and the §13 acceptance criteria below re-audited
   against evidence (two honest ⚠️ partials carried to §14, not silently claimed done).

Full phase detail and the files each one touched: §12.

## 0. Revision notes (se-harness review pass)

This revision folds in six changes from a review against the se-harness codebase as of commit
`dc5bf87`, before any implementation started:

1. **§3 — the manifest is additive, not a replacement.** Today's `templates/workspace.yaml`
   (`workspace:` + flat `units:` + `contracts:`) is read literally by `contract-check.sh` and is
   already documented and in use (including the user's own `finance-portal` trial). The new
   `components:`/`relationships:` model is a new, optional section layered onto the existing file,
   not a schema that replaces it. Nothing that reads the current shape breaks on upgrade.
2. **§5.3/§6 — the shared task plan reuses the existing REQ/gate file machinery** instead of a new
   parallel state system. `gate-check.sh` already greps REQ frontmatter to block push/PR/deploy, and
   `harness-goal.md`'s own rule is "every phase output is a file with status frontmatter — never
   chat-only." The workspace plan is a sibling file under the same `REQ-NNN/` directory, not a new
   kind of state.
3. **§4.5/§8 — the memory-driver framing is scoped to tier 1 only.** "Choosing a driver"
   (Graphify vs. codebase-memory-mcp vs. CodeGraph) applies to the **structural** tier alone, which
   se-harness already treats as an open, swappable bake-off. The session log (tier 2) and domain
   wiki (tier 3) stay plain markdown regardless of topology — this was a deliberate ruling
   (git-diffable, human-inspectable, survives a client switch), not an oversight, and workspace
   support doesn't change it.
4. **§4.2 — auto-clone is opt-in and confirmed per repo, not merely "safe."** se-harness's existing
   posture is that the human clones side-by-side themselves; nothing in the framework touches other
   repos' working trees unprompted. Automated cloning must show the exact plan (URLs, destination
   paths, what already exists) and get explicit confirmation before acting — the same opt-in
   discipline `/harness-bootstrap` already uses for every installable component.
5. **§5 — a fast path for single/few-component work.** Most requirements, including most real
   work on a single product, touch one or two components. The orchestrator only engages once the
   impact map crosses **two or more** components; a single-component change hands off directly to
   that component's existing agent roster with none of the new ceremony. This keeps principle 2
   ("a single repo should not need workspace configuration just to use the existing workflow")
   true in practice, not just in intent.
6. **§12 — phases land as independently reviewable increments** against this repo's actual
   contribution model: edit `plugins/se-harness/` (the Claude-first source), regenerate
   `plugins/se-harness-copilot/` via `build-copilot-plugin.sh`, pass the test suite
   (`tests/run-tests.sh`), one phase per PR. No phase ships as one large orchestrator-subsystem drop.

A smaller, incidental fix: §3's example used `version: 1` for what is actually a second schema
generation; renamed to `schemaVersion: 2` throughout so it doesn't read as "first version."

## 1. Purpose

Evolve se-harness from a repository-only setup tool into a workspace-level harness that can
understand and coordinate software projects of different shapes:

- Single repo: one repository contains the application.
- Monorepo: one repository contains multiple applications, services, or packages.
- Modulith: one deployable application contains distinct, intentional modules.
- Multi-repo: multiple repositories make up a product or enterprise application.
- Hybrid: a combination, such as a monorepo frontend alongside separately versioned services.

The harness should let a user describe a requirement once — for example, "Add AI chat to the
e-shopping cart" — and produce a traceable plan that identifies the affected components,
repositories, contracts, tests, and documentation. It should coordinate the implementation while
preserving clear boundaries between workspace-wide decisions and repo-local work.

## 2. Core design principles

1. The workspace is the coordination boundary; repos and modules are implementation boundaries.
   Shared methodology, system relationships, and task coordination belong to the workspace. Stack
   and implementation details belong to their respective repos or modules.
2. Support structures without forcing them into one model. A single repo should not need
   workspace configuration just to use the existing workflow. A workspace may contain repos,
   monorepo packages, modules, or combinations.
3. Discover, explain, and confirm. Use repository metadata, code structure, tests, manifests,
   documentation, and memory to recommend topology and relationships. Show evidence and ask for
   confirmation where inferences affect behavior.
4. Use explicit coordination rather than relying on agent-to-agent chat. Maintain a shared,
   inspectable plan with owners, dependencies, decisions, contracts, and test results. Agents may
   message when the runtime supports it, but the workflow must also work without direct messaging.
5. Keep changes attributable and bounded. Every task has an owner and scope. Cross-boundary
   changes require explicit assignment and integration checks.
6. Ground plans in evidence. Code, configuration, tests, and non-code sources should inform
   decisions with source references and freshness information. Memory is an aid to discovery, not
   a substitute for checking current repository state.

## 3. Workspace model

**This extends `workspace.yaml`; it does not replace it.** The file already exists today, is
already documented (`docs/setup-guide-copilot.md` / `setup-guide-claude.md` Parts 2-4), and is
already read literally by `scripts/contract-check.sh` in its current shape: `workspace:`
(name/topology/layout), a flat `units:` list (`name` + `path` or `repo` + `stack`), and
`contracts:` (name/file/provider/consumers). None of that moves or gets renamed.
`components:`/`relationships:` below are **optional, additive** sections for workspaces that need
finer-grained modeling than one `unit` per repo (monorepo packages, moduliths) — a workspace happy
with "one unit = one repo" never needs them, and `contract-check.sh` keeps working against
`contracts:` unchanged. A workspace file with none of the new keys is exactly today's file, and
every existing script must treat it identically to before — that is the backward-compatibility
bar for phase 1.

A conceptual example of the additive sections (`schemaVersion` is new; its absence means "today's
shape only, nothing below applies"; it's `2` because today's unversioned shape is implicitly
version 1):

```yaml
schemaVersion: 2    # new, optional key — omit it and this is exactly today's workspace.yaml

workspace:
  name: e-shopping
  topology: hybrid   # existing field; "hybrid" is a new allowed value alongside mono-repo/multi-repo

units:                 # UNCHANGED shape — existing one-unit-per-repo entries keep working as-is
  - { name: storefront, repo: <url>/storefront.git, stack: [react, typescript] }

components:             # NEW, optional — only for finer-than-one-repo granularity
  - id: storefront-ui
    kind: application
    boundary:
      type: repo          # repo | monorepo-package | module
      path: storefront     # must resolve to (or inside) a declared unit — never a dangling path
    role: customer-ui

  - id: cart-api
    kind: service
    boundary:
      type: monorepo-package
      path: backend/services/cart-api
    role: backend-service

  - id: cart-domain
    kind: module
    boundary:
      type: module
      path: backend/packages/cart-domain
    role: business-logic

relationships:          # NEW, optional — richer than contracts:, which still works unchanged
  - from: storefront-ui
    to: cart-api
    type: calls          # calls | publishes-to | consumes-from | depends-on | owns-data-for |
                          # deployed-with | tested-by
    evidence: contracts/cart-api.yaml   # required — see 3.1; no evidence, no relationship

contracts:               # UNCHANGED — existing deterministic provider/consumer checks
  - name: cart-api
    file: contracts/cart-api.yaml
    provider: cart-api
    consumers: [storefront]

shared:                  # UNCHANGED shape; memory scopes to tier 1 only — see 4.5/8
  org: {}
  mcp: []
  memory:
    structural_driver: null   # tier 1 only — never touches the tier-2/3 markdown tiers
```

This example illustrates the concepts, not a finalized schema. The design should reuse existing
se-harness profiles, lockfiles, generated-file conventions, and migration patterns where possible.
The manifest must not contain credentials.

> **Implemented in phase 1** (`templates/workspace.yaml`, `plugins/se-harness/scripts/
> workspace-validate.sh`): the `schemaVersion`/`components`/`relationships` keys above, and a
> validator enforcing uniqueness, boundary-type/path validity, and the evidence requirement below.

### 3.1 Model components and relationships

Represent components independently of repositories. A component may be:

- A whole repository.
- An application or service inside a monorepo.
- A module inside a modulith.
- A shared library, infrastructure package, or data component.

Represent relationships explicitly where known, such as `calls`, `publishes-to`,
`consumes-from`, `depends-on`, `owns-data-for`, `deployed-with`, `tested-by`.

Every relationship **requires** an `evidence` reference — an API spec, package-manifest
dependency, docker-compose `depends_on`, service configuration, or an explicit user
confirmation recorded with a date. A relationship with no evidence field does not get written to
the manifest; it stays an open question in the discovery report (§4.3) instead of becoming a
graph edge. This keeps `relationships:` a deterministic, auditable structure like today's
`contracts:` rather than a graph of LLM guesses — the same discipline principle 3 already asks for.
Unknown relationships should remain unknown rather than being guessed.

### 3.2 Scope configuration

| Concern | Default scope | Details |
|---|---|---|
| Methodology and shared workflow | Workspace | One shared methodology by default; allow documented exceptions. |
| Topology and component relationships | Workspace | Covers repos, monorepo components, modules, and cross-boundary dependencies. |
| Stack and code profile | Repo or component | Keep language, frameworks, and local conventions close to the code. |
| DevOps and cloud | Repo or component | Keep deployment and operations facts local, with workspace links for shared infrastructure. |
| Non-code sources | Workspace, optionally scoped | Ask whether sources exist and which components or topics they apply to. |
| Structural-memory driver (tier 1 only) | Workspace-selected, with scoped indexing | Tier 1 only — see §4.5/§8. Tiers 2/3 are always plain markdown, at every scope. |
| Agent instructions | Workspace plus repo/component scope | Orchestration instructions at workspace level; implementation context at local level. |

## 4. `/harness-init`

### 4.1 Detect the setup target

When run in a Git repository, preserve the existing single-repo initialization path. If the user
wants broader workspace behavior, allow them to opt into workspace setup.

When run in a non-Git directory, offer workspace initialization. If there is a `repos.txt`, use it
as a bootstrap inventory; if not, ask the user how they want to define the starting structure.
Support both supplied repositories and existing local child directories.

### 4.2 Acquire repositories safely — opt-in, confirmed per repo

Cloning is **off by default**. se-harness's existing posture for multi-repo setup is that the
human clones side-by-side themselves (`docs/setup-guide-copilot.md`/`setup-guide-claude.md` Part
2) — nothing in the framework touches another repo's working tree unprompted. Automated cloning
is an explicit opt-in that mirrors how `/harness-bootstrap` already treats every installable
component ("composable, opt-in — users cherry-pick; never install everything"):

1. Build the **clone plan** first, without touching disk: validated URLs, the predictable
   workspace-relative destination path for each, and whether that path already exists (and if so,
   whether it looks like the expected repo, an unrelated directory, or a partial/failed clone).
2. **Show the plan and ask for confirmation** — for all repos at once, or one at a time if any
   destination collisions were found. Nothing clones until confirmed.
3. Clone only the confirmed repos. Never reset, overwrite, or delete an existing directory or
   repo. Preserve successful clones if another clone fails later in the batch, and support
   resuming the remainder without repeating completed work.
4. Report clone failures clearly, per repo, without blocking the repos that already succeeded.
   Keep credentials out of inventory files, manifests, and logs.

The harness performs the clone itself (not an unreviewed ad hoc shell script the user has to
trust blindly) using a dedicated, reviewable script, with shell and PowerShell variants that
behave identically — same pattern as the existing `scripts/*.sh` + the Windows/Git-Bash notes
already in the setup guides.

### 4.3 Discover topology and components

Scan available evidence such as Git roots, project manifests, build files, package boundaries,
deployment configuration, API specs, tests, and documentation. Use these to recommend:

- Topology: single repo, monorepo, modulith, multi-repo, or hybrid.
- Applications, services, modules, libraries, and infrastructure components.
- Likely component relationships (see §3.1 — only ones with cited evidence become candidates).
- Existing contracts and test boundaries.

Present the recommendation with supporting evidence and ask the user to confirm or correct it. A
directory name or repo name is a clue — not proof of a component's role.

### 4.4 Configure shared and local context

Ask for or confirm:

- Workspace methodology and any deliberate exceptions.
- Stack and DevOps/cloud details for each relevant repo or component.
- Whether non-code sources exist.
- If sources exist: their locations, scope, access constraints, and how they should be used.
- Known system relationships, ownership, and important contracts.

If no non-code sources exist, continue without blocking initialization. Do not ingest a source
until the user has identified it and the relevant access and integration are supported.

### 4.5 Select and configure structural memory (tier 1 only)

This step configures **only the tier-1 structural-memory driver** — Graphify, codebase-memory-mcp,
or CodeGraph, per the registry's existing bake-off entry (`registry/recommendations.json` →
`memory.structural`). It does not touch tiers 2/3:

- **Tier 1 (structural, this step)**: a code-structure/code-graph tool for navigating symbols,
  dependencies, and code relationships — rebuildable, swappable, chosen here.
- **Tier 2 (session log)** and **Tier 3 (domain wiki)**: always plain, git-diffable markdown under
  `.harness/memory/`, at every topology — single repo, multi-repo, or workspace. This was a
  deliberate ruling (not an oversight): markdown stays human-inspectable, diffable, and survives a
  client switch, which a graph database or vector store gives up. Workspace support changes
  *where* those files live relative to each other (workspace-level `MEMORY.md`/wiki vs. per-repo),
  never *what format* they're in.

Let the user choose among the supported tier-1 drivers, explain prerequisites/scope/limitations,
configure the chosen driver for the confirmed components, check prerequisites, and report what was
successfully indexed with source provenance and freshness. If a driver cannot index a source type,
say so and offer a supported alternative rather than implying that it can. Non-code knowledge
(architecture docs, requirements, runbooks, API decisions) is always tier 2/3's job
(`wiki-ingest`), never the tier-1 driver's, regardless of which driver is chosen.

### 4.6 Generate and validate

Generate the workspace manifest additions, shared guidance, repo/component profiles, and agent
definitions from confirmed inputs. Preserve user-authored content and existing generated-file
conventions (the `SEAA:GENERATED` block markers). Before replacing generated artifacts, make the
changes reviewable.

Validate manifest structure, paths, discovered boundaries, memory prerequisites, and generated
configuration. Summarize what was configured, what remains unknown, and any failures.

## 5. Requirement-to-work orchestration

### 5.0 Scale coordination to impact size

Build the impact map (§5.2) before deciding how much ceremony applies:

- **Impact spans 0-1 components**: skip the orchestrator entirely. Hand off directly to that
  component's existing agent roster — the exact single-repo `/harness-goal` flow that already
  works today, unchanged. No workspace plan file, no cross-component task graph.
- **Impact spans 2+ components**: the orchestrator engages as described in §5.3-§5.4.

This is not an optimization to add later — it is the mechanism that keeps principle 2 true
("a single repo should not need workspace configuration just to use the existing workflow") for
the common case, which on most real products is most requirements.

### 5.1 Understand the request

Translate the request into user-visible behavior, affected capabilities, and acceptance criteria.
Identify ambiguity that would materially change the design; ask the user instead of inventing
product behavior.

For a request such as "Add AI chat to the e-shopping cart," clarify or infer-with-confirmation
details such as:

- What the chat assistant is allowed to do: answer questions, recommend products, modify a cart,
  or complete purchases.
- Which existing AI provider or model is approved.
- Whether chat history is saved and for how long.
- Authentication, privacy, accessibility, and performance requirements.
- Required rollout, configuration, and monitoring behavior.

### 5.2 Build an evidence-backed impact map

Combine current repository inspection with relevant workspace memory to identify candidate
components. Examine evidence such as:

- Workspace topology and component relationship graph.
- Repo/component profiles and dependency manifests.
- API, event, and schema contracts.
- Tests and deployment/configuration files.
- Relevant architecture, requirements, security, and operations documents.
- Code graph/index results, if configured (tier 1).

For each proposed impact, record why it is included, the evidence source, and confidence. Check
the current code before treating previously indexed memory as authoritative. If the graph does not
show a likely path to a component, do not include that component merely because its name sounds
relevant. The component count from this step feeds §5.0's fast-path decision.

### 5.3 Create a dependency-aware work plan — on the existing REQ artifact, not a new state system

se-harness's rule is that every phase output is a file with status frontmatter, never chat-only
(`harness-goal.md`), and `gate-check.sh` already greps REQ frontmatter to enforce the approval
gates. The workspace plan reuses that machinery rather than inventing a parallel one: it is
`.harness/requirements/REQ-NNN/workspace-plan.md`, a sibling of `design.md`/`story.md` under the
same REQ directory, with one row per task:

- Component/repo ownership and allowed write scope.
- A clear outcome and acceptance criteria.
- Dependencies and ordering constraints.
- Required contracts or interface changes.
- Relevant evidence and documentation.
- Unit, integration, and end-to-end validation.
- Assumptions, risks, and user decisions still needed.
- Status per row (`pending` / `in-progress` / `done` / `blocked`), so `gate-check.sh` can extend
  its existing frontmatter check to also confirm every row reached `done` before PR/deploy — one
  more grep on a file shape it already understands, not a new state system to keep in sync.

Parallelize independent tasks; serialize tasks that depend on an agreed API, schema, or design.
The orchestrator should avoid parallel implementation against a contract that has not yet been
decided.

### 5.4 Coordinate implementation and integration

The workspace orchestrator assigns work to repo/component agents, tracks results in
`workspace-plan.md`, and routes blockers or contract changes. Agents report completion with
changed files, decisions, test evidence, and follow-up dependencies. Cross-boundary changes update
the shared plan and relevant contracts.

After local work, run the planned integration checks against the actual combined changes. The
orchestrator reports incomplete tasks, contract mismatches, and failed validation; it must not
describe the whole feature as complete solely because individual agents finished.

## 6. Agent roles

**Workspace orchestrator** — one per workspace, the primary coordinator when §5.0 determines a
requirement spans 2+ components. Owns requirement decomposition, impact mapping, task assignment,
dependency management, shared decisions (via `workspace-plan.md`), integration planning, and
status reporting. It coordinates testing but is not named only a "test orchestrator" — testing is
one responsibility among several.

**Repo/component agents** — one agent per confirmed repo or useful component boundary, not one
per hypothetical specialty. Use a meaningful role-based name when confirmed (e.g. `frontend-agent`,
`backend-core-agent`); otherwise a neutral name derived from the boundary. Each agent receives its
local profile, relevant shared architecture and contracts, and only the workspace context needed
for its task. It stays within its assigned write scope unless the orchestrator explicitly grants a
cross-boundary task.

**Integration/test responsibility** — validates changes across boundaries. May be a dedicated
agent when useful; otherwise the orchestrator assigns the responsibility to a capable repo agent
or runs the checks itself. Avoid a permanent agent for every possible concern by default.

**Optional specialists** (database, security, release, …) — invoked when the requirement and
supported runtime justify them. They supplement component ownership; they do not replace it.

**Agent lifecycle** — `/harness-init`/`/harness-scan` scaffold or update agent definitions; agents
are never launched to create, update, or delete other agents. During feature work, the
orchestrator selects from configured roles and delegates supported tasks. If the workspace lacks a
needed role, propose the change for user review rather than silently rewriting agent
configuration — the same human-confirms-consequential-change discipline the hook-enforced gates
already apply everywhere else in this framework.

## 7. Worked example: AI chat for an e-shopping cart

Suppose the confirmed workspace contains a frontend, cart backend, AI integration service,
database, and deployment configuration — five candidate components, so §5.0 routes this through
the full orchestrator path.

| Component | Possible work | Evidence to verify |
|---|---|---|
| Frontend | Chat UI, streaming/loading/error states, accessibility, cart context display | Frontend profile, routes, UI conventions, existing API client |
| Cart backend | Authenticated chat endpoint or cart-aware orchestration; enforce cart ownership and permitted actions | Service graph, API contract, authorization code, tests |
| AI integration service | Provider/model integration, prompt and tool boundaries, timeouts, retries, provider configuration | Service configuration, integration docs, approved-provider guidance |
| Database | Only if persistence is required: conversation/session schema, retention and deletion behavior, migration | Data ownership docs, existing schemas, retention policy |
| Shared API/event contracts | Define request/response and streaming or event format between UI and backend | Existing OpenAPI/AsyncAPI contracts and service relationships |
| Deployment/configuration | Provider secrets via approved secret store, feature flag, resource limits, rollout config | Deployment manifests, environment conventions, operations docs |
| Tests | UI behavior, service/API contract, provider adapter, authorization, integration, and end-to-end flow | Existing test layout and CI workflows |
| Documentation/operations | User behavior, operational monitoring, failure modes, support/runbook updates | Workspace documentation sources and operational standards |

This is a candidate plan, not an automatic assumption. For example, if the product does not need
persisted history, the database task may be excluded. If the AI integration already exists, the
work may be limited to exposing a safe cart-aware capability. The orchestrator should cite the
evidence behind each inclusion and ask about unresolved product or policy decisions.

A sensible ordering is:

1. Confirm behavior, data handling, and permitted AI actions.
2. Agree on the API/streaming contract and security boundaries.
3. Implement independent UI and AI-provider work against the agreed contract where safe.
4. Implement backend orchestration and any approved data/configuration changes.
5. Integrate components, run contract and end-to-end checks, and update docs/operations.

## 8. Memory and knowledge behavior

Memory should help the orchestrator answer questions such as "Which service owns cart mutations?"
or "What is the approved AI-data retention policy?" It should return evidence, not just a
generated answer:

- Source file or document, location, and relevant excerpt or symbol.
- Source scope: workspace, repo, or component.
- Index/update time or staleness indicator where available.
- Confidence or uncertainty.
- Whether the evidence is current code, indexed memory, or user-confirmed guidance.

Use tier-1 structural memory for code structure and navigation only; use tier-2/3 markdown
(session log / domain wiki) for non-code artifacts and decisions — these are composable tiers, not
interchangeable capabilities, per §4.5. When sources disagree, surface the conflict and prefer
neither silently (the same rule `wiki-ingest`'s contradiction handling already follows). High-impact
design, security, privacy, and data-retention decisions should be confirmed against authoritative
sources or by the user.

## 9. Runtime compatibility

Keep the workspace manifest and task plan independent of a specific coding client. A runtime
adapter can translate the plan into the agent format and capabilities available in a client.

At runtime, detect or configure whether the client supports agent definitions, parallel
delegation, shared task state, direct agent messaging, and cross-repo workspaces. If a capability
is missing, use a sequential or user-mediated handoff while preserving the same tasks and
evidence. This is not hypothetical: Claude Code and Copilot CLI already diverge on hook semantics
today (`PreToolUse` deny behaves differently across Copilot CLI/coding-agent vs. VS Code, per
`docs/setup-guide-copilot.md` Part 6) — the adapter layer generalizes a gap that already has to be
worked around. Do not promise autonomous multi-agent coordination just because agent files exist.

## 10. `/harness-scan`

Make scanning scope-aware:

- In a single Git repo, preserve current behavior.
- At a workspace root, scan workspace configuration and each declared repo/component; report
  shared and local findings separately.
- Detect moved, missing, or newly discovered boundaries without silently rewriting the manifest.
- Show evidence and confidence for inferred topology and relationships.
- Ask before changing confirmed roles, methodology, memory setup, or generated files.
- Allow a local scan without changing unrelated workspace configuration.

## 11. Safety and quality requirements

- Never destructively reset, clean, overwrite, or delete existing repos during setup or recovery.
- Respect dirty worktrees; report status before operations that could affect them.
- Validate clone destinations and manifest paths.
- Keep credentials and sensitive data out of manifests, memory results, logs, and agent prompts
  unless an approved secure mechanism explicitly requires access.
- Bound agent write scopes and make generated changes reviewable and idempotent.
- Surface clone, indexing, tool, and validation failures explicitly.
- Ensure agents do not claim completion without reporting the changes and evidence requested by
  their task.
- Preserve the existing single-repo workflow throughout implementation.

## 12. Suggested implementation phases

Each phase lands as its own reviewable increment against `plugins/se-harness/` (the Claude-first
source of truth), regenerated into `plugins/se-harness-copilot/` via `build-copilot-plugin.sh`,
and gated on `tests/run-tests.sh` passing — this repo's existing contribution model
(`docs/setup-guide-claude.md`/`setup-guide-copilot.md` Part 10), not a new process. No phase ships
as one large orchestrator-subsystem drop.

1. ✅ **Workspace model** (additive) — IMPLEMENTED, commit `dd17e81`: extended
   `templates/workspace.yaml` with the optional `schemaVersion`/`components`/`relationships` keys;
   `contract-check.sh` and every existing consumer keep working unchanged against
   `units:`/`contracts:`. `plugins/se-harness/scripts/workspace-validate.sh` validates the new
   sections (no-op on a manifest with no `schemaVersion`); covered by `tests/run-tests.sh`,
   including a regression proving `contract-check.sh`'s behavior is unaffected.
2. ✅ **Discovery and initialization** — IMPLEMENTED: `/harness-init` Step 1 now detects
   whether it's running inside a repo (unchanged path) or at a candidate workspace root
   (`repos.txt`-driven bootstrap, Step 1a); `plugins/se-harness/scripts/workspace-clone.sh`
   does the opt-in, plan-then-confirm, never-overwrite cloning (§4.2). Step 3 (topology) now
   asks explicitly before concluding `modulith` (directory structure is a clue, never a silent
   conclusion) and proposes `hybrid` when mono-repo/modulith structure and multi-repo
   membership are both confirmed. Cross-unit `components:`/`relationships:` are proposed only
   with cited evidence (§3.1) and validated via `workspace-validate.sh` before being written.
   `/harness-scan` gained the same detection rules for re-scans plus a workspace-root guard
   (full multi-repo-in-one-pass scanning is still §10, not yet done).
3. ✅ **Scoped configuration** — IMPLEMENTED: `workspace.yaml`'s `shared:` block gained
   `methodology`/`confluence_spaces`/`sharepoint_sites` alongside the existing `org`/`mcp`/
   `jira_project`. `/harness-init` Steps 4-5 read these first and only ask when still empty,
   then offer to write the answer back so every other unit inherits it; a repo that deviates
   records why as an inline comment next to the field in its own `profile.yaml` — a documented
   exception, never a silent one. `/harness-scan` flags **undocumented** deviations on re-scan
   instead of silently re-detecting independently per repo. `workspace-validate.sh` now checks
   `shared.methodology` against the known enum, regardless of `schemaVersion` (this field
   predates the additive schema). Stack/DevOps/cloud remain repo-scoped by design — unchanged.
4. ✅ **Structural-memory integration** (tier 1 only) — IMPLEMENTED: `/harness-init` gained
   Step 6, which records a `memory.structural_driver` choice (workspace-scoped when a manifest
   exists, repo-scoped otherwise) from the registry's existing bake-off list, or an explicit
   `null` (deferred — valid). Init never installs anything; `/harness-bootstrap` reads the
   recorded choice back and skips re-asking, going straight to installing that one driver.
   `/harness-scan` reads it too, to look for that specific driver instead of probing
   generically. `templates/AGENTS.md.tmpl` names the chosen driver in its generated Memory
   section when set, falling back to generic wording when not. No change to tiers 2/3.
5. ✅ **Task planning** — IMPLEMENTED: `/harness-goal` step 2 builds an evidence-backed impact
   map (component, evidence, confidence); step 3 applies §5.0 — 0-1 components continues
   exactly as before (no new file, no ceremony), 2+ components renders `templates/
   workspace-plan.md` into `REQ-NNN/workspace-plan.md` (one grep-able row per component,
   `status: pending`/`in-progress`/`done`/`blocked`), presented for the **same** approval as
   the REQ, not a second gate. `gate-check.sh` now also blocks push/PR/deploy while any
   approved REQ's workspace-plan.md has a row that isn't `done` — a REQ with no such file is
   completely unaffected (verified by regression tests). Cross-repo rows in step 5 are handed
   off as "run `/harness-goal` in that repo, referencing this REQ id" — honest about there
   being no automated dispatch yet (phases 6-7).
6. ✅ **Agent scaffolding** — IMPLEMENTED: `agents/workspace-orchestrator.md` ships with the
   plugin (12th in the roster, like every other agent — not dynamically generated per
   workspace) and is only *invoked* when `workspace-plan.md` exists (§5.0). Repo/component
   agents are the existing roster, unchanged — no new agent type per repo, per §6's own
   guidance. It does cross-repo rows' work directly (Bash `cd` into an already-cloned sibling
   tree) rather than nested subagent dispatch, since that capability isn't reliably available
   across runtimes (§9) — it never claims a row is in progress if it can't actually act on it,
   falling back to the phase-5 handoff instead. It never bypasses a repo's own PR/deploy gates.
7. ✅ **Runtime adapters** — IMPLEMENTED: `workspace-orchestrator.md` checks per-surface
   cross-repo capability *before* attempting a sibling-repo row (Claude Code CLI/desktop and
   Copilot CLI: full local FS access; Copilot coding agent: never, single-repo sandbox by
   design; VS Code Copilot Chat: conditional on the open workspace, checked with
   `[ -d <sibling-path> ]`) and falls back to the phase-5 manual handoff when it can't, instead
   of claiming progress it can't make. `gate-check.sh`'s workspace-plan.md block message was
   reordered (actionable line first) and capped (5 rows + true count) so Copilot's 500-char
   deny-reason truncation can never cut off the instruction. Verified `copilot-hook-adapter.sh`
   needs no changes — it translates purely on exit code, agnostic to *why* a script blocked.
   `docs/interop-matrix.md` gained a row documenting all of this per platform.
8. ✅ **Integration validation** — IMPLEMENTED: `workspace-plan.md`'s frontmatter gained
   `integration: pending|passed|failed`. Once every row is `done`/`blocked`,
   workspace-orchestrator runs the combined check against the *actual* combined
   changes — workspace-level `docker-compose` smoke test, `contract-check.sh` re-run in every
   touched repo, and any e2e specs that span components — before setting `integration:
   passed`; a contradicted row goes back to `blocked`, never stays a false `done`.
   `gate-check.sh` requires `passed` in addition to all-rows-`done` (a missing field defaults
   to blocked, never an implicit pass). `/harness-goal` steps 6/8 point at the same combined
   compose rather than each writing a narrower, repo-only check.
9. ✅ **Documentation and regression** — IMPLEMENTED: added
   [setup guide Part 3a](./setup-guide-claude.md#part-3a--example-c-modulith-and-hybrid)
   (modulith + hybrid worked walkthroughs — the two topologies that had schema/detection
   support since phase 2 but no worked example anywhere). Corrected Part 3.4's stale
   "worktree fan-out across repos" claim (worktrees only ever worked within one repo;
   cross-repo dispatch is workspace-orchestrator crossing via `cd`, from phase 6) to describe
   the actual impact-map → workspace-plan → orchestrator → integration-check flow. Revised
   `docs/demo/README.md`'s real cross-unit goal walkthrough to show workspace-plan.md and the
   integration check actually firing, not pre-phase-1 behavior. §13's acceptance criteria
   re-audited against concrete evidence (test names, file references) rather than left as an
   unchecked wishlist — found and recorded two genuine partial gaps (§14) instead of silently
   marking everything done. Regenerated the Copilot variant and confirmed zero diff (phase 9
   touched docs only); full suite still 188/188.

## 13. Acceptance criteria (phase 9 audit — ✅ verified / ⚠️ partial, with evidence)

- ✅ **Existing single-repo initialization and scanning continue to work without a workspace
  manifest.** `/harness-init` Step 1 only branches on git-repo detection (unchanged path
  inside a repo); Step 3 falls through to `single` when no markers/signals/multi-repo answer
  apply. Every script the new steps touch (`workspace-validate.sh`, `workspace-clone.sh`)
  early-exits with no manifest present.
- ✅ **Existing multi-repo workspaces with no `schemaVersion`/`components`/`relationships`
  keys continue to work identically to before.** Verified: "workspace-validate: today's shape
  (no schemaVersion) exits 0", "contract-check: additive manifest, no contract change, exits
  0" and "...still flags a real contract change" (`tests/run-tests.sh`, phase 1).
- ✅ **The workspace model can represent single repo, monorepo, modulith, multi-repo, and
  hybrid structures.** `templates/workspace.yaml`'s `topology:` comment lists all five;
  `/harness-init` Step 3 detects/confirms each explicitly (modulith via a direct question,
  hybrid via the combined confirmation); worked through in
  [setup guide Part 3a](./setup-guide-claude.md#part-3a--example-c-modulith-and-hybrid).
- ✅ **Topology and component relationships are evidence-backed suggestions confirmed by the
  user where needed; a relationship with no `evidence` field is never written.**
  `workspace-validate.sh` rejects an evidence-less relationship row (tested); Step 3 instructs
  "only with the evidence attached ... never a written entry."
- ✅ **Shared methodology is configured at workspace scope by default; stack and DevOps/cloud
  remain local by default.** Phase 3: `shared.methodology` + Step 4's inherit-or-ask logic.
  Stack/DevOps/cloud were never added to `workspace.yaml` — absence of change, by design.
- ⚠️ **Non-code sources can be absent, workspace-wide, or scoped to selected components** —
  *partial*. Absent/workspace-wide are implemented (phase 3: `shared.jira_project`/
  `confluence_spaces`/`sharepoint_sites`). Scoping a *specific* source to only some components
  (e.g. "this Jira project applies only to the billing module") was never built — there is no
  schema field for it. Carried to §14 as an open decision rather than silently claimed done.
- ✅ **The structural-memory driver choice never implies a choice of format for tiers 2/3.**
  Phase 4: explicit "tier 1 ONLY" language in `/harness-init` Step 6 and both templates'
  comments.
- ✅ **A feature request yields an inspectable impact map and dependency-aware plan before
  changes begin, and single/few-component requirements skip orchestration overhead
  entirely.** Phase 5: `/harness-goal` Step 2 (impact map) + Step 3 (§5.0 fast path).
- ⚠️ **The orchestrator can coordinate parallel and sequential work ... using
  `workspace-plan.md` as the shared, inspectable state** — *partial, honestly*.
  `workspace-plan.md` is confirmed as the sole shared state (no agent-to-agent messaging
  anywhere — phase 6 deliberately avoided nested subagent dispatch, §9). The
  *dependency-aware ordering* is real (`depends_on` serializes correctly). **True concurrent
  execution of independent rows is not implemented** — one orchestrator session works rows
  one at a time even when the dependency graph would allow parallelism; building real
  parallelism would mean spawning concurrent sessions, which runs into the same
  nested-dispatch reliability question phase 6 explicitly declined to assume. Carried to §14.
- ✅ **Cross-boundary work includes explicit contracts and integration validation.** Phase 8:
  `contract-check.sh` re-run per touched repo + combined compose smoke test +
  `integration: passed/failed`, enforced by `gate-check.sh` (8 new fixture tests).
- ✅ **Agent capabilities are adapted to the active runtime rather than assumed.** Phase 7:
  explicit per-surface capability check (local full access / cloud coding agent never /
  VS Code conditional) before attempting cross-repo work, not after failing.
- ✅ **Setup and recovery do not destroy existing repos ...; cloning never happens without
  explicit per-repo confirmation.** Phase 2: `workspace-clone.sh`'s plan-then-confirm,
  never-overwrite design — collision detection and untouched-content verified by fixture
  tests that assert the pre-existing file content is byte-identical after a blocked attempt.

## 14. Open design decisions

- Whether `repos.txt` is only a bootstrap input or remains a maintained inventory.
- Supported ways to represent component boundaries in monorepos and moduliths beyond the three
  `boundary.type` values sketched in §3 (`repo`/`monorepo-package`/`module`).
- Exact `evidence:` field shape for `relationships:` — a single path/URL, or a richer
  `{source, excerpt, confirmed_by, date}` structure (leaning toward the latter, to match how
  wiki-ingest already records provenance).
- Which agent runtimes are supported initially (Claude Code first, per the rest of this
  framework's dual-publish order) and the shared orchestration contract for Copilot CLI's
  different hook/agent-messaging capabilities.
- Whether agent definitions live at workspace level, in repos, or both, based on client discovery
  rules.
- How generated guidance merges with user-authored agent instructions and repo-specific
  exceptions.
- Exact threshold mechanics for §5.0 — "2+ components" is the starting rule; whether it should
  also weigh contract/relationship criticality (e.g. a one-component change to a widely-consumed
  contract might still warrant orchestrator visibility) is open.
- **Per-component scoping of non-code sources** (§13 audit, phase 9): `shared.jira_project`/
  `confluence_spaces`/`sharepoint_sites` are workspace-wide or absent today; there's no schema
  for "this source applies only to components X and Y." Worth a field if a real workspace
  needs it (e.g. one Confluence space per product line within one workspace) — not built
  speculatively ahead of that need.
- **True parallel execution of independent `workspace-plan.md` rows** (§13 audit, phase 9):
  dependency-aware *ordering* is real; concurrent *execution* isn't — one orchestrator session
  works rows sequentially regardless of what the dependency graph would allow. Building real
  parallelism means either spawning concurrent sessions (hits the same nested-dispatch
  reliability question phase 6 declined to assume — §9) or a job-queue-style external
  coordinator (Multica-shaped, already flagged as v2+ infrastructure in `brainstorm.md` B5/B8).
  Not pursued here; sequential-but-correct was the acceptance bar for phases 5-8.
