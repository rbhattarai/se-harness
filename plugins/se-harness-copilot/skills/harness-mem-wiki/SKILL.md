---
name: harness-mem-wiki
description: Build and refresh the workspace-level domain wiki from non-code sources — Jira, Confluence, SharePoint, NAS documents, NAS video — gated on each source actually being configured, synthesis-only, nothing ingested without confirmation.
---


# /harness-mem-wiki — non-code domain-wiki build & refresh

Synthesize non-code sources into the **workspace-level** domain wiki
(`.harness/memory/wiki/` at the workspace root — distinct from any single repo's own). Same
doctrine as the `wiki-ingest` skill this command drives: raw sources are never copied into the
repo, only synthesis, with a citation back to the original. Jira/Confluence/SharePoint stay
live-refetchable via MCP; NAS documents/video have no "live" — the citation is a path, and
re-fetching means re-opening the file. `/harness-goal`'s deep-dive step reads what this command
builds.

This command only ingests sources that are actually configured in `workspace.yaml`'s
`shared:` (set during `/harness-init` Step 4); it never invents a source to check.

## Step 1 — Scope

1. If `$ARGUMENTS` names one source (`jira`, `confluence`, `sharepoint`, `nas-docs`,
   `nas-video`), process only that one — skip straight to its step below.
2. No source given: look at `workspace.yaml`'s `shared:` for which sources actually have
   something configured (non-empty `jira_project`/`confluence_spaces`/`sharepoint_sites`/
   `nas_doc_paths`/`nas_video_paths`). Ask whether to process every configured source, name
   specific ones, or stop — never infer consent to run everything from silence. A source with
   nothing configured is skipped and reported, never offered as a choice.
3. Resolve the workspace root the same way `/harness-mem-graphify` does — from `workspace.yaml`,
   not wherever the plugin is installed. No `workspace.yaml` at all → this command has nothing
   to do (non-code sources are workspace-scoped by design); say so and stop.

## Step 2 — Credentials

1. Look for a workspace-root `.env.harness`. Missing → offer to create it from
   `tools/harness/templates/env.harness.workspace.example`, tell the user exactly which vars to fill for the
   sources actually in scope this run, and **stop this run** until they confirm it's filled —
   never read a partially-filled file and guess at what's missing.
2. If the workspace root is itself inside a git repo (`git rev-parse --is-inside-work-tree` —
   true for the mono-repo topology, false for a plain sibling-clone folder), make sure
   `.env.harness` is in *that* repo's `.gitignore` (append from `tools/harness/templates/gitignore.harness`
   if not already present, same mechanics `/harness-init` Step 7 uses). A sibling-clone
   workspace root that isn't a git repo at all needs no `.gitignore` — there's nothing to
   accidentally commit it to.
3. Never read `.env.harness` content into chat, logs, or any wiki page — load it only into the
   environment for the MCP/CLI calls that need it.

## Step 3 — Jira, Confluence, SharePoint (MCP-based, live-refetchable)

For each in scope:
1. **Staleness, by source**: compare against
   `.harness/memory/wiki/.ingest-manifest.json` at the workspace root (create it, empty, if
   this is the first run) —
   - Jira: JQL filtered by `updated >=` the manifest's last-synced date for this project.
   - Confluence: each page's `lastModified` against the manifest's per-page last-synced date.
   - SharePoint: whatever its MCP exposes for modification time; if nothing, treat everything
     as potentially stale and say so rather than silently skipping (no data beats wrong data,
     but don't pretend there's a real staleness signal when there isn't one).
2. Present what's new or changed since last sync; ask whether to process all of it, name
   specific items, or skip this source for now.
3. **SharePoint specifically**: se-harness doesn't ship a SharePoint MCP server. If none is
   connected this session, report that plainly (point at
   `docs/setup-guide-copilot.md` Part 6 for standing one up) and skip — never silently treat an
   unreachable source as "nothing to do."
4. For each confirmed item: read it live via MCP → extract entities, decisions, constraints,
   contradictions with existing pages (same procedure as the `wiki-ingest` skill) → synthesize
   into `wiki/<topic>.md` at the **workspace root** (update an existing page rather than
   creating a near-duplicate) → `sources:` footer citing the item + today's date → update
   `wiki/index.md` and `wiki/log.md` (`wiki-ingest`'s own steps 4 and 6) → record the new
   last-synced marker in `.ingest-manifest.json`.

## Step 4 — NAS documents (filesystem, not MCP — no "live," the path is the citation)

Any document format, not just PDF/Office. The mechanics live in
`tools/harness/doc-extract.sh` (registry: `scripts/doc-registry/*.tsv`); the
default extractor for binary formats is **MarkItDown**. Pass `--registry-extra
<workspace>/.harness/doc-registry` to every call if that directory exists (it holds the
user's own added formats/converters, Step 4c).

### 4a — Inventory (read-only, before anything else)
1. Run `bash tools/harness/doc-extract.sh --inventory --skip-ext <skipped
   extensions from .ingest-manifest.json's formats:> <every nas_doc_paths entry>` — recursive,
   any depth; it already drops lock/temp/NAS-housekeeping files (`~$x`, `Thumbs.db`, `@eaDir`,
   `#recycle`…) and reports how many.
2. Show one table: **extension | files | size | status**. Statuses: `ready` (a reader is
   installed), `missing` (reader not installed), `unsupported` (no reader known for this
   extension), `flagged-ocr` (images — never ingested), `declined` (skipped on an earlier run).
   A path the script reports as `MISSING_PATH` (NAS offline/unmounted) is reported as such, not
   silently treated as empty.

### 4b — Close the gaps, one format group at a time
For every `missing` or `unsupported` extension (group by extractor so one install answers
several formats) ask once (AskUserQuestion), never installing anything unasked:
- **missing** → show the exact install text (`doc-extract.sh --install-cmd <extractor>`) and
  what it pulls in. Options: **install it**, **use a different/own converter** (4c), or
  **skip this format**. For MarkItDown, if `workspace.yaml`'s `shared.package_index` is set, the
  install must go through it exactly as `/harness-mem-graphify` Step 2 does (private index,
  `--system-certs`; if unreachable, stop and report — never disable TLS or fall back to public
  PyPI). Check `uv --version` first; no `uv` → say so and offer the user's own installer or skip.
  After installing, re-run `--tool-status <extractor>` to confirm; a failed install is reported
  and treated as **skip**.
- **unsupported** (an extension with no known reader) → options: **give me a converter
  command** (4c) or **skip**.
- **skip** ignores *only that extension*; every other format proceeds. Record each decision in
  `.ingest-manifest.json` under `formats: {<ext>: {decision: installed|custom|skipped,
  extractor, decided: <date>}}` so a skipped format is not asked about again on later runs
  (list them in one line at the end; the user can say "reconsider formats" to re-open them).
- **flagged-ocr** (images) and scanned PDFs (found at extraction time) are **not offered an
  install** in this version: OCR is out of scope. They are counted and listed in the report so
  nothing disappears silently.

### 4c — User-supplied converter (for locked-down machines or exotic formats)
Ask for a shell command that writes text/markdown to stdout, with `{in}` as the input path
(e.g. `mytool --to-md {in}`). Run it once on a sample file to prove it works, then append rows
to `<workspace>/.harness/doc-registry/extractors.tsv` and `formats.tsv` (same columns as the
built-in files; TAB-separated). Never put a command the user didn't write or approve there.

### 4d — Extract and synthesize
1. Fingerprint each `ready` file — path + mtime + size **+ extractor id** (so a newly installed
   or changed extractor re-offers files read poorly before) — and diff against the manifest's
   doc entries. Report new/changed vs. unchanged-skipped counts, then ask whether to process
   the new/changed ones, name specific ones, or skip.
2. For each confirmed file: `bash tools/harness/doc-extract.sh --extract
   <file> --max-chars 200000 --max-bytes 52428800`. Handle the exit code:
   0 → continue · 7 → flagged (scanned PDF/image): count it, don't retry · 6 → failed
   (corrupt/encrypted/tool error): report the file and reason, move on · 8 → too large: ask
   before raising `--max-bytes` · 4 → the reader vanished since 4a: back to 4b for that format.
   One bad file never aborts the run.
3. Extracted text is **transient** — not written into the repo or a cache (raw sources stay
   immutable and un-copied; this also keeps confidential NAS content out of git). Synthesize
   into a wiki page at the workspace root. **Spreadsheets and CSVs are not prose**: capture
   sheet/column names, what each sheet is for, notable rules and a small sample — never
   transcribe rows. Citation: the NAS path (a path, not a link), the extractor id, today's date.
   Update the manifest with the fingerprint and resulting page.

## Step 5 — NAS video (transcription first, the expensive one)

1. Recursively walk every configured `nas_video_paths` entry, same as step 4.
2. Fingerprint each video file (path + mtime + size) against `.ingest-manifest.json`'s video
   entries. **Report an estimate before asking anything** — file count, folder breakdown, rough
   total duration if cheaply readable from file metadata — then ask whether to process all
   new/changed ones, name specific ones, or skip. Never start transcribing without this
   confirmation; it's real compute time, not a cheap operation like the other sources here.
3. Confirm Graphify's video extra (`graphifyy[video]`) is installed — same gate
   `/harness-mem-graphify` Step 2 already has. If it was declined there, this source can't run;
   say so and point at that command rather than re-asking the same question here.
4. **Raw transcript handling, asked once per run (not once per video)**: keep transcripts
   gitignored locally (disposable, regenerable by re-running transcription against the source
   video — the default recommendation) or committed/tracked (team-shared, adds repo size).
   Record the choice in `.ingest-manifest.json` and apply it consistently for this run; it's
   fine to ask again on a later run if the user wants to change it.
5. Transcribe each confirmed video (check `graphify --help` for the current video-pipeline
   flags rather than assuming a specific one). Cache the raw transcript per the step 4 choice.
6. Synthesize each transcript into a wiki page at the workspace root with **structured
   sections** — `## Key Takeaways`, `## Important Points`, `## Do's and Don'ts` — populated
   from what the transcript actually supports; omit a section rather than padding it with
   nothing. Citation: the NAS video path, the timestamp range if the content came from a
   specific segment, and today's date. Update the manifest with the new fingerprint, the
   resulting page, and (if tracked) the transcript's location.

## Step 6 — Completion report

Per source: items processed / skipped as unchanged / skipped as not-configured, pages
created/updated. For NAS documents also a per-extension table: processed · failed (with reason) ·
skipped by the user's choice · flagged for OCR (scanned PDFs, images) · unsupported. For NAS video specifically, don't just report "done" — name what actually
landed: how many pages got a Key Takeaways section, an Important Points section, a Do's/Don'ts
section, so the user can see what was captured, not just that something ran. Contradictions
flagged during synthesis get called out explicitly here too, same as `wiki-ingest`'s own rule —
never buried in a page nobody re-reads.

## Keeping this fresh

Unlike `/harness-mem-graphify`'s code graph, there's no commit to trigger a refresh from — Jira
tickets and Confluence pages change independently of any repo's git history. Re-run this
command periodically, or point an external scheduler (cron, Windows Task Scheduler, a nightly
CI workflow) at it from the workspace root, the same way `/harness-mem-graphify`'s own
"keeping this fresh automatically" section recommends for the workspace-level graph merge.
