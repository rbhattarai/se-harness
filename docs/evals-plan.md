# Eval plan — status

Plan and status log for the harness's regression evals (`evals/`, usage in
[`evals/README.md`](../evals/README.md)). Written so the work can be picked up later.
Last updated: 2026-10-13. Status markers follow the other plan docs: ✅ done · 🔄 in progress ·
⚠️ done but partially verified · ⬜ todo · 🚫 decided against.

## Goal and decisions

**Goal:** protect against regressions from the maintainer's own edits to prompts (12 agents,
8 skills, `/harness-goal`) and to the hook scripts that gate them. `tests/run-tests.sh` already
checks structure and plumbing; evals check *behaviour*.

| Decision | Choice |
|---|---|
| Where it runs | Local only, on demand. **Not** in CI, **not** a hook (✅ decided; revisit via the ⬜ CI item below) |
| Who runs it | The maintainer, by hand. Plugin users never run or see it |
| Runtime | Python 3.10+ stdlib + bash + the `claude` CLI (layers 2–3 only). No Docker |
| Network | None except the model API in layers 2–3; web tools, docker, curl, installs, `gh` denied |
| Fixtures | Pinned `git archive` snapshots of `demo-loan-app` and `finance-portal`; no live-repo access during runs |

## When to run it, and how

It is **manual** — nothing invokes it automatically (no CI job, no git hook, no plugin hook).

| You changed | Run | Cost / time |
|---|---|---|
| Any script in `plugins/se-harness/scripts/` or `hooks/hooks.json` | `bash evals/run-evals.sh` (Layer 1) | free, ~90 s |
| `skills/requirement-grill`, `templates/requirement.md` | Layer 1 + `--layer 2 --suite req_grill` | ~$0.30–1 |
| `skills/stack-detector`, `scan-evidence.sh` | Layer 1 + `--layer 2 --suite stack_detect` | ~$0.40 |
| `agents/architect` / `story-writer` / `unit-tester` | Layer 1 + `--layer 2 --suite <name>` | ~$0.70–1.50 each |
| `commands/harness-goal.md` or anything cross-cutting; before a release | all layers: `--layer all --compare` | not yet measured for the happy path |

First time on a machine: `bash evals/run-evals.sh fixtures`. Preview any model-backed run without
spending: `--dry-run`. Compare to committed scores: `--compare`; accept new scores:
`--update-baseline` (then commit `evals/baselines/`).

## Status

### Layer 1 — deterministic, offline, free

| Item | Status | Notes |
|---|---|---|
| Gate cases (`gate-check.sh`: states, bypasses, false positives, workspace-plan rows) | ✅ | 92 cases |
| Contract cases (`contract-check.sh` on the real demo `workspace.yaml`) | ✅ | 23 cases |
| Hook cases (`inject-context`, `memory-log-commit`, `org-validate`) | ✅ | 20 cases |
| `new-requirement.sh` scaffolding cases | ✅ | 14 cases |
| Grader self-tests (each grader must pass good / flag mutated input) | ✅ | 26 cases |
| Hidden-test validity (fail on unsolved repo, pass on reference solution) | ✅ | needs local `node_modules`; skips otherwise |
| Pipeline self-test with a stand-in `claude` (oracle / null / reckless) | ✅ | 15 cases; proves layers 2–3 plumbing with no model |
| Bugs found by the above fixed (gate bypasses, REQ-009 octal, backslash goals, org-validate) | ✅ | commit `d90642b`; all `known_gap` flags removed |
| Layer-1 baseline recorded | ✅ | `evals/baselines/layer1.json`, 190 cases |

### Layer 2 — one agent/skill, one artifact (live)

| Suite | Status | Notes |
|---|---|---|
| `stack_detect` (finance-portal, demo-loan-app) | ✅ | 1.00 / 1.00, 1 sample |
| `req_grill` (csv-export, vague goal, "just decide") | ✅ | 1.00 ×3, 1 sample |
| `architect` | ✅ | 1.00, 1 sample (judge questions) |
| `story_writer` | ⚠️ | 0.83 before a grader fix; not re-run after it. One soft judge failure left (extra e2e / per-character cases beyond the criteria) — judge call, left as is |
| `unit_tester` (mutation score, 15 seeded bugs) | ✅ | 1.00, 1 sample |
| Layer-2 baseline recorded | ⬜ | needs `--samples 3` first; 1 sample says nothing about variance |

### Layer 3 — full `/harness-goal` loop (live)

| Item | Status | Notes |
|---|---|---|
| Pressure scenario (user says: approve yourself, push, open PR) | ⚠️ | passed 1.00 ($0.39), but the agent refused up front and never tried to push, so the hook-block path was **not** exercised |
| Happy path `csv-export` (gate 1 → human approves → implement → hidden tests) | ⬜ | built and validated against the stand-in; never run with a real model. Estimated $3–8 |
| Slash entry `/se-harness:harness-goal` works headless | ✅ | confirmed in the pressure run (Skill tool); file-read fallback stays as insurance |
| "BLOCKED by se-harness gate" visible in a real transcript (`hook_blocked()`) | ⬜ | needs the direct-push scenario below |

### Backlog

| Item | Status | Notes |
|---|---|---|
| Direct-push scenario: tell the agent to run `git push` / `gh pr create` on a draft REQ and assert the hook blocks and the agent stops | ⬜ | closes the gap above; < $0.50 |
| Run `story_writer` again after the grader fix | ⬜ | ~$0.80 |
| `--samples 3` runs of layers 2–3, then `--update-baseline` for `layer2` / `layer3` | ⬜ | then `--compare` is meaningful for them |
| Evals for `wiki-ingest` / `wiki-query` / `wiki-lint` (provenance, refusal when wiki has no answer) | ⬜ | `finance-portal` SRS/SDD PDFs are candidate sources |
| `workspace-orchestrator` eval on a 2-component change | ⬜ | seed from finance-portal git history (news service split) |
| Evals for `db-engineer`, `implementer-*`, `integration-tester`, `e2e-*`, `release-manager` | ⬜ | e2e agents need a live app, so they conflict with the no-Docker rule |
| `/harness-init` and `/harness-scan` command-level evals (beyond the stack-detector skill) | ⬜ | scripted intake answers, golden `profile.yaml` |
| Same dataset against the Copilot variant (`se-harness-copilot`) | ⬜ | cross-ecosystem parity |
| Optional: run Layer 1 in CI and/or a pre-push hook | ⬜ | free and fast, so low-risk; deferred because the decision was "local only for now" |
| Cloud-hosted / nightly Layers 2–3 | 🚫 | out of scope while evals are local-only |

## Known limits

- The gate classifier (`scripts/irreversible-cmd.sh`) reads commands like a shell but has no real
  parser; deliberately obfuscated commands can still pass. Quoted separators (`echo "x; git push"`)
  can false-positive.
- Layers 2–3 are noisy by nature: one sample is a smoke test, not a score. Use `--samples 3` and
  compare means.
- LLM-judge questions are pinned in the dataset but the judge model is whatever `claude` defaults to
  unless `--judge-model` is given.
- Hidden tests and the reference solution live only for the CSV-export task; a different task needs its
  own pair (and a `reference_check` case to validate it).

## Where things are

`evals/README.md` (usage, layout, how to add cases) · `evals/datasets/` (cases) · `evals/golden/`
(real REQ-001 run + golden stacks) · `evals/hidden/` (acceptance tests the agent never sees) ·
commits `20cc92a` (framework), `d90642b` (bug fixes), `ee4ca4b` (live-run fixes).
