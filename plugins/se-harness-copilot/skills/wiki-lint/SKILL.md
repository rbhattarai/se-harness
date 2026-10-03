---
name: wiki-lint
description: Health-check the domain wiki — contradictions, stale claims, orphan pages, index drift, missing links. Use periodically, after large ingests, or when the user asks whether the wiki is trustworthy.
---

# Wiki Lint

Audit `.harness/memory/wiki/` and produce a findings report; fix mechanical issues, ask before
substantive ones.

## Step 0 — Run the deterministic check first

Run `scripts/wiki-lint.sh` against `.harness/memory/wiki` (from the plugin's `scripts/`
dir — on Copilot, the vendored `tools/harness/` copy).

Its findings (index drift, orphans, missing `sources:`, contradiction markers, oversize
pages, secret hits) need no LLM judgment — attach the full output to your report and work
from it. Everything below says which findings you fix directly vs. judge.

## Checks

1. **Index drift** — from the script (`MISSING-FROM-INDEX`, `DANGLING-INDEX-LINK`,
   `INDEX-MISSING`). *Fix mechanically:* add/drop the one-line entries.
2. **Orphans** — from the script (`ORPHAN`). Propose links or merging; apply once confirmed.
3. **Provenance** — from the script (`NO-SOURCES`). Re-ingest or drop the page; a page
   without a source is a rumor.
4. **Contradictions** — script locates (`CONTRADICTION: file:line`); you judge. List each
   with both sources quoted; resolution decisions belong to the user. Also flag new ones
   you spot between pages that carry no marker yet.
5. **Staleness** — LLM judgment, grounded by the script's SOURCES section (verbatim
   `sources:` lines per page): compare against recent daily-log entries and REQ activity.
   Flag for re-ingest; don't guess updates.
6. **Secrets sweep** — from the script (`SECRET-HIT: file:line` — content is never echoed).
   Open the location, redact immediately, and report (this fix never waits for permission).
7. **Size** — from the script (`OVERSIZE`). Propose splits; apply once confirmed.

## Output

Findings table (check | page | detail | action taken/proposed), then apply the mechanical
fixes, then append `date | lint | <n> findings | pages touched` to `wiki/log.md`.
