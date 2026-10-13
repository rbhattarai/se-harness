"""Layer 1: deterministic, offline, free. Runs the plugin's real scripts against table-driven cases.

Case kinds (datasets/l1_*.jsonl, one JSON object per line):
  hook             run a plugin script the way Claude Code would (JSON on stdin, cwd = fixture)
  newreq           run new-requirement.sh and check the scaffold it writes
  grader_selftest  run an eval grader on a golden artifact, optionally mutated, and require the
                   verdict to match - proves the graders themselves can fail
"""
from __future__ import annotations

import json
import re
from datetime import date, timedelta
from pathlib import Path

import graders
from common import (EVALS_DIR, GOLDEN_DIR, PLUGIN_DIR, SCRIPTS_DIR, Check, CaseResult, Sandbox,
                    apply_appends, apply_files, build_fixture, bash, finalize, git, posix, run)

REQ_TMPL = "---\nid: {id}\nstatus: {status}{comment}\ngoal: \"test\"\n---\n\n# {id}\n{body}\n"


# ----------------------------------------------------------------------------- shorthand

def write_reqs(root: Path, reqs: list[dict] | None) -> None:
    """req shorthand -> .harness/requirements/REQ-NNN.md (+ optional workspace-plan.md)."""
    for r in reqs or []:
        d = root / ".harness" / "requirements"
        d.mkdir(parents=True, exist_ok=True)
        nl = "\r\n" if r.get("crlf") else "\n"
        text = REQ_TMPL.format(id=r["id"], status=r["status"], comment=r.get("comment", ""),
                               body=r.get("body", ""))
        with open(d / f"{r['id']}.md", "w", encoding="utf-8", newline="") as fh:
            fh.write(text.replace("\n", nl))
        plan = r.get("plan")
        if plan is not None:
            pd = d / r["id"]
            pd.mkdir(parents=True, exist_ok=True)
            lines = ["---", f"req: {r['id']}"]
            if plan.get("integration") is not None:
                lines.append(f"integration: {plan['integration']}")
            lines += ["---", "", f"# Workspace plan - {r['id']}", ""]
            for comp, st in plan.get("rows", []):
                lines.append(f"- component: {comp} | status: {st} | owner: x | outcome: y "
                             f"| depends_on: - | evidence: -")
            (pd / "workspace-plan.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def payload(command: str) -> str:
    return json.dumps({"tool_name": "Bash", "tool_input": {"command": command}})


# ----------------------------------------------------------------------------- hook cases

def _dates(s: str) -> str:
    today = date.today()
    return s.replace("{today}", today.isoformat()).replace("{yesterday}", (today - timedelta(days=1)).isoformat())


def run_hook(case: dict) -> CaseResult:
    res = CaseResult(case["id"], 1, case.get("suite", "hook"), known_gap=case.get("known_gap", ""))
    script = SCRIPTS_DIR / case["script"]
    with Sandbox() as root:
        base_files = case.get("baseline_files")
        build_fixture(case.get("fixture", "empty"), root, init_git=case.get("git", True) and not base_files)
        if base_files:                                         # files that exist at the baseline commit
            apply_files(root, base_files)
            git(root, "init", "-q", "-b", "main")
            git(root, "add", "-A")
            git(root, "commit", "-q", "-m", "eval baseline")
        write_reqs(root, case.get("req"))
        apply_files(root, {_dates(k): v for k, v in (case.get("files") or {}).items()})
        apply_appends(root, case.get("appends"))
        for rel in case.get("crlf", []):                       # convert an existing file to CRLF
            f = root / rel
            raw = f.read_bytes().replace(chr(13).encode() + chr(10).encode(), chr(10).encode())
            f.write_bytes(raw.replace(chr(10).encode(), chr(13).encode() + chr(10).encode()))
        for rel in case.get("stage", []):
            git(root, "add", rel)
        if case.get("commit_edits"):
            git(root, "add", "-A")
            git(root, "commit", "-q", "-m", "edits")

        if "command" in case:
            stdin = payload(case["command"])
        else:
            stdin = case.get("stdin")
        cmd = [bash(), posix(script), *case.get("args", [])]
        env = None
        p = run(cmd, cwd=root / case.get("cwd", "."), stdin=stdin if stdin is not None else "", timeout=case.get("timeout", 30),
                env=env)
        for rel, needles in (case.get("expect_files") or {}).items():       # post-run file assertions
            f = root / _dates(rel)
            body = f.read_text(encoding="utf-8", errors="replace") if f.exists() else None
            res.checks.append(Check(f"file_exists[{rel}]", body is not None, "not created"))
            for n in _as_list(needles):
                res.checks.append(Check(f"file_contains[{rel}:{n[:24]}]", body is not None and n in body,
                                        (body or "")[:160]))
        for rel in case.get("expect_no_files", []):
            res.checks.append(Check(f"no_file[{rel}]", not (root / _dates(rel)).exists(), "was created"))

    exp = case.get("expect_exit", 0)
    res.checks.append(Check("exit_code", p.returncode == exp,
                            f"exit {p.returncode}, expected {exp}; stderr={p.stderr.strip()[:200]!r}"))
    for s in _as_list(case.get("stderr_contains")):
        res.checks.append(Check(f"stderr_contains[{s[:30]}]", s in p.stderr, p.stderr.strip()[:200]))
    for s in _as_list(case.get("stderr_lacks")):
        res.checks.append(Check(f"stderr_lacks[{s[:30]}]", s not in p.stderr, p.stderr.strip()[:200]))
    for s in _as_list(case.get("stdout_contains")):
        res.checks.append(Check(f"stdout_contains[{s[:30]}]", s in p.stdout, p.stdout[:200]))
    for s in _as_list(case.get("stdout_lacks")):
        res.checks.append(Check(f"stdout_lacks[{s[:30]}]", s not in p.stdout, "present"))
    if "stdout_max_bytes" in case:
        n = len(p.stdout.encode("utf-8"))
        res.checks.append(Check("stdout_max_bytes", n <= case["stdout_max_bytes"],
                                f"{n} bytes > {case['stdout_max_bytes']}"))
    order = case.get("stdout_order")
    if order:
        pos = [p.stdout.find(_dates(x)) for x in order]
        res.checks.append(Check("stdout_order", all(i >= 0 for i in pos) and pos == sorted(pos),
                                f"positions {pos} for {order}"))
    if "stderr_max_chars" in case:
        n = len(p.stderr.strip())
        res.checks.append(Check("stderr_max_chars", n <= case["stderr_max_chars"],
                                f"{n} chars > {case['stderr_max_chars']}"))
    if "stderr_first_line_matches" in case:
        first = (p.stderr.strip().splitlines() or [""])[0]
        res.checks.append(Check("stderr_first_line", bool(re.search(case["stderr_first_line_matches"], first)),
                                first[:200]))
    return finalize(res)


def _as_list(v) -> list[str]:
    return [] if v is None else ([v] if isinstance(v, str) else list(v))


# ----------------------------------------------------------------------------- newreq

def _unyaml(s: str) -> str:
    return s.replace('\\"', '"').replace("\\\\", "\\")


def run_newreq(case: dict) -> CaseResult:
    res = CaseResult(case["id"], 1, "newreq", known_gap=case.get("known_gap", ""))
    script = SCRIPTS_DIR / "new-requirement.sh"
    with Sandbox() as root:
        build_fixture("empty", root, init_git=False)
        for rid in case.get("existing", []):
            (root / ".harness" / "requirements").mkdir(parents=True, exist_ok=True)
            (root / ".harness" / "requirements" / f"{rid}.md").write_text("x", encoding="utf-8")
        p = run([bash(), posix(script), case["goal"]], cwd=root)
        res.checks.append(Check("exit_code", p.returncode == 0, p.stderr.strip()[:200]))
        out = p.stdout.strip().replace("\\", "/")
        res.checks.append(Check("path", out.endswith(case["expect_file"]),
                                f"printed {out!r}, expected ...{case['expect_file']}"))
        f = root / case["expect_file"]
        if f.exists():
            text = f.read_text(encoding="utf-8")
            fm = graders.parse_frontmatter(text)
            res.checks.append(Check("id", fm.get("id") == case["expect_id"], f"id={fm.get('id')!r}"))
            res.checks.append(Check("status_draft", fm.get("status") == "draft", fm.get("status", "")))
            res.checks.append(Check("goal_roundtrip", fm.get("goal", "") == case["goal"],
                                    f"wrote {fm.get('goal')!r}"))
            res.checks.append(Check("no_placeholder_id", "REQ-000" not in text, "REQ-000 survived"))
            res.checks.append(Check("artifact_dir",
                                    (f.parent / case["expect_id"]).is_dir(), "REQ-NNN/ dir missing"))
        else:
            res.checks.append(Check("file_exists", False, str(f)))
    return finalize(res)


# ----------------------------------------------------------------------------- grader self-tests

def _mutate(text: str, muts: list[dict]) -> str:
    for m in muts or []:
        if "replace" in m:
            old, new = m["replace"]
            if old not in text:
                raise ValueError(f"mutation target not found: {old[:40]!r}")
            text = text.replace(old, new)
        elif "drop_section" in m:
            text = re.sub(rf"^## {re.escape(m['drop_section'])}\b.*?(?=^## |\Z)", "", text,
                          flags=re.S | re.M)
        elif "truncate" in m:
            text = text[: m["truncate"]]
        elif "append" in m:
            text += m["append"]
        elif "regex_delete" in m:
            text = re.sub(m["regex_delete"], "", text, flags=re.S | re.M)
        else:
            raise ValueError(f"unknown mutation {m}")
    return text


def run_grader_selftest(case: dict) -> CaseResult:
    res = CaseResult(case["id"], 1, "grader_selftest", known_gap=case.get("known_gap", ""))
    art = (EVALS_DIR / case["artifact"]).read_text(encoding="utf-8")
    try:
        art = _mutate(art, case.get("mutations"))
    except ValueError as e:
        res.checks.append(Check("mutation", False, str(e)))
        return finalize(res)
    g = case["grader"]
    kw = case.get("args", {})
    if g == "req_quality":
        checks = graders.req_quality(art, **kw)
    elif g == "design_doc":
        req = (EVALS_DIR / case["req"]).read_text(encoding="utf-8")
        checks = graders.design_doc(art, req, **kw)
    elif g == "test_traceability":
        req = (EVALS_DIR / case["req"]).read_text(encoding="utf-8")
        checks = graders.test_traceability(art, req)
    elif g == "stack_proposal":
        golden = json.loads((GOLDEN_DIR / case["golden"]).read_text(encoding="utf-8"))["fields"]
        checks, _ = graders.stack_proposal(json.loads(art), golden)
    else:
        res.checks.append(Check("grader", False, f"unknown grader {g}"))
        return finalize(res)

    failed = {c.name for c in checks if not c.ok}
    if case["expect"] == "pass":
        res.checks.append(Check("grader_passes_good_input", not failed, f"unexpected failures: {sorted(failed)}"))
    else:
        want = set(case.get("expect_failed", []))
        res.checks.append(Check("grader_flags_bad_input", bool(failed), "grader passed a known-bad artifact"))
        if want:
            res.checks.append(Check("grader_flags_the_right_check", want <= failed,
                                    f"expected {sorted(want)} among failures, got {sorted(failed)}"))
    return finalize(res)


# ----------------------------------------------------------------------------- hidden-test validity

def run_reference_check(case: dict) -> CaseResult:
    """The hidden acceptance tests must FAIL on the untouched repo and PASS on the reference solution.

    Without this, a Layer-3 'tests pass' score could be meaningless (tests that never fail) or
    unreachable (tests that no correct solution satisfies).
    """
    import reference as ref
    res = CaseResult(case["id"], 1, "hidden_tests", known_gap=case.get("known_gap", ""))
    if not ref.node_available():
        res.status, res.note = "skip", "node or a local node_modules checkout not found (offline: nothing is installed)"
        return res
    for solved in (False, True):
        with Sandbox() as root:
            build_fixture("demo-loan-app+harness", root)
            if not ref.link_deps(root):
                res.status, res.note = "skip", "could not link node_modules (symlink/junction unavailable)"
                return res
            if solved:
                ref.apply_reference(root)
                for unit in ref.UNITS:                      # lint + existing suite BEFORE hidden tests are added
                    lint = ref.eslint(root / unit)
                    res.checks.append(Check(f"reference is lint-clean [{unit}]", lint.returncode == 0,
                                            (lint.stdout + lint.stderr)[-400:]))
                    full = ref.vitest(root / unit)
                    res.checks.append(Check(f"reference keeps existing suite green [{unit}]", full.returncode == 0,
                                            (full.stdout + full.stderr)[-400:]))
            ref.install_hidden_tests(root)
            for unit in ref.UNITS:
                hidden = f"test/zz-{'loan' if unit == 'loan-webapp' else 'lendor'}.hidden.test.ts"
                p = ref.vitest(root / unit, hidden)
                if solved:
                    res.checks.append(Check(f"reference passes hidden [{unit}]", p.returncode == 0,
                                            (p.stdout + p.stderr)[-400:]))
                else:
                    res.checks.append(Check(f"hidden tests fail on unsolved repo [{unit}]", p.returncode != 0,
                                            "hidden tests passed without any implementation"))
    return finalize(res)


# ----------------------------------------------------------------------------- pipeline self-test

def run_pipeline_selftest(case: dict) -> CaseResult:
    """Run a Layer 2/3 case against a scripted stand-in for `claude` (lib/fake_claude.py).

    oracle must PASS, null must FAIL, reckless must FAIL the gate case: proves the whole model-backed
    pipeline (prompt -> transcript parse -> artifact graders -> hidden tests -> mutation runner ->
    aggregation) can tell a perfect agent from an empty or a rule-breaking one, without spending a cent.
    Runs sequentially (the stand-in is selected through process environment).
    """
    import os
    import sys
    from types import SimpleNamespace
    import l23
    res = CaseResult(case["id"], 1, "pipeline", known_gap=case.get("known_gap", ""))
    target = None
    for f in ("l2_artifacts.jsonl", "l3_goal_loop.jsonl"):
        from common import DATASETS_DIR, load_jsonl
        for c in load_jsonl(DATASETS_DIR / f):
            if c["id"] == case["target"]:
                target = c
    if target is None:
        res.checks.append(Check("target_exists", False, case["target"]))
        return finalize(res)
    if target["kind"] in ("unit_tester",) or target.get("scenario") == "happy":
        import reference as ref
        if not ref.node_available():
            res.status, res.note = "skip", "node or a local node_modules checkout not found"
            return res
    fake = str(Path(__file__).resolve().parent / "fake_claude.py")
    old = {k: os.environ.get(k) for k in ("EVAL_CLAUDE_BIN", "EVAL_FAKE_MODE")}
    os.environ["EVAL_CLAUDE_BIN"] = json.dumps([sys.executable, "-I", fake])
    os.environ["EVAL_FAKE_MODE"] = case["mode"]
    args = SimpleNamespace(samples=1, dry_run=False, keep=False, model=None, judge_model=None,
                           budget=1.0, no_judge=True)
    try:
        out = l23.RUNNERS[target["kind"]](target, args)
    finally:
        for k, v in old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    want = case["expect"]
    got = "pass" if out.status in ("pass",) else "fail"
    res.checks.append(Check(f"{case['mode']} agent scores as {want}", got == want,
                            f"status={out.status} score={out.score} failed={[c.name for c in out.failed_checks][:5]}"))
    if case.get("expect_failed"):
        names = {c.name for c in out.failed_checks}
        res.checks.append(Check("the right checks fired", set(case["expect_failed"]) <= names,
                                f"expected {case['expect_failed']} among {sorted(names)[:8]}"))
    if case["mode"] == "oracle" and want == "pass":
        res.checks.append(Check("oracle scores 1.0", (out.score or 0) >= 0.999, f"score={out.score} soft={out.note}"))
    return finalize(res)


# ----------------------------------------------------------------------------- driver

RUNNERS = {"hook": run_hook, "newreq": run_newreq, "grader_selftest": run_grader_selftest,
           "reference_check": run_reference_check, "pipeline_selftest": run_pipeline_selftest}


def run_case(case: dict) -> CaseResult:
    kind = case.get("kind", "hook")
    try:
        return RUNNERS[kind](case)
    except Exception as e:  # a crashing case must not take the run down
        r = CaseResult(case.get("id", "?"), 1, kind, status="error", note=f"{type(e).__name__}: {e}")
        r.checks.append(Check("harness_error", False, r.note))
        return finalize(r)
