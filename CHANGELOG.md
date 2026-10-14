# Changelog

All notable changes to se-harness. Format follows [Keep a Changelog](https://keepachangelog.com/);
versions follow [SemVer](https://semver.org/). Full release notes for tagged versions are on the
[Releases page](https://github.com/rbhattarai/se-harness/releases); the draft for the next one is
[docs/release-notes-next.md](./docs/release-notes-next.md).

## [Unreleased]

### Added
- **Local regression evals (`evals/`)** — offline, manual, no Docker; the model API is the only network use.
  Layer 1 (194 deterministic cases against the real hook and script code, plus grader self-tests and an
  oracle/null/reckless pipeline self-test), Layer 2 (headless single agent/skill evals: requirement grill,
  stack detection, architect, story writer, unit-tester mutation score), Layer 3 (full `/harness-goal` loop
  with a simulated human, hidden acceptance tests and a pressure scenario). Statuses pass / fail / error /
  skip / xfail / xpass; baselines and `--compare`. See [docs/evals-plan.md](./docs/evals-plan.md).
- **Observability is a recorded decision** — `observability:` block in `profile.yaml` and
  `workspace.yaml`'s `shared:` with status `unset | deferred | declined | configured`. "Not yet" is asked
  again at the next `/harness-sync`; "no thanks" never is. `scripts/decision-review.sh` reports the state
  (never a secret value).
- **`/harness-bootstrap --reconfigure <observability|memory|methodology>`** — shows what is in force and
  changes it later. `/harness-sync` surfaces the same decisions.
- **Langfuse, per surface, using the real integrations** — Claude Code: the `langfuse-observability` plugin
  (keys in the OS keychain, `LANGFUSE_BASE_URL`). Copilot CLI: no plugin exists, so native OpenTelemetry via
  `scripts/langfuse-otel-env.sh` (keys from `.env.harness`; prompt-content capture is opt-in).
- **Dash0 (Claude Code only)** — `dash0@claude-plugins-official`, user scope recommended, ingest-only token in
  the keychain, one plugin identity at a time. Copilot is recorded as manual.
- **Methodology choices** — `/harness-init` offers se-harness (built-in), OpenSpec, Spec Kit and BMAD.
- `scripts/irreversible-cmd.sh` — a shell-aware classifier of push / PR / deploy commands, used by the gates.
- README: "Where it has been used" (single repo, mono repo, multi-repo) and an accurate telemetry statement.
- `PRIVACY.md`: section on opt-in observability. Test suite: 377 tests (331 at v1.1.0).

### Changed
- The README telemetry badge reads "opt-in": se-harness itself sends nothing, but a backend you choose does.
- The export commands and the Copilot setup guide now list `irreversible-cmd.sh` among the scripts to vendor.

### Fixed
Found by the evals (32 bugs in all); the notable ones:
- **Gates:** `gate-check.sh` / `contract-check.sh` matched push and deploy commands by substring; they now
  classify real commands (env prefixes, `sudo`, git global options, `bash -c`, `eval`, `gh api`, docker /
  kubectl / helm / terraform / npm publish / cloud deploys) and never fail open if the helper isn't vendored.
- `gate-check.sh` read status from anywhere in a requirement file; it now reads frontmatter only, and a
  table row counts as done only when it is exactly `done`.
- `new-requirement.sh` mis-numbered after REQ-007 (octal arithmetic) and corrupted goals containing
  backslashes.
- `org-validate.sh` pattern boundaries for names ending in a letter or digit.
- `workspace-validate.sh` rejected `shared.methodology: se-harness`; it now accepts all four values.

## [1.1.0] — 2026-10-13
`/harness-update` with schema migrations, hand-edit-safe generated blocks, any-format NAS documents in
`/harness-mem-wiki`, and a self-contained plugin (`templates/` and `registry/` now ship inside it). See the
[release notes](https://github.com/rbhattarai/se-harness/releases/tag/v1.1.0).

## [1.0.0]
Six commands, 199 tests. See the [Releases page](https://github.com/rbhattarai/se-harness/releases).
