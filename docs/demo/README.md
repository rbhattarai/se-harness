# Demos

Two demos live here:

- **Part 1 — the README GIF**: a 45–60s single-project recording for the top of the root
  README.
- **Part 2 — multi-unit walkthrough**: harness a two-app product — the companion
  [**demo-loan-app**](https://github.com/rbhattarai/demo-loan-app) repo (`loan-webapp` +
  `lending-webapp` sharing a JSON store) — with a workspace manifest and contract
  checking. Use it live, or record it as a second GIF.

---

# Part 1 — Recording the README demo GIF

Target: **`docs/assets/demo.gif`** — 45–60 seconds, ≤ 10 MB, terminal only.
Once it exists, uncomment the image block near the top of the root `README.md`.

## Storyboard (what to show, in order)

Rehearse once first. Record in a real project that has the plugin installed —
`loan-webapp` inside a clone of [demo-loan-app](https://github.com/rbhattarai/demo-loan-app)
works well (reset its state between takes, see Part 2 § Demo hygiene).

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

The companion repo [**demo-loan-app**](https://github.com/rbhattarai/demo-loan-app) is a
realistic two-app product:

| Unit | URL | Role |
|---|---|---|
| [`loan-webapp`](https://github.com/rbhattarai/demo-loan-app/tree/main/loan-webapp) | `https://localhost:3000` | Borrower side — request a loan (`status: New`), dashboard |
| [`lending-webapp`](https://github.com/rbhattarai/demo-loan-app/tree/main/lending-webapp) | `https://localhost:3001` | Lender side — add lenders, assign approver (`New → Pending`), approve/reject |

They share `data/*.json` (a compose volume) and sync in real time via a `POST /notify`
webhook + SSE. That shared surface is exactly what the harness's contract registry is
for — so the demo shows **init per unit + workspace-level contract checking**.

**How `data/` is modeled:** it's a data store, not a code unit, so it is *not* a third
unit in the manifest. Instead its record shapes and the webhook protocol are declared as
**contracts** ([`contracts/loan-record.md`](https://github.com/rbhattarai/demo-loan-app/blob/main/contracts/loan-record.md),
[`contracts/notify-webhook.md`](https://github.com/rbhattarai/demo-loan-app/blob/main/contracts/notify-webhook.md))
registered in [`workspace.yaml`](https://github.com/rbhattarai/demo-loan-app/blob/main/workspace.yaml)
with providers and consumers. Change a contract → `contract-check.sh` names every
consumer unit before you can push.

## Step 0 — prerequisites

```bash
git clone https://github.com/rbhattarai/demo-loan-app
cd demo-loan-app
docker compose up --build      # loan-webapp :3000, lending-webapp :3001
```

Everything below assumes the se-harness plugin is installed (root README § Install).

## Step 1 — the workspace manifest

Already provided at the demo repo's root: `workspace.yaml` — two units (`path:` form,
since they sit side by side in one repo), the shared block, `run.compose` pointing at
`docker-compose.yml` (used by the goal loop's compose-verify step), and the two
contracts. For a true multi-repo product you'd use `repo:` per unit in a small meta-repo
instead; everything else is identical.

## Step 2 — init each unit

```bash
cd loan-webapp
claude
> /harness-init
```

Because the repo exists, `/harness-scan` runs first: the evidence collector detects
Node + TypeScript + Express 5 + EJS + Docker and shows you the findings to **confirm**
(low-confidence detections become questions, never silent guesses). You're interviewed
only for what can't be detected — methodology, environments, org context. Result per
unit: `AGENTS.md` + `CLAUDE.md` (generated blocks), `.harness/` (profile, memory seeds),
gitignored `.env.harness`.

Repeat in `lending-webapp`. The manifest is auto-discovered (the hook looks for
`../workspace.yaml` relative to the unit — the demo repo's root), linking both profiles
to the workspace.

Optionally follow with `/harness-bootstrap` in each unit for recommended companion
tooling (opt-in, recorded in the lockfile).

## Step 3 — see the contract gate fire

Make a breaking change to the shared loan shape — e.g. edit `contracts/loan-record.md`
to add a required `rejectionReason` field. Inside a Claude session the PreToolUse hook
then blocks `git push` / `gh pr create` automatically. To run the same check standalone,
point at the script in your se-harness clone (or installed plugin) from the demo repo
root:

```bash
bash /path/to/se-harness/plugins/se-harness/scripts/contract-check.sh --
```

Exit 2, stderr names the blast radius:

```
se-harness contract-check: contract 'loan-record' (contracts/loan-record.md) changed.
  provider:  loan-webapp
  consumers: lending-webapp
  → verify each consumer still matches, and link consumer tasks to this REQ.
```

## Step 4 — a cross-unit goal, end to end

The flagship demo goal (it genuinely spans both units + the contract):

```
cd lending-webapp
claude
> /harness-goal "When a lender rejects a loan, they must give a rejection reason,
  and the borrower must see it on the loan-webapp dashboard"
```

What to watch for:

1. **Grill + impact map:** the requirement skill interrogates the ambiguity (free text or
   picklist? shown where exactly? required on reject only?) while the deep-dive step builds
   an impact map from `workspace.yaml` — this goal touches both units, so the count is 2.
2. **Workspace plan, same gate.** Because the impact spans 2+ units, `/harness-goal` also
   renders `.harness/requirements/REQ-001/workspace-plan.md` (one row per unit) **alongside**
   `REQ-001.md`, not a second gate — ⛔ **gate 1** blocks until you flip `status: approved`,
   which approves both at once.
3. **Contract impact:** the change adds `rejectionReason` to the loan record →
   contract-check flags `loan-webapp` as an impacted consumer; the loop links a consumer
   task to the same REQ.
4. **workspace-orchestrator works the plan**, not manual fan-out: it implements the
   `lending-webapp` row directly, then `cd`s into `loan-webapp` (trivial here — both units
   are already checked out side by side in the one clone) for that row, isolated worktrees
   and unit/integration/e2e tests either way.
5. **Integration check before anything is "done."** Once both rows are implemented, it brings
   up `docker-compose.yml` from the combined current state and re-checks contracts — passing
   each unit's own tests isn't the same as the SSE sync actually working end to end. Only
   then does `workspace-plan.md` get `integration: passed`.
6. ⛔ **Gate 2** — PR with evidence, including each row's status and the integration result;
   `gate-check.sh` would block the PR itself otherwise. Compose-verify re-runs against
   `docker-compose.yml` (both apps up, SSE sync observable in two browser tabs).
7. ⛔ **Gate 3** — deploy approval.

Good smaller goals if you want a shorter take: "Add an amount-range filter to the lender
dashboard" (single unit), "Show a live-updated count of pending loans on both dashboards"
(webhook contract touched).

## Demo hygiene (repeatable takes)

The running apps mutate `data/*.json`, and the goal loop writes `.harness/` state.
Between takes, from the demo repo root:

```bash
git checkout -- data                                        # reset seed data
git clean -fd loan-webapp/.harness lending-webapp/.harness  # if committed state isn't wanted
docker compose restart
```

## GIF storyboard for Part 2 (optional second GIF)

`docs/assets/demo-multirepo.gif` — same tooling as Part 1, ~60s:

1. Split screen: both dashboards in a browser, add a loan on :3000, watch it appear live
   on :3001 (~8s — establishes the product).
2. `/harness-init` scan-confirm moment in `loan-webapp` (~15s).
3. `cat workspace.yaml` — units + contracts (~5s).
4. Edit the contract file, `git push` inside the session → **contract-check block naming
   lending-webapp** (~12s). This is Part 2's money shot.
5. `/harness-goal` grill → REQ gate block → approve (~20s).
