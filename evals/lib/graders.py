"""Programmatic graders. Each returns list[Check]; none call a model.

Every grader is exercised against known-good and known-bad artifacts by the Layer-1
`grader_selftest` suite, so a grader that silently passes everything is caught offline.
"""
from __future__ import annotations

import re

from common import Check

REQ_SECTIONS = ["Context", "Refined requirement", "Acceptance criteria", "Out of scope",
                "Impact", "Open questions"]

# Placeholders copied from templates/requirement.md — any survivor means the agent skipped a field.
TEMPLATE_PLACEHOLDERS = [
    "REQ-000", "<title>", "<Why now", "<The unambiguous statement", "<testable criterion",
    "<explicitly excluded", "<Blast radius", "<anything the user deferred",
]

# The grill skill: "no 'fast/better/robust'" — rewrite into a number/observable or park it.
UNTESTABLE = re.compile(
    r"\b(fast|faster|quick|quickly|better|robust|user[- ]friendly|easy|easier|intuitive|"
    r"scalable|seamless(?:ly)?|performant|efficient(?:ly)?|modern|clean|nice|good|improved?)\b",
    re.I)

# A vague word is excused only by an actual threshold, not by any stray digit (e.g. "RFC 4180").
MEASURED = re.compile(
    r"(<=?|>=?|≤|≥|within|under|below|above|at most|at least|less than|more than|no more than)\s*\d"
    r"|\d[\d,.]*\s*(ms|s|sec|secs|seconds|minutes|%|percent|rows|records|requests|kb|mb|gb)", re.I)


# ----------------------------------------------------------------------------- markdown utils

def parse_frontmatter(text: str) -> dict[str, str]:
    m = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
    out: dict[str, str] = {}
    if not m:
        return out
    for line in m.group(1).splitlines():
        km = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if km:
            val = km.group(2).strip()
            if val.startswith('"'):
                end = re.search(r'(?<!\\)"', val[1:])              # first unescaped closing quote
                inner = val[1:1 + end.start()] if end else val[1:]
                val = inner.replace('\\"', '"').replace('\\\\', '\\')
            elif val.startswith("'"):
                val = val[1:val.rfind("'")] if val.rfind("'") > 0 else val[1:]
            else:
                val = re.sub(r'\s+#.*$', '', val).strip()           # strip trailing YAML comment
            out[km.group(1)] = val
    return out


def sections(text: str) -> dict[str, str]:
    """Map '## Heading' -> body (up to the next '## ')."""
    body = re.sub(r"^---\r?\n.*?\r?\n---\r?\n", "", text, count=1, flags=re.S)
    parts = re.split(r"^##\s+", body, flags=re.M)
    out = {}
    for p in parts[1:]:
        head, _, rest = p.partition("\n")
        out[head.strip()] = rest
    return out


def criteria(text: str) -> list[str]:
    sec = sections(text).get("Acceptance criteria", "")
    items, cur = [], None
    for line in sec.splitlines():
        m = re.match(r"^\s*-\s*\[[ xX]\]\s*(.*)$", line)
        if m:
            if cur is not None:
                items.append(cur)
            cur = m.group(1)
        elif cur is not None and line.strip() and re.match(r"^\s{2,}\S", line):
            cur += " " + line.strip()                      # continuation line
        elif cur is not None and not line.strip():
            items.append(cur)
            cur = None
    if cur is not None:
        items.append(cur)
    return items


# ----------------------------------------------------------------------------- REQ quality

def req_quality(text: str, *, expect_status: str | None = None, min_criteria: int = 2,
                must_match: list[str] | None = None,
                must_not_match: list[str] | None = None) -> list[Check]:
    c: list[Check] = []
    fm = parse_frontmatter(text)

    c.append(Check("frontmatter.id", bool(re.fullmatch(r"REQ-\d{3}", fm.get("id", ""))),
                   f"id={fm.get('id')!r}"))
    c.append(Check("frontmatter.goal", bool(fm.get("goal")), "goal is empty"))
    c.append(Check("frontmatter.created", bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", fm.get("created", ""))),
                   f"created={fm.get('created')!r}"))
    if expect_status:
        c.append(Check("frontmatter.status", fm.get("status") == expect_status,
                       f"status={fm.get('status')!r}, expected {expect_status!r} "
                       "(only the human flips draft -> approved)"))

    secs = sections(text)
    for s in REQ_SECTIONS:
        c.append(Check(f"section.{s}", s in secs and bool(secs[s].strip()),
                       "missing or empty"))

    left = [p for p in TEMPLATE_PLACEHOLDERS if p in text]
    c.append(Check("no_template_placeholders", not left, f"left over: {left}"))

    crit = criteria(text)
    c.append(Check("criteria.count", len(crit) >= min_criteria,
                   f"{len(crit)} acceptance criteria, need >= {min_criteria}"))
    vague = []
    for item in crit:
        for m in UNTESTABLE.finditer(item):
            if not MEASURED.search(item):                   # a real threshold makes it measurable
                vague.append(m.group(0))
    c.append(Check("criteria.testable", not vague, f"untestable words w/o a measure: {vague}"))
    c.append(Check("criteria.observable",
                   all(re.search(r"[`\d\"']|\b(returns?|shows?|displays?|contains?|equals?|"
                                 r"responds?|rejects?|logs?|renders?|emits?|redirects?|"
                                 r"fails?|exports?|creates?|is |are )\b", i, re.I)
                       for i in crit) if crit else False,
                   "a criterion names no observable behavior/value"))

    scope = secs.get("Out of scope", "")
    bullets = [l for l in scope.splitlines() if re.match(r"^\s*[-*]\s+\S", l)]
    c.append(Check("scope.has_exclusion", len(bullets) >= 1, "no explicit exclusion recorded"))

    refined = secs.get("Refined requirement", "")
    vague_ref = [m.group(0) for m in UNTESTABLE.finditer(refined) if not MEASURED.search(refined)]
    c.append(Check("refined.no_vague_words", not vague_ref, f"vague: {vague_ref}"))

    if fm.get("status") == "approved":
        oq = secs.get("Open questions", "")
        # The template says this must be empty before approval; a section that is explicitly
        # "(none ...)" or lists only items under a "Resolved ..." heading is fine.
        settled = re.search(r"\(none|resolved by|^none", oq, re.I | re.M)
        unresolved = [] if settled else [l for l in oq.splitlines()
                                         if re.match(r"^\s*[-*]\s+\S", l)]
        c.append(Check("approved.no_open_questions", not unresolved,
                       f"unresolved while approved: {unresolved[:3]}"))

    for pat in must_match or []:
        c.append(Check(f"must_match[{pat}]", bool(re.search(pat, text, re.I | re.S)),
                       "pattern absent from requirement"))
    for pat in must_not_match or []:
        c.append(Check(f"must_not_match[{pat}]", not re.search(pat, text, re.I | re.S),
                       "forbidden content present"))
    return c


# ----------------------------------------------------------------------------- design + tests

def design_doc(design: str, req: str, *, require_files: list[str] | None = None) -> list[Check]:
    c: list[Check] = []
    c.append(Check("design.nonempty", len(design.strip()) > 400, f"{len(design)} chars"))
    c.append(Check("design.open_questions_section",
                   bool(re.search(r"^#{1,3}\s+Open questions", design, re.M | re.I)),
                   "architect must resolve/declare open questions before code"))
    fm = parse_frontmatter(design)
    if fm:
        c.append(Check("design.req_link", "REQ-" in (fm.get("req", "") + design[:400]),
                       "design does not reference its REQ"))
    for f in require_files or []:
        c.append(Check(f"design.covers[{f}]", f in design, "file from REQ impact not in design"))
    n = len(criteria(req))
    c.append(Check("design.addresses_criteria", n == 0 or
                   len(re.findall(r"\bAC[- ]?\d+|acceptance criteri", design, re.I)) >= 1
                   or "acceptance" in design.lower(),
                   "design never ties back to the REQ's acceptance criteria"))
    return c


def test_traceability(test_cases: str, req: str) -> list[Check]:
    """One test case per acceptance criterion: each criterion's key tokens must appear in a TC."""
    c: list[Check] = []
    crit = criteria(req)
    tcs = set(re.findall(r"^#{2,4}\s+.*?\bTC-(\d+)", test_cases, re.M))      # "## TC-3" and "## REQ-001-TC-03"
    c.append(Check("tc.at_least_one_per_criterion", len(tcs) >= len(crit),
                   f"{len(tcs)} test cases for {len(crit)} criteria"))
    for i, item in enumerate(crit, 1):
        toks = [t for t in re.findall(r"`([^`]{3,})`", item)][:3]
        by_ref = bool(re.search(rf"\bAC[- ]?0*{i}\b|criterion[- ]0*{i}\b", test_cases, re.I))
        hit = by_ref or not toks or any(t in test_cases for t in toks)
        c.append(Check(f"tc.covers_criterion_{i}", hit, f"no TC mentions {toks}"))
    return c


# ----------------------------------------------------------------------------- stack proposal

def _norm(v) -> str:
    if isinstance(v, (list, tuple, set)):
        return " | ".join(_norm(x) for x in v).lower()
    return str(v or "").lower()


def stack_proposal(proposal: dict, golden: dict) -> tuple[list[Check], float]:
    """golden: {field: {"required": [[alias,...],...], "forbidden": [token,...]}}.

    Each required group and each forbidden token is one check. Score = recall of required groups,
    zeroed per forbidden hit (a hallucinated technology costs more than a missed one).
    """
    checks: list[Check] = []
    got_req = want_req = bad = 0
    for field, spec in golden.items():
        have = _norm(proposal.get(field))
        for group in spec.get("required", []):
            want_req += 1
            ok = any(a.lower() in have for a in group)
            got_req += ok
            checks.append(Check(f"{field}.has[{group[0]}]", ok, f"proposal.{field}={have!r}"))
        for tok in spec.get("forbidden", []):
            ok = tok.lower() not in have
            bad += (not ok)
            checks.append(Check(f"{field}.lacks[{tok}]", ok, f"hallucinated: {have!r}"))
    recall = got_req / want_req if want_req else 1.0
    score = max(0.0, recall - 0.25 * bad)
    return checks, score
