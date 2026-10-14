---
area: {{area}}                 # e.g. angular | dotnet | e2e-playwright | db-mssql | lib-ui-components
status: draft                  # draft | confirmed | stale
applies_to: ["{{glob}}"]       # files this doc governs; agents load it when they touch a match
libraries: []                  # - { name: "@acme/ui", version: "4.2.0" }  (staleness check)
evidence_hash: ""              # hash of the lint/format configs this was derived from
updated: {{date}}
---

# {{area}} conventions

> Loaded by agents before they write or review code matching `applies_to`. MUST = enforced at
> the PR gate. SHOULD = default; deviate only with a stated reason. Keep this doc under ~100 lines.

## Rules
| # | Level | Rule | Evidence |
|---|---|---|---|
| 1 | MUST | {{rule}} | {{file / config / org-guideline}} |

## Library catalog (compose first)
Use the internal library before writing anything new. Most-used first.

| Need | Use | Import | Example |
|---|---|---|---|
| {{what you need}} | `{{symbol}}` | `{{import path}}` | `{{minimal usage}}` |

## Anti-patterns
- {{hand-rolled thing}} → use `{{symbol}}` instead ({{evidence}})

## Golden examples
Read these before imitating the nearest file.
- `{{path/to/exemplary/file}}` — {{what it shows}}

## Review checklist
- [ ] {{one-line check a reviewer can verify from the diff}}

## Open questions
- {{unresolved inconsistency; who decides}}
