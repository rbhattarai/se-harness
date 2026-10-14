# Release notes — v1.2.0 (draft)

> Draft for the v1.2.0 release (versions are bumped to 1.2.0; no tag has been made). Copy this into the
> GitHub release when it is cut and delete this file's "draft" banner.

The agents now follow your organization's coding conventions and internal libraries, `/harness-goal` checks
conventions and memory and sizes a change before it starts, observability becomes something you can change after init, the gates stop trusting substring matches, and
the repo gains a local eval suite that protects the prompts and hooks from regressions.

## Conventions the agents actually follow (new)

- **`/harness-conventions`** captures coding conventions and internal-library usage as per-area docs
  (`.harness/conventions/<area>.md`: MUST/SHOULD rules with evidence, a "use this library for X" catalog,
  golden example files, a review checklist). It detects from lint configs, library sources, how code calls
  the libraries and existing instruction files (all optional), and asks you to confirm each inferred rule.
- The docs are indexed in `org.convention_docs` and in AGENTS.md; the nine implementer, tester and architect
  agents read the matching doc before writing code, and the `/harness-goal` automated gate reviews the diff
  against the MUST rules.
- **Workspace docs sync into units**: a shared library's catalog is written once at the workspace root and
  mirrored into each unit's profile with a unit-relative path. `/harness-sync` has a new axis E that detects
  index/file drift, stale docs and missing inherited guardrails.
- Optional export to `.github/instructions/*.instructions.md` for Copilot.

## `/harness-goal` looks before it leaps (new)

- **Preflight**: checks conventions and memory readiness (code index present and fresh, domain wiki built
  for the configured sources) before the grill, offers the fixing command (`/harness-mem-graphify`,
  `/harness-mem-wiki`, `/harness-conventions`) and runs a light memory lookup so the grill is informed.
- **Scope triage**: sizes the goal S/M/L from cited signals. Small and medium goals run as before; a large
  one is analyzed first in Plan mode (no code changes) and, if still large, split into prioritized phases
  implemented one at a time, each with its own gates (`epic` parent REQ plus one child REQ per phase).
- `/harness-bootstrap` ends with a "Next commands" list and offers conventions and the domain wiki as rows.

## Guardrails (new, optional)

`org.guardrails` is rendered as a "Guardrails" section in AGENTS.md when set. `/harness-init` lets you pick
from a preset list (scope, security, secrets, ask-when-unclear, honesty, destructive actions, licensing)
and/or write your own; in a workspace it is asked once and inherited. An instruction, not enforcement.

## Observability you can revisit (new)

- Observability is now a **recorded decision**: `unset`, `deferred` ("not yet"), `declined` or
  `configured`. A deferred choice is asked again at the next `/harness-sync`; a declined one never is.
- **`/harness-bootstrap --reconfigure <observability|memory|methodology>`** shows the choice in force and
  lets you change it. `/harness-sync` reports the same decisions in one line each.
- **Langfuse** is set up the way each tool actually supports it. Claude Code: the `langfuse-observability`
  plugin, keys entered with `/plugin configure` and kept in the OS keychain. Copilot CLI has no Langfuse
  plugin, so it uses native OpenTelemetry through `langfuse-otel-env.sh`; prompt-content capture is off
  unless you pass `--capture-content`.
- **Dash0** (Claude Code only) installs `dash0@claude-plugins-official`, user scope recommended, with an
  ingest-only token in the keychain.
- Nothing is enabled unless you say yes, and se-harness itself still sends no telemetry. See
  [PRIVACY.md](https://github.com/rbhattarai/se-harness/blob/main/PRIVACY.md).

## Methodology choices

`/harness-init` offers **se-harness (built-in)**, OpenSpec, Spec Kit and BMAD. Only se-harness and OpenSpec
are delegated to by `/harness-goal` today. A workspace that chose `se-harness` as its shared methodology
used to fail `workspace-validate.sh`; that is fixed.

## Evals (new, local)

`evals/` is an offline, manual regression suite: 194 deterministic cases against the real hook and script
code, headless single-agent evals, and a full `/harness-goal` loop with hidden acceptance tests and a
pressure scenario. It runs only when you run it. See `docs/evals-plan.md`.

## Fixed

The evals found 32 bugs in the harness; the important ones are in the gates:
- Push, PR and deploy detection now understands real shell commands instead of matching substrings, and it
  blocks (never fails open) when the classifier isn't vendored beside the gate.
- Requirement status is read from frontmatter only; a table row is "done" only when it says exactly `done`.
- `new-requirement.sh` numbered REQ-008 to REQ-010 wrongly and mangled goals containing backslashes.
- Pattern boundaries in `org-validate.sh`.

381 tests in CI (331 at v1.1.0).

## Upgrading

```
/plugin marketplace update se-harness
/plugin update se-harness
```

Restart Claude Code, then run `/harness-update` in each project. Existing projects show observability as
`unset`; the next `/harness-sync` asks once, and reports AGENTS.md template drift (re-render to get the
convention-docs and guardrails sections). New profile keys are additive; no migration. Run
`/harness-conventions` per repo, library repos first. Copilot CLI: `copilot plugin update se-harness-copilot`.
