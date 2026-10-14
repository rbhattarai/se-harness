# Release notes — v1.3.0

Three more structural-memory drivers get first-class support: **Sourcegraph** (Cloud or self-hosted),
**codebase-memory-mcp** and **CodeGraph** now each have a lifecycle command, like Graphify already did.

## Sourcegraph (new)

- Choose Sourcegraph at `/harness-init` and it records the instance (Cloud or self-hosted), URL, endpoint
  (`/.api/mcp` or `/.api/mcp/all`) and auth (OAuth, or an access token kept in `.env.harness`).
- **`/harness-mem-sourcegraph`** connects it (user-scope, per-repo `.mcp.json` with the token only as a
  `${SOURCEGRAPH_ACCESS_TOKEN}` reference, or the Copilot equivalents), verifies it, and reports which of your
  workspace repos the instance has indexed. It builds nothing; the instance indexes. Requires an Enterprise plan
  with MCP enabled.
- `/harness-goal` uses its cross-repo search for the impact map; `decision-review.sh` shows the instance and a
  missing token variable.

## codebase-memory-mcp and CodeGraph (new commands)

- **`/harness-mem-codebase-memory`** installs only after confirming the exact vendor command, registers the
  server explicitly (the vendor installer otherwise auto-configures about 45 clients), indexes each repo, offers
  its cross-repo linking mode for workspaces, and refreshes. Fixed the `.mcp.json` template, which registered it
  with a `serve` argument the project does not use.
- **`/harness-mem-codegraph`** asks which of the two unrelated CodeGraph projects you mean. colbymchenry/codegraph
  is fully supported (install, `init`, registration with the callers/callees/impact tools enabled, and the
  telemetry question asked rather than assumed); codegraph-ai/CodeGraph is register-and-verify only.
- `/harness-bootstrap` hands off to all of these, and `/harness-goal`, `/harness-scan` and `/harness-sync` point to
  them when a driver is not connected or an index is stale.

## Upgrading

```
/plugin marketplace update se-harness
/plugin update se-harness
```

Restart Claude Code, then run `/harness-update` in each project. Copilot CLI:
`copilot plugin update se-harness-copilot`. Existing projects are unaffected; the new profile keys are additive and
used only when you choose one of these drivers (`/harness-bootstrap --reconfigure memory` to switch).
Caveat: the new commands follow each project's README and have not been exercised against the live tools.

402 tests in CI (381 at v1.2.0).
