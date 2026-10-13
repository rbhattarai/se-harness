# Migrations

One script per schema step: `<N>-to-<N+1>.sh`. `scripts/migrate.sh` chains them from the
project's `schema_version` (lockfile; absent = 1) up to the highest step present here. There is
no migration yet because the schema is still 1 — add `1-to-2.sh` only when a release changes the
layout of `.harness/` in a way old projects can't read.

## Contract for a migration script

```bash
#!/usr/bin/env bash
# migration: one-line description (shown by --dry-run)
set -eu
PROJ="$1"            # project root; cd there or use "$PROJ/…" paths
```

- **Idempotent.** Running twice must be harmless (the runner can re-run after a rollback).
- **Additive.** Rename/restructure, never delete user content. Anything user-authored
  (memory, requirements, hand-written text in AGENTS.md/CLAUDE.md) is out of bounds except to move it.
- **Generated blocks only via render-block.sh:** `bash "$HARNESS_RENDER_BLOCK" $HARNESS_RENDER_FLAGS <target> <block-file>`.
  It refuses to overwrite hand-edited blocks (exit 3 — propagate it by not catching it, `set -e`).
- **No network.** (PRIVACY.md; a test enforces it for `scripts/`.)
- **Don't touch `schema_version` or `migrations.log`** — the runner owns them.
- Files you may change: `.harness/**` (not `.harness/backup/`), `AGENTS.md`, `CLAUDE.md`, `.mcp.json`.
  Only these are backed up and rolled back.
- Fail loudly (non-zero exit): the runner then restores everything from the pre-run backup.
- Add a test fixture: a frozen project at the old schema under `tests/fixtures/migrate/` and an
  assertion that user edits survive.
