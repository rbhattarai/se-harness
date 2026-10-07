---
name: wiki-ingest
description: Ingest an external source (Confluence page, Jira epic, URL, document) into the project's domain wiki — synthesize into pages, update the index, log the operation. Use when the user shares a source, when org conventions_url is set, or when /harness-goal finds an unread PRD.
---

# Wiki Ingest (Karpathy pattern, B7)

You maintain `.harness/memory/wiki/` — synthesized domain knowledge. **Raw sources are
immutable; you never store copies of them — only synthesis.** Retrieval stays live via MCP
(Atlassian for Jira/Confluence, SharePoint MCP) for those three; NAS documents/video have no
"live" retrieval at all — the citation is a filesystem path, and re-fetching means re-opening
the file.

**Which wiki**: if this repo is part of a workspace (`workspace.yaml` exists), domain-wide
knowledge (anything from Jira/Confluence/SharePoint/NAS) goes in the **workspace-root**
`.harness/memory/wiki/`, not this repo's own — `/harness-mem-wiki` is the dedicated driver for
those five sources specifically (scope selection, credentials, staleness tracking, the NAS
recursive walk, video transcription gating). Use this skill directly, as described below, for
an ad-hoc single-item ingestion mid-task (the user pastes a URL, `/harness-goal` finds an
unread PRD) — into whichever wiki (workspace-level or this repo's own) the content actually
belongs to by the same domain-wide-vs-repo-specific judgment `wiki-query` uses.

## Procedure
1. **Read the source** via the right MCP/tool (Confluence page, Jira epic tree, fetched URL,
   local document, a transcript already produced by `/harness-mem-wiki`'s video step).
2. **Extract**: entities (services, domain objects, flows), decisions (+rationale), constraints,
   contradictions with existing wiki content.
3. **Synthesize into pages** (`wiki/<topic>.md`) — update existing pages rather than creating
   near-duplicates; one concept per page; rewrite freely (this tier is *revised*, not
   append-only). A single source legitimately touches many pages. **Video-sourced content gets
   structured sections instead of freeform prose** — `## Key Takeaways`, `## Important Points`,
   `## Do's and Don'ts` — populated from what the transcript actually supports, a section
   omitted rather than padded if it doesn't apply.
4. Each page carries a `sources:` footer line per contributing source
   (`Confluence ACME/PRD-payments, ingested 2026-07-15`) — provenance without copying content.
5. **Contradictions**: never silently overwrite. Add a `⚠ CONTRADICTION` block quoting both
   claims + sources, and surface it to the user (or leave it for wiki-lint if mid-task).
6. **Refresh `wiki/index.md`** — one line per page. **Append to `wiki/log.md`**:
   `date | ingest | source | pages touched`.

## Rules
- No secrets, credentials, or personal data into pages — ever, even if the source has them.
- Keep pages skimmable (< ~150 lines); split when they outgrow that.
- Cross-link related pages with `[[wiki-links]]` — links compound value.
