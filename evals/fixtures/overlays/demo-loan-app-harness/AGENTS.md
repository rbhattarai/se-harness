<!-- SEAA:GENERATED:START — managed by se-harness; sync rewrites ONLY this block. -->
# demo-loan-app

A two-app demo loan product — loan-webapp (borrowers) and lending-webapp (lenders) — sharing a
flat-file JSON data store and syncing in real time via webhook + SSE. Originally built as a test
target for AI-agent SDLC tooling (se-harness) and Playwright E2E testing.

## Stack
- Languages: typescript, node
- Frameworks: express, ejs
- Data: none (flat-file JSON store, no database or messaging)
- CI/containers: github-actions, docker-compose · Cloud: none yet
- Methodology: se-harness (artifacts in `.harness/requirements/`, stories in Jira: not configured)

## Organization conventions & libraries (compose-first)
**Rule: compose before you code.** Before writing any new component, utility, or service code,
check the internal libraries below. Hand-roll ONLY when nothing fits — and say so in the PR
description ("no internal component for X").

No internal libraries, preferred/banned library pairs, or org guideline URL are recorded —
`/harness-scan` confirmed no private registry or internal-scope imports in this codebase.
Re-run `/harness-init --update` or `/harness-sync` if org conventions are established later.

These rules are machine-checked by a post-edit hook (`.harness/org-rules.txt`) — violations warn
and must be resolved or justified before PR.

## Memory (progressive disclosure — do not bulk-load)
- Index: `.harness/memory/MEMORY.md` (one line per entry — read this, then open only what you need)
- Structure: query the code-graph MCP, don't grep blindly
- Domain: `.harness/memory/wiki/` (Karpathy-style; `index.md` first)
- Per-turn hot set is injected automatically by the context-injector hook

## Workflow
Goals go through `/harness-goal`: grill → deep-dive → refined REQ (⛔ human approves) → Jira
story + XRay tests → implement in worktrees → e2e (planner/generator/healer) → ⛔ human PR gate
→ docker-compose local verify → ⛔ human deploy gate. Requirement ID threads through branch,
commits, and PR.
<!-- SEAA:GENERATED:END -->

<!-- Hand-written notes below this line survive every sync. -->
