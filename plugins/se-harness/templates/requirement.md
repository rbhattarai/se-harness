---
id: REQ-000            # unique, threads through branch / commits / PR / story
status: draft          # draft → approved (HUMAN ONLY flips this) → in-progress → done
story: ""              # Jira story key once created (system of record — A5 #4)
test_cases: []         # XRay/Zephyr keys once created
created: YYYY-MM-DD
goal: ""               # one sentence — the user's original ask
---

# REQ-000: <title>

## Context
<Why now. What the memory deep-dive found: impacted code (graph query results), related
PRDs/decisions (wiki pages), prior attempts (session log). Cite sources as [[wiki-links]].>

## Refined requirement
<The unambiguous statement produced after grilling. No untestable words ("fast", "better").>

## Acceptance criteria
- [ ] <testable criterion 1>
- [ ] <testable criterion 2>

## Out of scope
- <explicitly excluded items surfaced during grilling>

## Impact
<Blast radius: services/modules touched, contracts affected (check workspace provides/consumes),
migration or config changes needed.>

## Open questions
- <anything the user deferred — must be empty before status can be approved>
