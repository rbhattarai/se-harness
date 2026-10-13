# Test cases: CSV export for the Loan Management and Loan Approvers grids

> Local-only test case record for REQ-001. No XRay/Zephyr project is configured for this repo
> — these are plain local IDs (TC-1 .. TC-8), not tracker keys. `test_cases:` in REQ-001.md
> frontmatter intentionally remains empty. One test case per acceptance criterion, written
> concretely enough to translate directly into Supertest unit tests and/or Playwright e2e
> scenarios.

**REQ:** REQ-001

---

## TC-1: loan-webapp export route returns 200 with CSV content-type and attachment header

**Covers AC:** `GET /loan/export.csv` (loan-webapp) returns `200`, `Content-Type: text/csv`,
and a `Content-Disposition: attachment; filename="loans-<YYYY-MM-DD>.csv"` header.

**Preconditions:**
- loan-webapp `app` (from `src/app.ts`) is available for Supertest, with `loanStore`'s
  `readLoans()` mocked to return a non-empty array of at least one well-formed `Loan` record
  (all fields populated, no special characters needed for this case).
- System/mock date is fixed (e.g. `2026-07-20`) if the filename date is derived from
  `Date.now()`, so the expected filename is deterministic.

**Steps:**
1. Send `GET /loan/export.csv` against the app.
2. Inspect the response status code.
3. Inspect the `Content-Type` response header.
4. Inspect the `Content-Disposition` response header.

**Expected result:**
- Status is `200`.
- `Content-Type` header is `text/csv` (charset suffix, if any, is acceptable as long as the
  base type is `text/csv`).
- `Content-Disposition` header equals
  `attachment; filename="loans-2026-07-20.csv"` (date matches the fixed/mocked "today").

---

## TC-2: loan-webapp export CSV body has exact header row and one data row per loan record

**Covers AC:** The loan-webapp CSV body's header row is exactly
`id,applicantName,amount,status,approver,createdAt`, followed by one data row per record
currently in `data/loans.json`, in the same order `readLoans()` returns them.

**Preconditions:**
- loan-webapp `app` available for Supertest, with `readLoans()` mocked to return a fixed,
  known array of 3 `Loan` records with distinct `id`s (e.g. `L-1`, `L-2`, `L-3`) in a specific
  order, no comma/quote/newline values in this case (covered separately in TC-5).

**Steps:**
1. Send `GET /loan/export.csv` against the app.
2. Split the response body text on CRLF or LF line breaks.
3. Compare the first line to the expected header string.
4. Compare each subsequent line, in order, to the expected raw-value row built from the mocked
   `readLoans()` array (same field order as the header: `id, applicantName, amount, status,
   approver, createdAt`).
5. Assert there are exactly 3 data lines (plus the header line, plus at most one trailing
   blank line from a final newline) — no extra or missing rows.

**Expected result:**
- First line is exactly `id,applicantName,amount,status,approver,createdAt`.
- Each of the 3 following lines matches the corresponding mocked record's raw field values in
  the same order `readLoans()` returned them (e.g. amount rendered as `25000`, not
  `"$25,000"`; `createdAt` as an ISO 8601 string, not locale-formatted).
- Total row count (excluding header and any single trailing blank line) equals 3.

---

## TC-3: lending-webapp export route returns 200 with CSV content-type and attachment header

**Covers AC:** `GET /lendor/export.csv` (lending-webapp) returns `200`, `Content-Type:
text/csv`, and a `Content-Disposition: attachment; filename="loan-approvers-<YYYY-MM-DD>.csv"`
header.

**Preconditions:**
- lending-webapp `app` (from `src/app.ts`) available for Supertest, with `approverStore`'s
  `readApprovers()` mocked to return a non-empty array of at least one well-formed `Approver`
  record.
- System/mock date fixed (e.g. `2026-07-20`) for a deterministic expected filename.

**Steps:**
1. Send `GET /lendor/export.csv` against the app.
2. Inspect the response status code.
3. Inspect the `Content-Type` response header.
4. Inspect the `Content-Disposition` response header.

**Expected result:**
- Status is `200`.
- `Content-Type` header is `text/csv`.
- `Content-Disposition` header equals
  `attachment; filename="loan-approvers-2026-07-20.csv"`.

---

## TC-4: lending-webapp export CSV body has exact header row and one data row per approver record

**Covers AC:** The lending-webapp CSV body's header row is exactly `id,name,createdAt`,
followed by one data row per record currently in `data/loan-approvers.json`.

**Preconditions:**
- lending-webapp `app` available for Supertest, with `readApprovers()` mocked to return a
  fixed, known array of 2 `Approver` records with distinct `id`s, no special characters in
  this case.

**Steps:**
1. Send `GET /lendor/export.csv` against the app.
2. Split the response body text on line breaks.
3. Compare the first line to the expected header string.
4. Compare each subsequent line, in order, to the expected raw-value row built from the mocked
   `readApprovers()` array (field order: `id, name, createdAt`).
5. Assert there are exactly 2 data lines (plus header, plus at most one trailing blank line).

**Expected result:**
- First line is exactly `id,name,createdAt`.
- Each of the 2 following lines matches the corresponding mocked record's raw field values in
  order, with `createdAt` as an ISO 8601 string.
- Total data row count equals 2.

---

## TC-5: RFC 4180 escaping of fields containing comma, double-quote, or newline

**Covers AC:** A field containing a comma, double-quote, or newline is wrapped in double
quotes with internal double-quotes doubled (RFC 4180), verified with at least one such value
in a unit test.

**Preconditions:**
- loan-webapp `app` available for Supertest, with `readLoans()` mocked to return a single
  `Loan` record whose `applicantName` is set to a value that exercises all three special
  characters at once, e.g. `Smith, "Bob" Jr.\nSuite 2` (contains a comma, two double quotes,
  and an embedded newline).

**Steps:**
1. Send `GET /loan/export.csv` against the app.
2. Extract the data row corresponding to this record from the response body.
3. Inspect the raw (unescaped-by-the-test) `applicantName` field of that CSV row.

**Expected result:**
- The `applicantName` field in the CSV output is wrapped in a surrounding pair of double
  quotes.
- Every literal double quote inside the original value is doubled (`"` becomes `""`) inside
  the quoted field.
- The embedded newline is preserved literally inside the quoted field (does not create a
  spurious extra CSV row when parsed by an RFC 4180-compliant CSV parser).
- Concretely, for input `Smith, "Bob" Jr.\nSuite 2`, the emitted field is
  `"Smith, ""Bob"" Jr.\nSuite 2"` (using the literal newline within the quotes).

---

## TC-6: loan-webapp export returns header-only CSV (200, not an error) when the store is empty

**Covers AC:** When the underlying store is empty, the route still returns `200` with only the
header row (not an error, not a 404/500).

**Preconditions:**
- loan-webapp `app` available for Supertest, with `readLoans()` mocked to return `[]`.

**Steps:**
1. Send `GET /loan/export.csv` against the app.
2. Inspect the response status code.
3. Inspect the full response body text.

**Expected result:**
- Status is `200` (explicitly not `404` or `500`).
- Body consists of exactly the header row `id,applicantName,amount,status,approver,createdAt`
  and no data rows (allowing for at most one trailing newline).

*(This test case's pattern — mock `readApprovers()` to return `[]` and assert
`200` + header-only body for `GET /lendor/export.csv` — should also be applied to
lending-webapp; the AC covers "the underlying store" generically for both apps, so the
e2e-planner/automation step should produce this as two parametrized/duplicated assertions,
one per app, both under this TC-6.)*

---

## TC-7: Export CSV link/button is present on both grid pages

**Covers AC:** Each grid page (`loan-webapp/src/views/loan.ejs`,
`lending-webapp/src/views/lendor.ejs`) shows an "Export CSV" link/button next to its existing
primary action button, pointing at the new route.

**Preconditions:**
- loan-webapp `app` available (Supertest, HTML response) or app running for a browser-based
  (Playwright) check; `readLoans()` mocked/seeded with at least one record so the grid renders
  normally.
- lending-webapp `app`/running instance similarly available with at least one approver
  record.

**Steps:**
1. Request `GET /loan` (loan-webapp) and parse the returned HTML.
2. Locate the existing primary action button/link on that page (e.g. the "Add Loan" /
   equivalent primary action already on the page).
3. Assert an "Export CSV" link/button element exists adjacent to that primary action element,
   with an `href` (or equivalent action target) equal to `/loan/export.csv`.
4. Repeat steps 1-3 for `GET /lendor` (lending-webapp), asserting the adjacent "Export CSV"
   link/button targets `/lendor/export.csv`.

**Expected result:**
- Both `/loan` and `/lendor` HTML responses contain a visible "Export CSV" link/button.
- Each is positioned next to (immediately before/after, in the same control group/toolbar as)
  the page's existing primary action button — not buried elsewhere in the page.
- Each link/button's target URL is the corresponding new export route
  (`/loan/export.csv` or `/lendor/export.csv`).

---

## TC-8: Both new export routes are covered by Supertest unit tests per existing conventions

**Covers AC:** Both new routes are covered by Supertest unit tests following the existing
convention in `.harness/memory/testing-conventions.md` (mock the data-store module, assert
status/headers/body — no real file I/O).

**Preconditions:**
- Repository checked out at the commit implementing this REQ's routes.

**Steps:**
1. Locate the test file(s) exercising `loan-webapp`'s `GET /loan/export.csv` route (e.g.
   `loan-webapp/test/loanRoute.test.ts` or a new dedicated test file) and `lending-webapp`'s
   `GET /lendor/export.csv` route (e.g. `lending-webapp/test/lendorRoute.test.ts`).
2. Confirm each test file imports the app via `src/app.ts` (never `src/server.ts`).
3. Confirm each test file mocks the relevant data-store module (`vi.mock("../src/data/
   loanStore")` / `vi.mock("../src/data/approverStore")`, or equivalent path) rather than
   performing real file I/O, and mocks `../src/events` if that module is imported transitively
   by the route file.
4. Confirm the test suite asserts, at minimum: response status, `Content-Type` header,
   `Content-Disposition` header, and body content (header row + data rows) for both the
   non-empty and empty-store cases (TC-1/TC-2/TC-6 and TC-3/TC-4/TC-6 content, respectively).
5. Run `npm test` in both `loan-webapp/` and `lending-webapp/` and confirm the new tests pass
   with no real filesystem or network access performed (no `fs`/`https` calls escape the
   mocks).

**Expected result:**
- Both routes have dedicated Supertest-based unit tests in `test/`, following the app-under-
  test / mocking pattern already established for other routes in this repo (per
  `.harness/memory/testing-conventions.md`).
- No test performs real file I/O against `data/loans.json` or `data/loan-approvers.json`.
- `npm test` passes in both packages.
