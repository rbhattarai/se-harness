---
name: harness-methodology-openspec
description: Install and initialize OpenSpec (Fission-AI/OpenSpec) for one repo or an entire se-harness workspace, gated on methodology:openspec actually being selected — setup only, /harness-goal drives the actual propose/archive lifecycle.
---


# /harness-methodology-openspec — OpenSpec setup

Get [OpenSpec](https://github.com/Fission-AI/OpenSpec) installed and initialized wherever
`methodology: openspec` was actually chosen. **Setup only** — it never runs `/opsx:propose`,
`/opsx:apply`, or `/opsx:archive` itself; `/harness-goal` steps 3 and 10 do that, as part of
driving an actual goal, not as a standalone action here.

## Step 1 — Scope

1. **Single repo** (`$ARGUMENTS` has a `repo_name`): process that one only. Validate against
   `workspace.yaml`'s `units:` or `repos.txt` and resolve its path beneath the workspace root.
2. **No repo given**: look for `workspace.yaml` or `repos.txt`. If found, ask whether to
   process every unit listed there, name one, or stop — don't infer consent from silence. If
   neither file exists, this is a single, non-workspace repo: process it alone.
3. Use the workspace root resolved from `workspace.yaml`/`repos.txt`, not wherever the plugin
   itself is installed.
4. Skip any unit whose directory doesn't exist and report it. Never clone anything.

## Step 2 — Confirm OpenSpec is actually the chosen methodology, then install it

Never install or initialize OpenSpec for a unit that didn't choose it:

1. Check `workspace.yaml`'s `shared.methodology` and the target unit's `.harness/profile.yaml`
   `methodology` field for `openspec`. An explicit different choice recorded in that unit's own
   `profile.yaml` (a documented deviation, per `/harness-init` Step 4) overrides an inherited
   workspace default — skip that unit unless the user explicitly selects OpenSpec for it in
   this invocation.
2. If OpenSpec wasn't selected anywhere relevant, ask before installing or initializing it for
   this invocation. If declined, stop.
3. If the `openspec` CLI already runs (`openspec --version`), reuse it — don't reinstall.
4. If it needs installing: check **Node 20+** first (`node --version`). Missing or below 20 →
   ask the user to install/upgrade it themselves and stop this run until they confirm it's
   ready. **Never install Node yourself.** Then:
   `npm install -g @fission-ai/openspec@latest` (confirm with the user first — third-party
   code). A Homebrew alternative (`brew install openspec`) exists on macOS/Linux if the user
   prefers it; ask which, don't assume.
5. Verify `openspec --version` before processing any unit.
6. For each unit:
   - **No `openspec/` directory yet**: run `openspec init` in that unit. This registers the
     `/opsx:*` slash commands for whichever client surface this session is running in — don't
     assume a fixed install path for those command files; `/harness-goal` discovers them by
     search when it actually needs one, not here.
   - **`openspec/` already exists**: run `openspec update` instead, to refresh the installed
     agent instructions/slash commands to the current OpenSpec version. Never re-run `init`
     over an existing setup — report what `update` changed, if anything.
7. Record a successful install in that unit's `.harness/agentstack.lock` (`components`): name
   `openspec`, source `Fission-AI/OpenSpec (npm: @fission-ai/openspec)`, installed version,
   install method, today's date, status `installed`. Never flip a prior `declined` status
   without the user's explicit choice in this invocation.

## Step 3 — Report

Per unit: already-installed vs newly-installed vs newly-updated, installed version, whether
`openspec init`/`update` reported any errors. Call out every skipped unit (didn't choose
OpenSpec, or declined) explicitly. Close with: OpenSpec is ready for `/harness-goal` to use on
the next goal for each unit listed as installed — nothing further to run here.
