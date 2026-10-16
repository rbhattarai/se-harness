# Release notes — v1.3.1

A packaging fix for GitHub Copilot: `/harness-init` no longer asks you to clone the framework repo next to your project.

## What was wrong

The Copilot plugin shipped without `templates/` and `registry/`, and its commands pointed at a side-by-side clone of
this repo. Installing the plugin (VS Code "Install from source" or `copilot plugin install`) was not enough, and
`/harness-init` stopped with "the required sibling framework checkout is absent".

## What changed

- **The Copilot plugin now bundles `templates/` and `registry/`**; commands read them from `tools/harness/`.
- **`/harness-init` Step 0a vendors everything from the installed plugin** into the repo's `tools/harness/`: scripts
  (including `migrations/` and `doc-registry/`, which were previously skipped), templates, registry, agents and
  `plugin.json`. It searches the VS Code `agent-plugins` cache and `~/.copilot`, re-checks inside each unit of a
  workspace loop, and falls back to a sibling clone only as a last resort.
- **Old installs get a clear message** instead of a request to clone: on Copilot, update the plugin
  (`copilot plugin update se-harness-copilot`, or update/reinstall in VS Code); on Claude Code, `/plugin marketplace
  update se-harness` then `/plugin update se-harness`, and restart.
- **Stale vendored files are caught**: `/harness-sync` compares `tools/harness/plugin.json` with the installed plugin
  and offers to re-vendor; `/harness-update` says to do it after a Copilot plugin update.
- `/harness-export` now works from the vendored `tools/harness/` (`export-agents.sh` finds `agents/` and accepts
  `NAME.agent.md`).

## Upgrading

Copilot: `copilot plugin update se-harness-copilot` (or update in Agent Customization → Plugins), then re-run
`/harness-init`. Repos that already have `tools/harness/` from an earlier version: run `/harness-sync`, which offers
to refresh it. Claude Code: `/plugin marketplace update se-harness`, `/plugin update se-harness`, restart.
The vendoring path follows the plugin cache locations observed for VS Code; the Copilot CLI location
(`~/.copilot`) is unverified, in which case Step 0a asks you for the plugin folder.

406 tests in CI (402 at v1.3.0).
