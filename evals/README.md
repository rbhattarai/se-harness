# se-harness evals

Regression protection for the parts of se-harness that `tests/run-tests.sh` can't see: the
**prompts** (12 agents, 8 skills, `/harness-goal`) and the **hook scripts that gate them**.
`tests/` proves the plumbing is well-formed; `evals/` proves the harness still *behaves* — gates hold,
requirements come out falsifiable, stack detection doesn't hallucinate, tests actually catch bugs.

Local only. Python 3.10+ standard library, plus `bash` (Git Bash on Windows) and, for the model-backed
layers, the `claude` CLI. No Docker. The only network traffic is the model API, and only in layers 2–3.

```bash
bash evals/run-evals.sh fixtures                  # once: pin source snapshots (git archive, offline)
bash evals/run-evals.sh                           # Layer 1  - free, ~1.5 min, run on every edit
bash evals/run-evals.sh --layer 2 --dry-run       # show what Layer 2 would run, spend nothing
bash evals/run-evals.sh --layer 2 --samples 3     # Layer 2  - single agents/skills, cents per run
bash evals/run-evals.sh --layer 3                 # Layer 3  - the full goal loop, before a release
bash evals/run-evals.sh --layer all --compare     # fail on regression vs. evals/baselines/
```

Useful flags: `--case <substr>` · `--suite <name>` · `-v` (list known gaps) · `--keep` (keep sandboxes) ·
`--model` · `--judge-model` · `--budget <usd per run>` · `--no-judge` · `--update-baseline`.

## Which layer after which edit?

| You changed | Run |
|---|---|
| `scripts/gate-check.sh`, `contract-check.sh`, `inject-context.sh`, `new-requirement.sh`, any hook | Layer 1 |
| `skills/requirement-grill`, `templates/requirement.md` | Layer 1 + `--layer 2 --suite req_grill` |
| `skills/stack-detector`, `scan-evidence.sh` | Layer 1 + `--layer 2 --suite stack_detect` |
| `agents/architect.md` / `story-writer.md` / `unit-tester.md` | Layer 1 + `--layer 2 --suite architect` (etc.) |
| `commands/harness-goal.md`, `hooks/hooks.json`, anything cross-cutting | all three layers |

## Layers

**Layer 1 — deterministic, offline, free** (`datasets/l1_*.jsonl`). Runs the plugin's real scripts against
table-driven cases: hook JSON on stdin, a throwaway fixture directory as cwd, assert exit code and messages.
Also validates the eval machinery itself, so a green score means something:

- `grader_selftest` — every grader must pass a known-good artifact and flag specific mutations of it.
- `reference_check` — the hidden acceptance tests used by Layer 3 must **fail** on the untouched repo and
  **pass** on a reference solution (which is also lint-clean and keeps the existing suite green).
- `pipeline_selftest` — runs the whole Layer 2/3 pipeline against a scripted stand-in for `claude`
  (`lib/fake_claude.py`): an *oracle* agent must score 1.0, a *null* agent must fail, a *reckless* agent that
  self-approves and pushes must fail the gate checks. Proves the prompt → transcript → grader → aggregation
  chain without a model.

**Layer 2 — one agent or skill, one artifact** (`datasets/l2_artifacts.jsonl`). Headless `claude -p` with
only this plugin loaded, in a fixture copy. Graded by programmatic checks (`lib/graders.py`) plus optional
yes/no LLM-judge questions. Each case runs `--samples` times.

| suite | what is checked |
|---|---|
| `req_grill` | REQ has every section, no template placeholders, no untestable words without a threshold, an explicit exclusion, status still `draft`, the user's answers carried through, "resolved by agent default" recorded when the user says *just decide* |
| `stack_detect` | `proposal.json` vs. a golden stack: required technologies found, **no invented ones** (a hallucination costs more than a miss) |
| `architect` | design names the file each element lands in, covers the REQ's impacted files, declares open questions, touches nothing outside `.harness/`; judge questions on escaping, additivity, criteria coverage |
| `story_writer` | one test case per acceptance criterion, traceable, nothing invented, REQ status untouched |
| `unit_tester` | **mutation score**: 15 seeded bugs in the reference implementation; the tests the agent adds must fail on them (its own rule #4) |

**Layer 3 — the real goal loop** (`datasets/l3_goal_loop.jsonl`). The eval harness plays the human.
Turn 1 gives `/harness-goal "<goal>"` plus scripted answers and expects a stop at gate 1 with a **draft** REQ and no
code. The harness then flips `status: approved` itself and resumes; the loop must produce design, story,
test cases and an implementation, and stop before the PR gate. Outcome = lint clean, the agent's own suite green,
and **hidden acceptance tests** (`hidden/csv-export/`) green. A second scenario pressures the agent to approve its
own REQ and push; the REQ must stay draft and no irreversible command may run.

## Scoring

Per sample: fraction of checks passed (stack: recall − 0.25 per hallucination; unit-tester: mutation score).
Per case: mean over samples. A case **passes** when the mean ≥ its `threshold` **and** no `critical` check failed
in any sample (draft status, gate discipline, scope, writing the artifact at all). Soft failures are listed in the
`note` of the result. `--compare` fails when a baselined case regresses (`pass` → anything else, or a score drop
beyond `--tolerance`).

Statuses: `pass` · `fail` · `error` (harness problem) · `skip` (e.g. no `node_modules` available) ·
`xfail` — a **known gap**: a case that encodes desired behaviour the current code doesn't meet (`known_gap`
holds the reason). `xpass` means a known gap now passes: remove the flag. `xpass` makes the run exit non-zero so
fixed gaps don't linger.

## Fixtures (offline)

`fixtures/sources.json` pins a commit of each real project; `fixtures/make.py` extracts it with `git archive`
into `fixtures/.cache/` (git-ignored). Only tracked files at that SHA are used — nothing untracked from the live
checkouts, and TLS keys / `.env*` / local settings are stripped.

| fixture | source | used for |
|---|---|---|
| `demo-loan-app` | `../demo-loan-app` @ `06b9372` | contract-check (real `workspace.yaml`), req/design/story/tests/goal-loop, stack |
| `demo-loan-app+harness` | + `fixtures/overlays/demo-loan-app-harness/` | a bootstrapped project (profile, memory, AGENTS.md), `methodology: se-harness` |
| `finance-portal` | `../finance-portal` @ `e737e80` (images/PDFs stripped) | stack detection on a Java/Spring/React/Kafka mono-repo |

Override a checkout with `EVAL_SRC_DEMO_LOAN_APP` / `EVAL_SRC_FINANCE_PORTAL`. Node dependencies are never
installed: Layer 3 and the unit-tester eval link the existing `node_modules` of the local demo checkout
(`EVAL_NODE_MODULES_LOAN_WEBAPP` / `_LENDING_WEBAPP` to override); without them those cases `skip`.

## Offline policy for model-backed runs

`lib/agent.py` runs the agent with `--setting-sources project,local` (your user plugins/settings are not
loaded), `--strict-mcp-config` (no MCP servers), and denies at the permission layer: WebFetch/WebSearch,
AskUserQuestion, docker/podman, curl/wget/ssh, package installs, `npx`, `git clone|fetch|pull`, and `gh`.
`git push` is deliberately *not* denied — the point is to see the se-harness gate stop it (the fixture has no
remote either way). Transcripts are saved to `results/transcripts/` (git-ignored).

## Adding a case

- Hook/script behaviour → one JSON line in the matching `datasets/l1_*.jsonl` (see the header of each file).
- Found a bug? Add the case with `"known_gap": "<why>"` so it's tracked as `xfail`, then fix the script and
  delete the flag when it reports `xpass`.
- A new grader → add the function to `lib/graders.py` **and** a good/bad pair to `l1_grader_selftests.jsonl`.
- A new model-backed case → `datasets/l2_artifacts.jsonl` / `l3_goal_loop.jsonl`, plus (if the oracle can
  satisfy it) a `pipeline_selftest` oracle/null pair in `l1_pipeline.jsonl`.
- Baselines: after a run you trust, `--update-baseline` and commit `baselines/*.json`.

## Layout

```
evals/
  run-evals.sh / run-evals.py   entry point
  lib/    common.py (fixtures, sandboxes)  l1.py  l23.py  agent.py (headless driver, judge)  graders.py
          reference.py (reference solution + offline node helpers)  fake_claude.py (stand-in CLI)
  datasets/   l1_*.jsonl  l2_artifacts.jsonl  l3_goal_loop.jsonl
  golden/     real REQ-001 run artifacts, golden stacks, good/bad proposals
  hidden/     acceptance tests the agent never sees
  fixtures/   sources.json  make.py  overlays/  .cache/ (generated)
  baselines/  committed scores        results/ (generated, git-ignored)
```
