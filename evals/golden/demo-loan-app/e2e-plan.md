---
req: REQ-001
step: 6.1-e2e-planner
status: draft
target_branch: REQ-001/integration
target_worktree: c:\Users\bhatt\OneDrive\Documents\develop\demo-loan-app\.worktrees\REQ-001-integration
tracker_keys: []   # no XRay/Zephyr in this repo — TC-1..TC-8 are the local test-case IDs
---

# E2E plan: CSV export for the Loan Management and Loan Approvers grids

## 0. What's already covered, and by what (read before writing any spec)

66 unit/integration tests already exist on `REQ-001/integration`, in three layers per app.
This plan exists to cover the **fourth layer** — real browser + real running HTTPS server —
which none of the following three layers exercise:

| Layer | File(s) | What it proves | TCs covered |
|---|---|---|---|
| 1. Mocked-store route unit tests | `loan-webapp/test/loanRoute.test.ts`, `lending-webapp/test/lendorRoute.test.ts` | Status/headers/body shape, RFC 4180 escaping, empty-store 200, HTML string contains the `Export CSV` link+href (TC-7's markup half) | TC-1, TC-2, TC-3, TC-4, TC-5, TC-6, TC-7 (HTML-string half), TC-8 |
| 2. Real-filesystem integration tests | `loan-webapp/test/exportIntegration.test.ts`, `lending-webapp/test/exportIntegration.test.ts` | The route's real `readLoans()`/`readApprovers()` path against the real, git-tracked `data/*.json` in **this worktree**, restored in `afterAll` | TC-1/2/5/6 content, against real disk I/O |
| 3. This plan (browser/e2e) | new Playwright specs (next step) | A real Chromium instance rendering the EJS page over real HTTPS/mTLS, a real click, a real OS-level download event, and the *downloaded file's* bytes | TC-7 (rendered-DOM half only), plus new browser-only assertions not owned by any TC below |

**Consequence for scope:** TC-1 through TC-6 and TC-8 are fully satisfied by Supertest already —
they are **not** re-implemented as browser specs. Re-asserting exact header/status/Content-Type
strings in a browser adds no coverage Supertest hasn't already given more cheaply and more
precisely (Supertest can assert byte-exact bodies; a browser download adds OS/filesystem/timing
noise for the same assertion). The one thing only a browser can prove — and the one thing this
REQ's acceptance criteria are silent on but the task brief explicitly calls for — is:

- The link is real, visible, styled, and clickable in a rendered page (not just present in an
  HTML string).
- Clicking it triggers a **download**, not a navigation (this only exists as a concept in a
  browser; Supertest has no notion of "the browser decided not to navigate because of
  `Content-Disposition: attachment`").
- The bytes that land on disk via that real download are a well-formed CSV whose header row
  matches what the unit tests already pinned, corroborating that nothing in the real
  request/response pipe (proxying, compression, EJS rendering, static-asset interference) breaks
  it end-to-end.

TC-7 is therefore **split** across layers 1 and 3, per the task brief's framing — not duplicated.
Layers 1/2 are sent back as "already done, no action needed"; only the browser half is planned
below.

## 1. Environment prerequisites (for the e2e-generator, not executed here)

- Both apps must be started from **this worktree**
  (`.worktrees\REQ-001-integration\loan-webapp`, `...\lending-webapp`), not `main` — `npm run dev`
  (ts-node/nodemon) or `npm run build && npm start`, per each app's README. Ports are fixed:
  `https://localhost:3000` (loan-webapp), `https://localhost:3001` (lending-webapp).
- Both apps serve **self-signed HTTPS with mTLS requested-but-not-enforced**
  (`rejectUnauthorized: false`). Playwright's browser context must set
  `ignoreHTTPSErrors: true` (both for `test.use()` and for the persistent context, if any) or
  every navigation fails at the cert-warning interstitial before any DOM exists — this is a
  hard requirement, not a flake mitigation.
- **Do not run this e2e suite concurrently with either app's `npm test`** in the same worktree.
  `exportIntegration.test.ts` in both apps overwrites the real, git-tracked
  `data/loans.json` / `data/loan-approvers.json` mid-run and restores them in `afterAll` — a
  concurrent e2e run reading/writing the same physical files during that window will race.
  Sequence: unit/integration tests first, then start the servers for e2e, or vice versa, never
  interleaved.
- No login/auth flow exists in either app (mTLS is transport-level and not enforced) — no
  credential/session setup needed before reaching `/loan` or `/lendor`.

## 2. Data-seeding & teardown strategy (explicit, per task brief)

**Chosen approach: read-only reliance on the worktree's checked-in demo rows, with a
defensive create-then-delete fallback only if the grid is unexpectedly empty at test time.**

Investigated and confirmed directly (not assumed):
- `data/loans.json` and `data/loan-approvers.json` are **not** in `.gitignore` (only
  `.worktrees/` itself is ignored, which hides the worktree directory from the *root* repo's
  status — it does not affect the worktree's own independent git checkout of its tracked files).
- In this worktree, `data/loans.json` currently holds **4** loan records and
  `data/loan-approvers.json` holds **1** approver record — real, non-empty, already checked into
  the `REQ-001/integration` branch.
- `exportIntegration.test.ts` (both apps) independently documents and relies on this same fact
  ("`data/loans.json` is git-tracked with real demo content... safe to overwrite here
  temporarily... original content is captured in `beforeAll` and restored in `afterAll`"),
  confirming this is the established, accepted pattern in this repo for treating the worktree's
  data files as a mutable-but-restorable fixture.

**Primary path (expected to be used every run):** do not create any data. Navigate to `/loan`
and `/lendor` and rely on the existing rows to render a populated grid (satisfying the task
brief's "grid actually populated, not empty" requirement) purely by reading, never writing.
This is the least invasive option available and requires no cleanup.

**Fallback path (defensive only, expected to be a no-op in normal runs):** if a spec's setup
step observes the grid rendering its "No loans found" / "No approvers yet" empty state (e.g.
because a prior, unrelated test run — including this app's own delete-flow tests, if any exist
elsewhere in the suite — emptied the store), create exactly one throwaway record through the
existing UI form before proceeding:
- loan-webapp: open the "New Loan" modal, submit `applicantName = "E2E-CSV-SeedRow"`,
  `amount = 1`.
- lending-webapp: open the "Add New Loan Approver" modal, submit
  `approverName = "E2E-CSV-SeedApprover"`.

Both values are prefixed `E2E-CSV-` specifically so they're unambiguous in the CSV output and
easy to identify for teardown. If this fallback path is used, **teardown (in the same spec's
cleanup, not a separate pass) must click that row's existing trash/delete button** (the grid
already has a delete form per row — `POST /loan/:id/delete` / `POST /lendor/:id/delete`) to
remove the created record, so no test-created data is left behind permanently in the
git-tracked file.

**Why this is acceptable for this demo repo, explicitly stated per the task brief:** these are
flat JSON files in a worktree, not a shared/production database — the worktree is disposable
scaffolding for this REQ's pipeline run, and `exportIntegration.test.ts` already establishes
that temporarily mutating and restoring this exact file is the repo's accepted convention.
Regardless, the plan above never leaves a *permanent* diff: the primary path never writes, and
the fallback path always deletes what it creates before the spec ends.

## 3. Selector strategy

No `data-testid` convention exists anywhere in either app's views (confirmed by reading both
`loan.ejs` and `lendor.ejs` in full) and `.harness/profile.yaml` records no org-level selector
convention either. Recommend the generator use Playwright's role/text-based locators rather than
CSS classes (Bootstrap classes are styling, not identity, and are shared across many buttons):

| Target | Recommended locator | Why it's stable |
|---|---|---|
| Export link, loan-webapp | `page.getByRole('link', { name: 'Export CSV' })` scoped within the toolbar `div.d-flex.justify-content-between` if disambiguation is ever needed | Accessible name is unique on the page; it's a real `<a>` so `role=link` is correct (not `role=button`, despite the `btn` CSS class) |
| Export link, lending-webapp | same pattern, same accessible name `Export CSV` | Text is identical to loan-webapp by design (per REQ) — fine since specs target one app's page at a time |
| Loans table rows | `#loansGrid tbody tr` (existing stable `id="loansGrid"` already on the `<table>`) | Already a stable, unique DOM id — no prep task needed |
| Approvers table rows | `#approversGrid tbody tr` (existing stable `id="approversGrid"`) | Same |
| "New Loan" / "Add New Loan Approver" primary buttons (for adjacency + fallback seeding) | `page.getByRole('button', { name: 'New Loan' })` / `page.getByRole('button', { name: 'Add New Loan Approver' })` | Accessible names already unique |
| Modal form fields (fallback seeding only) | `#applicantName`, `#amount`, `#approverName` (existing stable `id` attributes on the inputs) | Already stable — no prep task needed |
| Delete button for a given row (fallback teardown only) | `page.locator('#loansGrid tbody tr', { hasText: 'E2E-CSV-SeedRow' }).getByRole('button', { name: 'Delete loan' })` (accessible name comes from the button's `title` attribute) / equivalent `'Delete approver'` for lendor | `title` attributes already present on both delete buttons, giving them an accessible name distinct from every other button on the page |

**No selector prep tasks needed** — every element this plan touches already has either a unique
accessible name or a stable `id`/`title` attribute in the current markup. Nothing needs to be
added to `loan.ejs`/`lendor.ejs` for these specs to be written reliably.

## 4. Flake-risk register

| Risk | Mitigation |
|---|---|
| Self-signed cert / mTLS interstitial blocks navigation | `ignoreHTTPSErrors: true` on the browser context (see §1) — not really "flake," a hard prerequisite |
| Third-party CDN assets (`cdn.jsdelivr.net` Bootstrap CSS/JS, Bootstrap Icons) slow or unavailable in a restricted network | Don't wait on `networkidle`; wait on the specific locator (`getByRole('link', { name: 'Export CSV' })`) becoming visible/attached instead. Don't assert on the `bi-download` icon glyph rendering — assert only on the accessible name and `href`, which don't depend on the icon font loading |
| Bootstrap modal fade transition (used only by the fallback-seeding path, not the primary path) | Not exercised by the primary (no-seed) path at all. If the fallback path is used, wait for the modal's `shown.bs.modal` state via Playwright's built-in actionability (auto-waiting on the input becoming visible/enabled) rather than a fixed `waitForTimeout` |
| SSE-driven full-page reload (`loan.ejs` only — `EventSource` on `/events` triggers `window.location.reload()` on a `loan-updated` event) racing with the download click | Confirmed no self-notify path exists for the actions this plan takes: creating a loan notifies *lending-webapp*, not loan-webapp itself; creating an approver doesn't call `notifyApp` at all (per `lendor.ts`). So the plan's own fallback-seeding actions cannot trigger a reload of the page under test. Residual risk is only from a concurrent, unrelated human/agent session mutating the shared data store during the test window — avoid running this suite while another session is interacting with the same worktree's running servers |
| Concurrent physical-file writes vs. `exportIntegration.test.ts` | See §1 — don't run `npm test` and this e2e suite against the same worktree simultaneously |
| Filename date computed from the *server's* `new Date()` at request time (real clock, not mockable in e2e) | Assert the filename against a **regex** (`/^loans-\d{4}-\d{2}-\d{2}\.csv$/`, `/^loan-approvers-\d{4}-\d{2}-\d{2}\.csv$/`), never a literal hard-coded date. Do not attempt to compute "today" client-side and compare for exact equality — a run straddling a UTC-midnight boundary between the client-side "now" and the server's request-time "now" would flake on an exact-match assertion |
| Playwright download handling defaults | Ensure the browser context is created with downloads enabled (Playwright's default `acceptDownloads: true`); use `page.waitForEvent('download')` initiated *before* the click (`Promise.all([page.waitForEvent('download'), link.click()])`) rather than clicking first, to avoid a race on fast/local servers |

## 5. E2E scenarios

### E2E-1 (P0): loan-webapp `/loan` — Export CSV link triggers a real download of a well-formed, populated CSV

**Consolidates:** TC-7 (rendered-DOM half only) + new browser-only download/content assertions.
Not owned by any single TC in isolation — this is the cross-cutting "does the whole real thing
work" scenario the task brief asked for.

**Entry state:** Fresh browser context, navigate to `https://localhost:3000/loan`. Per §2,
primary path: rely on the worktree's checked-in demo rows (4 loans) to render a populated grid,
read-only, no setup writes. Fallback path (only if grid renders empty): seed one loan via the
UI form, tagged `E2E-CSV-SeedRow` (see §2), and this spec becomes responsible for its own
teardown before finishing.

**Test data:** None created in the expected/primary run. If fallback triggers: one loan record
(`applicantName: "E2E-CSV-SeedRow"`, `amount: 1`), deleted via its row's trash button at the end
of the spec regardless of pass/fail (`finally`/`test.afterEach` semantics, generator's choice of
Playwright idiom).

**Steps:**
1. Navigate to `/loan`. Assert the grid table (`#loansGrid`) is visible with at least one row
   (proves the "populated, not empty" precondition the task brief called for — and, incidentally,
   independently corroborates the primary-action-button rendering that TC-7's unit test already
   checks via raw HTML, but here via actual rendered layout).
2. Assert an element with role `link` and accessible name `Export CSV` is visible, and its
   resolved `href` attribute equals `/loan/export.csv`. Assert it sits inside the same toolbar
   grouping as the `New Loan` button (adjacency — the rendered-DOM half of TC-7's acceptance
   criterion "next to its existing primary action button").
3. Start waiting for a `download` event, then click the `Export CSV` link (`Promise.all` per
   §4's mitigation note).
4. Assert the click did **not** navigate the page away from `/loan` (`page.url()` still ends in
   `/loan` after the click settles) — this is the specific browser-only behavior the task brief
   called out: a real `<a href>` GET to a `Content-Disposition: attachment` response is handled
   by the browser as a download, not a navigation, and only a real browser can demonstrate that
   distinction.
5. On the resolved `Download` object: assert `suggestedFilename()` matches
   `/^loans-\d{4}-\d{2}-\d{2}\.csv$/`.
6. Save the download to a scratch path (e.g. under the harness scratchpad directory) and read
   its contents. Assert:
   - First line is exactly `id,applicantName,amount,status,approver,createdAt`.
   - There is at least one data row beyond the header (proves the populated-grid path actually
     produced data rows, not just a header — the thing an empty-grid unit test can't show).
   - The number of data rows in the CSV equals the number of `<tr>` rows rendered in
     `#loansGrid tbody` at the time of the click — a same-page consistency check that only a
     real browser + real download can perform (unit tests render the page and call the export
     route through two entirely separate mocked calls and never cross-check them against each
     other).

**Assertions -> acceptance criteria:**
- "Each grid page... shows an Export CSV link/button next to its existing primary action
  button, pointing at the new route" (rendered-DOM half) — steps 2.
- Implicit "this is a real download, not a broken/JS-blocked link" — steps 3-4 (not a literal
  REQ-001 AC line item, but the explicit behavior the task brief asked this plan to prove).
- Corroboration (not primary proof — Supertest already owns this) of the header-row format and
  non-empty-store behavior — step 6.

**Priority:** P0 — this is the only place in the whole test suite (unit, integration, or e2e)
where a human clicking the button in a real browser is verified to work at all.

---

### E2E-2 (P0): lending-webapp `/lendor` — Export CSV link triggers a real download of a well-formed, populated CSV

**Consolidates:** TC-7 (rendered-DOM half, lending-webapp) + the same new browser-only
download/content assertions as E2E-1, mirrored for the second app. Kept as a **separate** spec
from E2E-1 (not parametrized into one file) because it targets a different origin
(`https://localhost:3001`) — a different server/app entirely, not just a different route on the
same app — so there is no shared browser context or navigation state to consolidate.

**Entry state:** Fresh browser context, navigate to `https://localhost:3001/lendor`. Primary
path: rely on the worktree's 1 checked-in approver record. Fallback (only if grid renders
empty): seed one approver via the UI form, tagged `E2E-CSV-SeedApprover`, with matching teardown.

**Test data:** None created in the expected/primary run; fallback creates/deletes exactly one
approver record, same rules as E2E-1.

**Steps:** (mirrors E2E-1 exactly, substituting names)
1. Navigate to `/lendor`. Assert `#approversGrid` is visible with at least one row.
2. Assert a `link` with accessible name `Export CSV` is visible, `href` equals
   `/lendor/export.csv`, positioned adjacent to the `Add New Loan Approver` button.
3. `Promise.all([waitForEvent('download'), click])`.
4. Assert `page.url()` still ends in `/lendor` after the click (download, not navigation).
5. Assert `suggestedFilename()` matches `/^loan-approvers-\d{4}-\d{2}-\d{2}\.csv$/`.
6. Read the downloaded file. Assert first line is exactly `id,name,createdAt`; at least one data
   row present; data-row count equals the number of `#approversGrid tbody tr` rows at click time.

**Assertions -> acceptance criteria:** same mapping as E2E-1, for lending-webapp's AC lines.

**Priority:** P0, same justification as E2E-1.

## 6. Items explicitly NOT sent to the browser-test generator (send-back / no action)

Per the task brief's instruction to flag cases that are actually API/integration tests rather
than browser journeys:

- **TC-1, TC-2, TC-3, TC-4, TC-6:** pure HTTP status/header/body assertions with no rendered-DOM
  or user-interaction component — fully owned by `loanRoute.test.ts` / `lendorRoute.test.ts`
  (mocked store) and `exportIntegration.test.ts` (real fs). No browser adds anything here beyond
  what E2E-1/E2E-2 step 6 already corroborates incidentally. **No new spec needed.**
- **TC-5 (RFC 4180 escaping):** this is a pure string-transformation/serialization unit concern
  (`escapeCsvField`'s quoting/doubling logic) with a specific crafted fixture value — there is no
  user journey where a browser adds evidence beyond what `loanRoute.test.ts`'s dedicated test
  already proves byte-for-byte. Forcing this fixture into the real, git-tracked demo data just to
  exercise it in a browser would require mutating shared demo rows for no additional signal.
  **No action — stays a unit test.**
- **TC-8 (test-convention/process compliance — "are there Supertest tests, do they mock
  correctly, does `npm test` pass"):** this is a meta-test about the test suite itself, not a
  product behavior — not translatable into any browser journey. **No action; out of scope for
  e2e entirely.**

## 7. Summary for the e2e-generator

Two specs to write, both P0, both new (no existing e2e specs found in this repo —
`Glob` for `playwright*.config*` returned nothing):
1. `loan-webapp` `/loan` export-download spec (E2E-1 above).
2. `lending-webapp` `/lendor` export-download spec (E2E-2 above).

Both require: `ignoreHTTPSErrors: true`, base URLs `https://localhost:3000` /
`https://localhost:3001`, servers started from the `REQ-001/integration` worktree (not `main`),
role/text-based locators per §3 (no selector prep work needed), regex (not literal) filename
assertions, and the read-only-first / create-then-delete-fallback seeding strategy in §2 with
teardown guaranteed regardless of test outcome whenever the fallback path is taken.
