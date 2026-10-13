# Story: CSV export for the Loan Management and Loan Approvers grids

> Local-only story record for REQ-001. No Jira project/Atlassian MCP is configured for this
> repo — this file is the system of record for this REQ (not a tracker copy). No story key
> exists; `story:` in REQ-001.md frontmatter intentionally remains empty.

**REQ:** REQ-001
**Status:** approved

## Description

loan-webapp and lending-webapp are both server-rendered EJS/Express apps with no client-side
build step. loan-webapp's `/loan` page ("Loan Management") is the only full loans-listing grid;
lending-webapp has no equivalent full loans grid — its closest analog full-listing grid is
`/lendor` ("Loan Approvers"). Both read their full dataset directly from the shared flat-file
store (`data/loans.json`, `data/loan-approvers.json`) via `loanStore.ts` / `approverStore.ts`.

Add a CSV export capability to two existing grids:
1. **loan-webapp** `/loan` (Loan Management) — exports all loan records.
2. **lending-webapp** `/lendor` (Loan Approvers) — exports all approver records.

Each grid gets an "Export CSV" button/link that triggers a new server-side GET route
returning a `text/csv` response with a `Content-Disposition: attachment` header (no
client-side JS/build step, consistent with the rest of both apps). The route reads the same
data via the existing store functions (`readLoans()` / `readApprovers()`) used to render the
page — no new data path.

CSV columns match the grid's displayed columns, same order, but as **raw machine-readable
values** (not display-formatted): plain numbers (`25000`, not `"$25,000"`), ISO 8601 date
strings (not locale-formatted). Fields are CSV-escaped per RFC 4180 (quote any field
containing a comma, quote, or newline; double internal quotes).

- loan-webapp export columns: `id, applicantName, amount, status, approver, createdAt`
- lending-webapp export columns: `id, name, createdAt`

## Acceptance criteria

- [ ] `GET /loan/export.csv` (loan-webapp) returns `200`, `Content-Type: text/csv`, and a
      `Content-Disposition: attachment; filename="loans-<YYYY-MM-DD>.csv"` header.
- [ ] The loan-webapp CSV body's header row is exactly
      `id,applicantName,amount,status,approver,createdAt`, followed by one data row per
      record currently in `data/loans.json`, in the same order `readLoans()` returns them.
- [ ] `GET /lendor/export.csv` (lending-webapp) returns `200`, `Content-Type: text/csv`, and a
      `Content-Disposition: attachment; filename="loan-approvers-<YYYY-MM-DD>.csv"` header.
- [ ] The lending-webapp CSV body's header row is exactly `id,name,createdAt`, followed by one
      data row per record currently in `data/loan-approvers.json`.
- [ ] A field containing a comma, double-quote, or newline is wrapped in double quotes with
      internal double-quotes doubled (RFC 4180), verified with at least one such value in a
      unit test.
- [ ] When the underlying store is empty, the route still returns `200` with only the header
      row (not an error, not a 404/500).
- [ ] Each grid page (`loan-webapp/src/views/loan.ejs`, `lending-webapp/src/views/lendor.ejs`)
      shows an "Export CSV" link/button next to its existing primary action button, pointing at
      the new route.
- [ ] Both new routes are covered by Supertest unit tests following the existing convention in
      `.harness/memory/testing-conventions.md` (mock the data-store module, assert status/
      headers/body — no real file I/O).

## Out of scope

- CSV import (uploading/parsing a CSV back into the store).
- Scheduled or emailed exports.
- Per-row selection or filtering before export — always exports the full current dataset
  (neither grid has pagination/filtering today).
- Exporting the "Recent Loans" dashboard grids (`/index` in either app) — only the two grids
  named above.
- Any change to `loanStore.ts` / `approverStore.ts` read/write behavior, the loan-record or
  notify-webhook contracts, or the webhook/SSE sync — this is a read-only, additive export
  path with no status-transition or cross-app notification involved.

## Impact

**Files touched (blast radius via CodeGraph, no other callers affected):**
- `loan-webapp/src/routes/loan.ts` — new `GET /export.csv` route.
- `loan-webapp/src/views/loan.ejs` — new "Export CSV" link.
- `loan-webapp/test/loanRoute.test.ts` (or a new test file) — new route tests.
- `lending-webapp/src/routes/lendor.ts` — new `GET /export.csv` route.
- `lending-webapp/src/views/lendor.ejs` — new "Export CSV" link.
- `lending-webapp/test/lendorRoute.test.ts` (or a new test file) — new route tests.

**No contract impact** — `workspace.yaml`'s `loan-record` and `notify-webhook` contracts are
unaffected (no record-shape, status-transition, or webhook/SSE changes). No migration or config
changes; no new environment variables.
