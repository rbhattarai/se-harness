---
name: wiki-query
description: Answer domain questions from the project wiki with citations — and file useful new syntheses back into it. Use during /harness-goal deep-dive (step 2) and whenever a question concerns domain knowledge rather than code.
---

# Wiki Query

1. **Two possible locations**: if this repo is part of a workspace (`workspace.yaml` or
   `../workspace.yaml` exists), check the **workspace-root** `.harness/memory/wiki/` first —
   that's where `/harness-mem-wiki` writes non-code synthesis (Jira/Confluence/SharePoint/NAS).
   Then also check this repo's own `.harness/memory/wiki/` if it has entries — repo-specific
   domain knowledge still lives there, workspace-level doesn't replace it. A single-repo
   project (no workspace) only ever has the one, unchanged.
2. **Index first**: read each location's `wiki/index.md`; open only the pages it points to for
   this question. Never bulk-read the wiki (context-injector doctrine).
3. **Answer with citations**: every claim names its page (`per [[payments]]`), and when it came
   from the workspace-level wiki vs. this repo's own, say which. If pages carry a
   `⚠ CONTRADICTION` block relevant to the answer, present both sides — don't pick silently.
4. **Gaps are answers too**: if the wiki doesn't cover it, say so and name the likely source to
   ingest (Confluence space, Jira epic — `/harness-mem-wiki` is what actually runs that) rather
   than guessing from general knowledge.
5. **Compound**: if answering required synthesis across ≥2 pages and the result is durable,
   file it back as a new/updated page + index line (explorations compound — Karpathy). Write
   domain-wide synthesis to the workspace-level wiki when one exists, repo-specific synthesis
   to this repo's own.
6. **Log** non-trivial queries: `date | query | question | pages read` in `wiki/log.md` — the
   one at whichever location(s) you actually read from.
