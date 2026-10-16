# Release notes — v1.4.0

`/harness-goal` now reviews its own generated code against Karpathy's discipline, clean code and SOLID/design-pattern
smells, through a new read-only `reviewer` agent.

## What changed

- **New `reviewer` agent.** Read-only (Read, Grep, Glob and read-only git). It reviews only the REQ's merged diff, so it
  stays cheap and never turns into a refactor of untouched code. Priority order: (1) Karpathy discipline — every changed
  line traces to an acceptance criterion, nothing speculative; (2) clean code; (3) SOLID and design-pattern problems the
  diff itself introduced, each tied to a concrete cost. Karpathy's rules win over SOLID/patterns: an abstraction with one
  caller is a finding, not a virtue.
- **`/harness-goal` step 5.6.** Runs for size M and L changes, skipped for S. `block` and `fix` findings go back to the
  owning implementer (no separate refactor agent), then tests and the reviewer run once more; a second red round goes to
  the user. Findings are written to `REQ-NNN/review.md` and summarised in the Gate 2 evidence table.
- **`design-principles` convention area.** `/harness-conventions` can draft the project's own rules on SOLID, patterns
  and clean code from evidence. A confirmed doc overrides the reviewer's defaults.

## Upgrading

Claude Code: `/plugin marketplace update se-harness`, `/plugin update se-harness`, restart. Copilot:
`copilot plugin update se-harness-copilot`, then `/harness-sync` to refresh a vendored `tools/harness/`.

The reviewer has no dedicated eval yet; its quality rests on the prompt. 409 tests in CI (406 at v1.3.1).
