---
name: coding-discipline
description: Karpathy-inspired coding discipline — think before coding, simplicity first, surgical changes, goal-driven execution — with real-world wrong/right examples. Use when implementing, reviewing, or fixing code that shows hidden assumptions, overcomplication, scope creep, or vague success criteria.
---

# Coding Discipline

Behavioral guardrails against common LLM coding mistakes. Source:
https://github.com/multica-ai/andrej-karpathy-skills (derived from Karpathy's
observations on LLM coding pitfalls). Full wrong/right examples: `EXAMPLES.md`
in this directory.

## The four principles

1. **Think before coding** — state assumptions explicitly; present multiple
   interpretations instead of picking silently; push back when a simpler approach
   exists; stop and ask when confused.
2. **Simplicity first** — minimum code that solves the problem; no speculative
   features, single-use abstractions, unrequested configurability, or
   impossible-scenario handling. Test: would a senior engineer call this
   overcomplicated?
3. **Surgical changes** — touch only what the task requires; don't "improve"
   adjacent code, comments, or formatting; match existing style; mention unrelated
   dead code, don't delete it; clean up only orphans your changes created. Test:
   every changed line traces to the request.
4. **Goal-driven execution** — turn tasks into verifiable goals ("fix bug X" →
   "write a failing test for X, then make it pass"); for multi-step work state each
   step with its verification; loop until verified.

**Tradeoff:** these bias toward caution over speed. For trivial tasks, use judgment.

## When to open EXAMPLES.md

Open it when you catch yourself (or a diff under review) doing any of: assuming
scope/format/fields the user didn't state; reaching for an abstraction before the
second use case; reformatting or "improving" lines outside the task; starting work
with no test or check that would prove it done.
