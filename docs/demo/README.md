# Demos

Two demos live here:

- **Part 1 — the README GIF**: a 45–60s single-project recording for the top of the root
  README.
- **Part 2 — multi-unit walkthrough**: harness a two-app product (the bundled
  [`apps/loan-webapp`](../../apps/loan-webapp) + [`apps/lending-webapp`](../../apps/lending-webapp)
  sharing a JSON store) with a workspace manifest and contract checking. Use it live, or
  record it as a second GIF.

---

# Part 1 — Recording the README demo GIF

Target: **`docs/assets/demo.gif`** — 45–60 seconds, ≤ 10 MB, terminal only.
Once it exists, uncomment the image block near the top of the root `README.md`.

## Storyboard (what to show, in order)

Rehearse once first. Record in a real project that has the plugin installed —
`apps/loan-webapp` works well (reset its state between takes, see Part 2 § Demo hygiene).

1. **Init (~15s):** run `/harness-init` in an existing repo. Let the scan-confirmation
   moment be visible — the harness *detecting* the stack and asking you to confirm is the
   differentiator. Cut the rest of the interview.
2. **The generated artifacts (~5s):** `ls .harness/` and the top of `AGENTS.md` showing
   the `SEAA:GENERATED` markers.
3. **Goal (~20s):** `/harness-goal "Add CSV export to the reports page"` — show the grill
   question(s) and the written `.harness/requirements/REQ-001.md`.
4. **The money shot (~10s):** the gate hook **blocking** the PR/push with its message,
   then flipping `status: approved` in the REQ file, then the action going through.
   This is the frame people share — don't cut it short.

## Recording tips

- Terminal ~100×30, font 16–18 pt, a dark theme with good contrast (the GIF is shown
  small in the README — text must be readable at half size).
- Clean prompt (no long paths), `clear` between scenes.
- Trim dead time: long agent thinking pauses should be cut or sped up in the editor.

## Option A — ScreenToGif (easiest on Windows)

1. Install: `winget install NickeManarin.ScreenToGif`
2. Open ScreenToGif → **Recorder**, frame it around your Windows Terminal window.
3. Record the storyboard, then in the editor: delete dead frames, add 2× speed to slow
   sections, **Save as → GIF** (encoder: FFmpeg if offered; ~15 fps is plenty).
4. Save to `docs/assets/demo.gif`.

## Option B — vhs (scripted, reproducible)

[vhs](https://github.com/charmbracelet/vhs) replays a `.tape` script and renders a GIF —
same output every time, easy to re-record after UI changes.

```powershell
winget install charmbracelet.vhs   # or: scoop install vhs (installs ttyd + ffmpeg deps)
vhs docs/demo/demo.tape
```

`docs/demo/demo.tape` in this folder types the storyboard commands into a live Claude Code
session. Interactive agent output varies run to run, so adjust the `Sleep` durations to
your machine's pacing, or use vhs only for scenes 1–2 and ScreenToGif for the gate scene.

## Option C — asciinema (WSL) + agg

```bash
# inside WSL
sudo apt install asciinema && cargo install --git https://github.com/asciinema/agg
asciinema rec demo.cast          # record, Ctrl-D to stop
agg --font-size 18 demo.cast demo.gif
```

Bonus: also upload the `.cast` to asciinema.org — embeddable in blog posts and crisp at
any size.

## Size check before committing

```powershell
Get-Item docs/assets/demo.gif | Select-Object Length   # aim for < 10 MB
```

If it's too big: fewer fps (10–12), smaller terminal, shorter scenes — in that order.

---

# Part 2 — Multi-unit walkthrough: the loan product

The repo bundles a realistic two-app product under [`apps/`](../../apps):

| Unit | URL | Role |
|---|---|---|
| [`loan-webapp`](../../apps/loan-webapp) | `https://localhost:3000` | Borrower side — request a loan (`status: New`), dashboard |
| [`lending-webapp`](../../apps/lending-webapp) | `https://localhost:3001` | Lender side — add lenders, assign approver (`New → Pending`), approve/reject |

They share `apps/data/*.json` (a compose volume) and sync in real time via a
`POST /notify` webhook + SSE. That shared surface is exactly what the harness's contract
registry is for — so the demo shows **init per unit + workspace-level contract checking**.

**How `apps/data/` is modeled:** it's a data store, not a code unit, so it is *not* a
third unit in the manifest. Instead its record shapes and the webhook protocol are
declared as **contracts** ([`apps/contracts/loan-record.md`](../../apps/contracts/loan-record.md),
[`apps/contracts/notify-webhook.md`](../../apps/contracts/notify-webhook.md)) registered in
[`apps/workspace.yaml`](../../apps/workspace.yaml) with providers and consumers. Change a
contract → `contract-check.sh` names every consumer unit before you can push.

## Step 0 — prerequisites

```bash
cd apps
docker compose up --build      # loan-webapp :3000, lending-webapp :3001
```

Everything below assumes the se-harness plugin is installed (root README § Install).

## Step 1 — the workspace manifest

Already provided: [`apps/workspace.yaml`](../../apps/workspace.yaml) — two units
(`path:` form, since they sit side by side in one repo), the shared block, `run.compose`
pointing at `apps/docker-compose.yml` (used by the goal loop's compose-verify step), and
the two contracts. For a true multi-repo product you'd use `repo:` per unit in a small
meta-repo instead; everything else is identical.

## Step 2 — init each unit

```bash
cd apps/loan-webapp
claude
> /harness-init
```

Because the repo exists, `/harness-scan` runs first: the evidence collector detects
Node + TypeScript + Express 5 + EJS + Docker and shows you the findings to **confirm**
(low-confidence detections become questions, never silent guesses). You're interviewed
only for what can't be detected — methodology, environments, org context. Result per
unit: `AGENTS.md` + `CLAUDE.md` (generated blocks), `.harness/` (profile, memory seeds),
gitignored `.env.harness`.

Repeat in `apps/lending-webapp`. The manifest is auto-discovered (the hook looks for
`../workspace.yaml` relative to the unit), linking both profiles to the workspace.

Optionally follow with `/harness-bootstrap` in each unit for recommended companion
tooling (opt-in, recorded in the lockfile).

## Step 3 — see the contract gate fire

Make a breaking change to the shared loan shape — e.g. edit
`apps/contracts/loan-record.md` to add a required `rejectionReason` field — then:

```bash
bash plugins/se-harness/scripts/contract-check.sh --
```

Exit 2, stderr names the blast radius:

```
se-harness contract-check: contract 'loan-record' (apps/contracts/loan-record.md) changed.
  provider:  loan-webapp
  consumers: lending-webapp
  → verify each consumer still matches, and link consumer tasks to this REQ.
```

The same check runs automatically as a PreToolUse hook on `git push` / `gh pr create` —
inside a Claude session the push is blocked, not just warned.

## Step 4 — a cross-unit goal, end to end

The flagship demo goal (it genuinely spans both units + the contract):

```
cd apps/lending-webapp
claude
> /harness-goal "When a lender rejects a loan, they must give a rejection reason,
  and the borrower must see it on the loan-webapp dashboard"
```

What to watch for:

1. **Grill:** the requirement skill interrogates the ambiguity (free text or picklist?
   shown where exactly? required on reject only?) and writes
   `.harness/requirements/REQ-001.md` — ⛔ **gate 1** blocks until you flip
   `status: approved`.
2. **Contract impact:** the change adds `rejectionReason` to the loan record →
   contract-check flags `loan-webapp` as an impacted consumer; the loop links a consumer
   task to the same REQ.
3. **Implementation fan-out** in isolated worktrees, then unit/integration/e2e tests.
4. ⛔ **Gate 2** — PR with evidence; compose-verify runs against
   `apps/docker-compose.yml` (both apps up, SSE sync observable in two browser tabs).
5. ⛔ **Gate 3** — deploy approval.

Good smaller goals if you want a shorter take: "Add an amount-range filter to the lender
dashboard" (single unit), "Show a live-updated count of pending loans on both dashboards"
(webhook contract touched).

## Demo hygiene (repeatable takes)

The running apps mutate `apps/data/*.json`, and the goal loop writes `.harness/` state.
Between takes:

```bash
git checkout -- apps/data                              # reset seed data
git clean -fd apps/loan-webapp/.harness apps/lending-webapp/.harness  # if committed state isn't wanted
docker compose -f apps/docker-compose.yml restart
```

## GIF storyboard for Part 2 (optional second GIF)

`docs/assets/demo-multirepo.gif` — same tooling as Part 1, ~60s:

1. Split screen: both dashboards in a browser, add a loan on :3000, watch it appear live
   on :3001 (~8s — establishes the product).
2. `/harness-init` scan-confirm moment in `loan-webapp` (~15s).
3. `cat apps/workspace.yaml` — units + contracts (~5s).
4. Edit the contract file, `git push` inside the session → **contract-check block naming
   lending-webapp** (~12s). This is Part 2's money shot.
5. `/harness-goal` grill → REQ gate block → approve (~20s).
