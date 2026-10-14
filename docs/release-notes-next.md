# Release notes — next release (draft)

> Draft for the next tagged release. The version number is not decided yet (no version bump or tag has
> been made); copy this into the GitHub release when it is cut and delete this file's "draft" banner.

Observability becomes something you can change after init, the gates stop trusting substring matches, and
the repo gains a local eval suite that protects the prompts and hooks from regressions.

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

377 tests in CI (331 at v1.1.0).

## Upgrading

```
/plugin marketplace update se-harness
/plugin update se-harness
```

Restart Claude Code, then run `/harness-update` in each project. Existing projects show observability as
`unset`; the next `/harness-sync` asks once. Copilot CLI: `copilot plugin update se-harness-copilot`.
