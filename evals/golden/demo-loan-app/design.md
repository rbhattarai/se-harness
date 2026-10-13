---
req: REQ-001
status: draft
---

# Design: CSV export for the Loan Management and Loan Approvers grids

## Open questions
None block implementation. Everything below follows directly from REQ-001's resolved
decisions, the existing per-app duplication convention (`AGENTS.md`: "no internal libraries...
hand-roll only when nothing fits, and say so"), and precedent already in the codebase
(`generateLoanId`/`generateApproverId` both derive a date string via
`new Date().toISOString().slice(0, 10)`). Two small implementation choices were made below
where the REQ was silent — flagged inline, not blocking, supervisor can override if the user
disagrees:

- **CSV line-ending:** LF (`\n`), not CRLF. RFC 4180 technically specifies CRLF, but nothing
  else in this codebase emits CRLF, the test cases explicitly accept either ("split on CRLF or
  LF"), and LF is simpler to produce/assert. See ADR-1 for the escaping algorithm itself, which
  *is* RFC 4180-faithful where it matters (quoting/doubling).
- **Button style:** "Export CSV" rendered as a Bootstrap `btn-outline-*` anchor (secondary
  visual weight vs. the existing solid-color primary-action button), not a `<button>`. It must
  be a real `<a href>` (not a JS-triggered action) because the export is a plain `GET` file
  download with no modal/client JS involved, consistent with "no client-side JS/build step."

## Component summary

No new modules, no new files beyond the two already-listed test files. Everything lives inside
the 6 files named in REQ-001's Impact section. This is a deliberate scope decision — see ADR-1.

| File | Change |
|---|---|
| `loan-webapp/src/routes/loan.ts` | Add 2 private helper functions + 1 new `GET /export.csv` route |
| `loan-webapp/src/views/loan.ejs` | Add "Export CSV" link next to "New Loan" button |
| `loan-webapp/test/loanRoute.test.ts` | Add `describe("GET /loan/export.csv", ...)` block |
| `lending-webapp/src/routes/lendor.ts` | Add 2 private helper functions + 1 new `GET /export.csv` route |
| `lending-webapp/src/views/lendor.ejs` | Add "Export CSV" link next to "Add New Loan Approver" button |
| `lending-webapp/test/lendorRoute.test.ts` | Add `describe("GET /lendor/export.csv", ...)` block |

No changes to `loanStore.ts`, `approverStore.ts`, `app.ts`, `events.ts`, `workspace.yaml`, or
either contract file — confirmed no other callers of `readLoans()`/`readApprovers()` are
affected (both are called read-only, exactly as the existing `GET /` handlers already call
them).

---

## ADR-1: Hand-roll RFC 4180 CSV serialization, duplicated per app — no new dependency, no shared package

**Context:** Both apps need to serialize an array of flat records (no nested objects, no
nested arrays — `Loan` and `Approver` are both flat interfaces of strings/numbers) into a CSV
body with RFC 4180 quoting for 3 special characters. `AGENTS.md` requires checking internal
libraries first ("compose before you code"); `/harness-scan` already confirmed zero internal
libraries exist in this repo, so that check is satisfied — nothing to compose with. The
remaining choice is hand-rolled vs. pulling in an external npm CSV package (e.g. `csv-stringify`,
`papaparse`).

**Decision:** Hand-roll a ~10-line escape/serialize helper, duplicated independently in
`loan-webapp/src/routes/loan.ts` and `lending-webapp/src/routes/lendor.ts` (not extracted to a
shared file or package). This mirrors the repo's existing, established pattern of small
near-identical per-app utilities (`generateLoanId` / `generateApproverId`, each ~4 lines,
each independently defined in its own app's data-store file).

**Justification:**
- The serialization surface is trivial: 3-character class detection (`,`, `"`, `\n`/`\r`),
  quote-wrap, double internal quotes. This is not "reinventing a CSV parser" — there is no
  parsing, no multi-line-record handling, no dialect negotiation, no BOM/encoding concerns
  beyond what `res.send()` already does for any UTF-8 string body.
- Pulling in a library (e.g. `csv-stringify`) would be the *first* production dependency change
  in either `package.json` for something genuinely smaller than the two apps' existing
  hand-rolled ID generators. That asymmetry (a new dependency for something simpler than code
  the repo already hand-rolls) is the tell that this doesn't clear the "nothing fits" bar the
  other way — hand-rolling *is* the fit.
- Two functions duplicated across two files, ~20 lines total, is well inside the size/duplication
  budget the repo has already implicitly accepted (`generateLoanId`/`generateApproverId` today).
  If a third or fourth export consumer appears later, that's the trigger to extract a real shared
  package — not now, and not in scope for this REQ (REQ-001's Impact section fixes the blast
  radius at exactly these two route files).

**Consequences:**
- No `package.json`/`package-lock.json` changes in either app; no new supply-chain surface.
- The escape/serialize logic is duplicated verbatim (with column-list differences) between
  `loan.ts` and `lendor.ts`. This is intentional, matches existing repo convention, and is a
  known, accepted tradeoff already made by the codebase for other small utilities — not a new
  divergence pattern. It's not exported from either module (no public API surface change beyond
  the new route), so there's nothing for another module to accidentally depend on.
- If more than these two export routes appear in the future, revisit whether a shared package is
  now justified (out of scope here; flag in a future REQ, not this one).

---

## CSV serialization algorithm (implement exactly as written)

Add to **both** `loan-webapp/src/routes/loan.ts` and `lending-webapp/src/routes/lendor.ts`, as
module-private (non-exported) functions, placed directly below the existing imports and above
`const router = Router();`:

```ts
function escapeCsvField(value: string | number): string {
    const str = String(value);
    if (/[",\n\r]/.test(str)) {
        return `"${str.replace(/"/g, '""')}"`;
    }
    return str;
}
```

- `String(value)` first — this is what turns a `number` (e.g. `amount: 25000`) into `"25000"`
  with no formatting (no thousands separator, no currency symbol) — the raw-machine-readable
  requirement is satisfied simply by never calling `.toLocaleString()` or any display formatter
  here (contrast with `loan.ejs`'s existing `loan.amount.toLocaleString()` used for on-screen
  display only — that call must NOT be reused for the CSV path).
- The regex `/[",\n\r]/` tests for exactly the 3 RFC 4180 trigger characters: comma, double
  quote, and any newline character (`\n` or `\r`, covering both LF-only and CRLF-embedded field
  values, e.g. pasted-in Windows text).
- If none of those characters are present, the field is returned unquoted, unmodified.
- If any are present: every literal `"` inside the field is first doubled (`"` → `""`) via
  `.replace(/"/g, '""')`, and then the whole result is wrapped in one pair of literal `"` at each
  end. Order matters — the doubling must happen before wrapping, not after (wrapping first would
  double the two just-added boundary quotes too).
- Worked example (this is TC-5's fixture, work it through exactly): input
  `Smith, "Bob" Jr.\nSuite 2` contains a comma, two `"`, and a `\n` → triggers quoting.
  `.replace(/"/g, '""')` → `Smith, ""Bob"" Jr.\nSuite 2`. Wrapped →
  `"Smith, ""Bob"" Jr.\nSuite 2"`. This is the literal expected substring in TC-5.

**loan-webapp** — add just below `escapeCsvField`, using the existing `Loan` interface (add
`Loan` to the existing named import from `"../data/loanStore"` — change line 2 to
`import { readLoans, writeLoan, deleteLoan, generateLoanId, Loan } from "../data/loanStore";`):

```ts
function loansToCsv(loans: Loan[]): string {
    const header = "id,applicantName,amount,status,approver,createdAt";
    const rows = loans.map((loan) =>
        [loan.id, loan.applicantName, loan.amount, loan.status, loan.approver, loan.createdAt]
            .map(escapeCsvField)
            .join(","),
    );
    return [header, ...rows].join("\n") + "\n";
}
```

**lending-webapp** — add just below its own copy of `escapeCsvField`, using the existing
`Approver` interface (add `Approver` to the existing named import from
`"../data/approverStore"` — change the import block to also pull in `Approver`):

```ts
function approversToCsv(approvers: Approver[]): string {
    const header = "id,name,createdAt";
    const rows = approvers.map((approver) =>
        [approver.id, approver.name, approver.createdAt].map(escapeCsvField).join(","),
    );
    return [header, ...rows].join("\n") + "\n";
}
```

Column order in both functions is fixed by REQ-001 and must not be reordered:
`id, applicantName, amount, status, approver, createdAt` (loan-webapp) and
`id, name, createdAt` (lending-webapp) — these produce the header rows required verbatim by
the acceptance criteria.

Empty-array input (`loans = []` / `approvers = []`) naturally produces `[header, ...[]].join("\n")
+ "\n"` = the header row plus a single trailing `\n` and nothing else — satisfies the
header-only/empty-store acceptance criterion with no special-case branch needed.

---

## Route placement and definitions

**`loan-webapp/src/routes/loan.ts`** — insert the new route immediately after the existing
`router.get("/", ...)` handler (the page-render route) and before `router.post("/", ...)` (the
create-loan route). Both `GET /` and `GET /export.csv` are read-only views over the same
`readLoans()` data, so grouping them keeps the two "read" routes adjacent at the top of the
file, ahead of the "write" routes (`POST /`, `POST /:id/delete`) and the existing
`GET /api/loans` JSON route at the bottom. There is no Express 5 path-matching conflict either
way — `/export.csv` is a static literal segment distinct from `/`, `/:id/delete`, and
`/api/loans` — so this ordering is a readability choice, not a correctness requirement, but
implement it in this position for consistency with the design below:

```ts
router.get("/export.csv", (req: Request, res: Response) => {
    const loans = readLoans();
    const csv = loansToCsv(loans);
    const dateStr = new Date().toISOString().slice(0, 10);
    res.setHeader("Content-Type", "text/csv");
    res.setHeader("Content-Disposition", `attachment; filename="loans-${dateStr}.csv"`);
    res.send(csv);
});
```

**`lending-webapp/src/routes/lendor.ts`** — same placement rule: immediately after the existing
`router.get("/", ...)` handler, before `router.post("/", ...)`:

```ts
router.get("/export.csv", (req: Request, res: Response) => {
    const approvers = readApprovers();
    const csv = approversToCsv(approvers);
    const dateStr = new Date().toISOString().slice(0, 10);
    res.setHeader("Content-Type", "text/csv");
    res.setHeader("Content-Disposition", `attachment; filename="loan-approvers-${dateStr}.csv"`);
    res.send(csv);
});
```

**Date derivation:** `new Date().toISOString().slice(0, 10)` at request time, producing
`YYYY-MM-DD` (e.g. `2026-07-20`). This is the exact pattern already used in both
`loanStore.ts::generateLoanId` and `approverStore.ts::generateApproverId` (there, the hyphens
are additionally stripped for the ID; here, leave them in for the filename per REQ-001's
`loans-<YYYY-MM-DD>.csv` format). No new date-formatting logic is introduced — this reuses an
established idiom already present twice in the codebase.

**Header-setting order matters:** both `res.setHeader("Content-Type", ...)` calls must execute
*before* `res.send(csv)`. Express only auto-assigns a default `Content-Type` (`text/html`) inside
`res.send()` when no `Content-Type` header has been set yet; setting it explicitly first (via
raw `res.setHeader`, not `res.type()`, to avoid Express/`mime` appending an implicit
`; charset=utf-8`) guarantees the header value is exactly `text/csv` as the route file emits it.
(Test cases accept a charset suffix too, so this is a "keep it clean" choice, not a strict
requirement — but don't reorder the calls regardless, or the header won't apply at all.)

**No production-code time mocking needed** — `new Date()` at request time is fine per REQ-001;
mocking system time is a test-only concern (below).

---

## Test file changes

Both new `describe` blocks follow the file's existing pattern exactly: `vi.mock` the data-store
module and `../src/events` at the top (already present in both files — no new mocks to add
there), import `app` from `../src/app`, use `vi.resetAllMocks()` in `beforeEach`.

### `loan-webapp/test/loanRoute.test.ts` — add this new `describe` block

Add `import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";` (add `afterEach`
to the existing import) and append:

```ts
describe("GET /loan/export.csv", () => {
    beforeEach(() => {
        vi.resetAllMocks();
        vi.useFakeTimers();
        vi.setSystemTime(new Date("2026-07-20T12:00:00.000Z"));
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    it("returns 200 with text/csv content-type and the dated attachment filename (TC-1)", async () => {
        vi.mocked(readLoans).mockReturnValue([
            {
                id: "LOAN-1",
                applicantName: "Jane Smith",
                amount: 25000,
                status: "New",
                approver: "",
                createdAt: "2026-01-01T00:00:00.000Z",
            },
        ]);

        const res = await request(app).get("/loan/export.csv");

        expect(res.status).toBe(200);
        expect(res.headers["content-type"]).toMatch(/^text\/csv/);
        expect(res.headers["content-disposition"]).toBe(
            'attachment; filename="loans-2026-07-20.csv"',
        );
    });

    it("emits the exact header row and one data row per loan, in readLoans() order (TC-2)", async () => {
        vi.mocked(readLoans).mockReturnValue([
            {
                id: "L-1",
                applicantName: "A",
                amount: 100,
                status: "New",
                approver: "",
                createdAt: "2026-01-01T00:00:00.000Z",
            },
            {
                id: "L-2",
                applicantName: "B",
                amount: 200,
                status: "Pending",
                approver: "APPR-1",
                createdAt: "2026-01-02T00:00:00.000Z",
            },
            {
                id: "L-3",
                applicantName: "C",
                amount: 300,
                status: "Approved",
                approver: "APPR-2",
                createdAt: "2026-01-03T00:00:00.000Z",
            },
        ]);

        const res = await request(app).get("/loan/export.csv");
        const lines = res.text.split("\n").filter((line) => line.length > 0);

        expect(lines[0]).toBe("id,applicantName,amount,status,approver,createdAt");
        expect(lines[1]).toBe("L-1,A,100,New,,2026-01-01T00:00:00.000Z");
        expect(lines[2]).toBe("L-2,B,200,Pending,APPR-1,2026-01-02T00:00:00.000Z");
        expect(lines[3]).toBe("L-3,C,300,Approved,APPR-2,2026-01-03T00:00:00.000Z");
        expect(lines.length).toBe(4);
    });

    it("wraps a field containing a comma, double-quote, and newline per RFC 4180 (TC-5)", async () => {
        vi.mocked(readLoans).mockReturnValue([
            {
                id: "L-1",
                applicantName: 'Smith, "Bob" Jr.\nSuite 2',
                amount: 100,
                status: "New",
                approver: "",
                createdAt: "2026-01-01T00:00:00.000Z",
            },
        ]);

        const res = await request(app).get("/loan/export.csv");

        // NOTE: do not split res.text on "\n" for this assertion — the fixture's own
        // embedded newline is inside the quoted field and would be misinterpreted as a row
        // break by a naive line-splitter. Assert on the raw substring instead.
        expect(res.text).toContain(
            'L-1,"Smith, ""Bob"" Jr.\nSuite 2",100,New,,2026-01-01T00:00:00.000Z',
        );
    });

    it("returns 200 with only the header row when the store is empty (TC-6)", async () => {
        vi.mocked(readLoans).mockReturnValue([]);

        const res = await request(app).get("/loan/export.csv");

        expect(res.status).toBe(200);
        expect(res.text.trim()).toBe("id,applicantName,amount,status,approver,createdAt");
    });
});
```

### `lending-webapp/test/lendorRoute.test.ts` — add this new `describe` block

Add `import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";` (add `afterEach`)
and append:

```ts
describe("GET /lendor/export.csv", () => {
    beforeEach(() => {
        vi.resetAllMocks();
        vi.useFakeTimers();
        vi.setSystemTime(new Date("2026-07-20T12:00:00.000Z"));
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    it("returns 200 with text/csv content-type and the dated attachment filename (TC-3)", async () => {
        vi.mocked(readApprovers).mockReturnValue([
            { id: "APPR-1", name: "John Doe", createdAt: "2026-01-01T00:00:00.000Z" },
        ]);

        const res = await request(app).get("/lendor/export.csv");

        expect(res.status).toBe(200);
        expect(res.headers["content-type"]).toMatch(/^text\/csv/);
        expect(res.headers["content-disposition"]).toBe(
            'attachment; filename="loan-approvers-2026-07-20.csv"',
        );
    });

    it("emits the exact header row and one data row per approver, in readApprovers() order (TC-4)", async () => {
        vi.mocked(readApprovers).mockReturnValue([
            { id: "APPR-1", name: "Alice", createdAt: "2026-01-01T00:00:00.000Z" },
            { id: "APPR-2", name: "Bob", createdAt: "2026-01-02T00:00:00.000Z" },
        ]);

        const res = await request(app).get("/lendor/export.csv");
        const lines = res.text.split("\n").filter((line) => line.length > 0);

        expect(lines[0]).toBe("id,name,createdAt");
        expect(lines[1]).toBe("APPR-1,Alice,2026-01-01T00:00:00.000Z");
        expect(lines[2]).toBe("APPR-2,Bob,2026-01-02T00:00:00.000Z");
        expect(lines.length).toBe(3);
    });

    it("returns 200 with only the header row when the store is empty (TC-6)", async () => {
        vi.mocked(readApprovers).mockReturnValue([]);

        const res = await request(app).get("/lendor/export.csv");

        expect(res.status).toBe(200);
        expect(res.text.trim()).toBe("id,name,createdAt");
    });
});
```

**Why `vi.useFakeTimers()` + `vi.setSystemTime(...)` rather than regex-matching the date:** the
route computes the filename via `new Date().toISOString()` at request time (no injectable clock
parameter — the REQ explicitly says not to add one), so the only way to assert the *exact*
frozen filename literal (`loans-2026-07-20.csv`), as TC-1/TC-3 require, is to freeze the system
clock for the duration of the test via Vitest's fake timers, matching each TC's stated
precondition ("System/mock date is fixed... so the expected filename is deterministic"). This is
the first use of `vi.useFakeTimers()` in either app's test suite — it's a standard Vitest API,
not a new test framework or mocking strategy, so it doesn't conflict with
`.harness/memory/testing-conventions.md`. `afterEach(() => vi.useRealTimers())` restores real
timers so later tests/files aren't affected (Vitest resets configured mocks between files, but
being explicit here avoids any cross-test-file timer leakage within the same file).

No changes needed to the existing `vi.mock("../src/data/loanStore", ...)` /
`vi.mock("../src/data/approverStore", ...)` / `vi.mock("../src/events", ...)` factory objects in
either test file — `readLoans`/`readApprovers` are already mocked there; no new store or events
functions are introduced by this REQ.

---

## View changes

### `loan-webapp/src/views/loan.ejs`

Change the toolbar block (currently lines 25-30) from:

```html
<div class="d-flex justify-content-between align-items-center mb-4">
    <h4 class="mb-0 text-muted">Loan Management</h4>
    <button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#newLoanModal">
        <i class="bi bi-plus-lg me-1"></i> New Loan
    </button>
</div>
```

to:

```html
<div class="d-flex justify-content-between align-items-center mb-4">
    <h4 class="mb-0 text-muted">Loan Management</h4>
    <div class="d-flex gap-2">
        <a href="/loan/export.csv" class="btn btn-outline-primary">
            <i class="bi bi-download me-1"></i> Export CSV
        </a>
        <button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#newLoanModal">
            <i class="bi bi-plus-lg me-1"></i> New Loan
        </button>
    </div>
</div>
```

The "Export CSV" link is placed *before* the "New Loan" button inside a new wrapping
`d-flex gap-2` container (so both sit in the same right-hand control group, satisfying TC-7's
"adjacent to the existing primary action button" — the wrapping div keeps them visually and
structurally grouped without disturbing the existing `justify-content-between` layout that keeps
the "Loan Management" heading pinned left). No other part of `loan.ejs` changes — the grid table,
the "New Loan" modal, and the SSE reload script are untouched.

### `lending-webapp/src/views/lendor.ejs`

Change the toolbar block (currently lines 25-30) from:

```html
<div class="d-flex justify-content-between align-items-center mb-4">
    <h4 class="mb-0 text-muted">Lendor Management</h4>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#newApproverModal">
        <i class="bi bi-person-plus me-1"></i> Add New Loan Approver
    </button>
</div>
```

to:

```html
<div class="d-flex justify-content-between align-items-center mb-4">
    <h4 class="mb-0 text-muted">Lendor Management</h4>
    <div class="d-flex gap-2">
        <a href="/lendor/export.csv" class="btn btn-outline-success">
            <i class="bi bi-download me-1"></i> Export CSV
        </a>
        <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#newApproverModal">
            <i class="bi bi-person-plus me-1"></i> Add New Loan Approver
        </button>
    </div>
</div>
```

Same pattern: new link placed before the existing primary-action button inside a new
`d-flex gap-2` wrapper. No other part of `lendor.ejs` changes.

Both apps' `bootstrap-icons` CDN link (already present in both `<head>` blocks) already provides
`bi-download`; no new asset/CDN reference is introduced.

---

## Data model / contract impact

None. `Loan` and `Approver` interfaces (`loanStore.ts`, `approverStore.ts`) are unchanged —
confirmed by reading both files directly. `readLoans()`/`readApprovers()` signatures and
behavior are unchanged; the new routes are pure additional consumers of the exact same read
functions the existing `GET /`  page routes already call. `workspace.yaml`'s `loan-record` and
`notify-webhook` contracts are untouched — no record-shape, status-transition, or webhook/SSE
change (already confirmed correct in REQ-001's own Impact section; verified here by reading
`workspace.yaml`, `loanStore.ts`, and `approverStore.ts` directly rather than taking the REQ's
word for it).

## Migration needs

None. No schema change, no data migration, no new environment variables, no Docker/compose
change (`docker-compose.yml` untouched — both routes run inside the existing Express apps on
their existing ports 3000/3001).
