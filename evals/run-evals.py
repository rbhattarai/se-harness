#!/usr/bin/env python3
"""se-harness eval runner.  See evals/README.md.

  run-evals.sh                         Layer 1 (offline, free)
  run-evals.sh --layer 2               Layer 2 (model-backed, single-agent artifacts)
  run-evals.sh --layer 3               Layer 3 (headless /harness-goal end to end)
  run-evals.sh --layer all --compare   everything, diffed against committed baselines
  run-evals.sh fixtures [--force]      (re)build the pinned source snapshots
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))

from common import (BASELINES_DIR, DATASETS_DIR, RESULTS_DIR, CaseResult, load_jsonl)  # noqa: E402

LAYER1_FILES = ["l1_gates.jsonl", "l1_contracts.jsonl", "l1_hooks.jsonl", "l1_scaffold.jsonl",
                "l1_grader_selftests.jsonl", "l1_pipeline.jsonl"]
SEQUENTIAL_KINDS = {"pipeline_selftest"}      # they select the stand-in CLI through process environment
LAYER2_FILE = "l2_artifacts.jsonl"
LAYER3_FILE = "l3_goal_loop.jsonl"

SYMBOL = {"pass": "PASS ", "fail": "FAIL ", "xfail": "xfail", "xpass": "XPASS", "error": "ERROR", "skip": "skip "}


def select(cases: list[dict], args) -> list[dict]:
    out = cases
    if args.suite:
        out = [c for c in out if {c.get("suite"), c.get("kind"), c["id"].split("/")[0]} & set(args.suite)]
    if args.case:
        out = [c for c in out if any(s in c["id"] for s in args.case)]
    return out


def run_layer1(args) -> list[CaseResult]:
    import l1
    cases: list[dict] = []
    for f in LAYER1_FILES:
        p = DATASETS_DIR / f
        if p.exists():
            cases += load_jsonl(p)
    cases = select(cases, args)
    if not cases:
        return []
    t0 = time.time()
    par = [c for c in cases if c.get("kind") not in SEQUENTIAL_KINDS]
    seq = [c for c in cases if c.get("kind") in SEQUENTIAL_KINDS]
    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        results = list(ex.map(l1.run_case, par))
    results += [l1.run_case(c) for c in seq]
    print(f"  layer 1: {len(results)} cases in {time.time() - t0:.1f}s")
    return results


def run_layer(n: int, args) -> list[CaseResult]:
    import l23
    f = DATASETS_DIR / (LAYER2_FILE if n == 2 else LAYER3_FILE)
    cases = select(load_jsonl(f), args) if f.exists() else []
    return l23.run_cases(n, cases, args) if cases else []


# ----------------------------------------------------------------------------- reporting

def report(results: list[CaseResult], verbose: bool) -> None:
    by_status: dict[str, int] = {}
    for r in results:
        by_status[r.status] = by_status.get(r.status, 0) + 1
    print()
    for r in results:
        show = r.status in ("fail", "error", "xpass") or verbose
        if r.status == "xfail" and not verbose:
            continue
        if not show and r.status == "pass":
            continue
        sc = f" score={r.score:.2f}" if r.score is not None else ""
        print(f"  {SYMBOL[r.status]} {r.id}{sc}")
        if r.status in ("fail", "error"):
            for c in r.failed_checks[:6]:
                print(f"         - {c.name}: {c.detail[:160]}")
        if r.status == "xpass":
            print(f"         known_gap now passes - remove the flag: {r.known_gap[:140]}")
        if r.status == "xfail" and verbose:
            print(f"         known gap: {r.known_gap[:140]}")
    gaps = [r for r in results if r.status == "xfail"]
    if gaps and not verbose:
        print(f"\n  {len(gaps)} known gaps (xfail) hidden - rerun with -v to list them")
    total_cost = sum(r.cost_usd for r in results)
    parts = [f"{by_status.get(k, 0)} {k}" for k in ("pass", "fail", "error", "xfail", "xpass", "skip") if by_status.get(k)]
    print(f"\n  {len(results)} cases: " + ", ".join(parts) + (f"   (model spend ${total_cost:.2f})" if total_cost else ""))


def compare_baseline(results: list[CaseResult], layer_key: str, tol: float) -> list[str]:
    path = BASELINES_DIR / f"{layer_key}.json"
    if not path.exists():
        return [f"no baseline at {path.name} - run with --update-baseline once you trust the numbers"]
    base = json.loads(path.read_text(encoding="utf-8"))
    problems = []
    for r in results:
        b = base.get(r.id)
        if b is None:
            continue
        if b["status"] == "pass" and r.status != "pass":
            problems.append(f"regression: {r.id} was pass, now {r.status}")
        if b.get("score") is not None and r.score is not None and r.score < b["score"] - tol:
            problems.append(f"regression: {r.id} score {b['score']:.2f} -> {r.score:.2f} (tol {tol})")
    return problems


def write_baseline(results: list[CaseResult], layer_key: str) -> None:
    BASELINES_DIR.mkdir(exist_ok=True)
    data = {r.id: {"status": r.status, "score": r.score} for r in results}
    (BASELINES_DIR / f"{layer_key}.json").write_text(json.dumps(data, indent=1, sort_keys=True) + "\n",
                                                    encoding="utf-8")
    print(f"  baseline written: baselines/{layer_key}.json ({len(data)} cases)")


def main() -> int:
    ap = argparse.ArgumentParser(prog="run-evals")
    ap.add_argument("command", nargs="?", default="run", choices=["run", "fixtures"])
    ap.add_argument("--layer", default="1", help="1, 2, 3 or all (default 1)")
    ap.add_argument("--suite", action="append", help="only this suite (repeatable)")
    ap.add_argument("--case", action="append", help="only cases whose id contains this (repeatable)")
    ap.add_argument("--samples", type=int, default=3, help="runs per model-backed case (default 3)")
    ap.add_argument("--model", default=None, help="model alias/name for the agent under test")
    ap.add_argument("--judge-model", default=None, help="model for LLM-judge rubrics (default: same as --model)")
    ap.add_argument("--budget", type=float, default=2.0, help="max USD per model-backed run (default 2.0)")
    ap.add_argument("--max-turns", type=int, default=40)
    ap.add_argument("--jobs", type=int, default=8, help="parallel layer-1 cases")
    ap.add_argument("--dry-run", action="store_true", help="layers 2/3: build the fixture and print the command; no model call")
    ap.add_argument("--no-judge", action="store_true", help="skip LLM-judge questions (programmatic checks only)")
    ap.add_argument("--keep", action="store_true", help="keep the sandbox directories for inspection")
    ap.add_argument("--compare", action="store_true", help="fail on regression against baselines/")
    ap.add_argument("--tolerance", type=float, default=0.10, help="allowed score drop vs baseline")
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if args.command == "fixtures":
        sys.argv = [sys.argv[0]] + (["--force"] if args.force else [])
        sys.path.insert(0, str(Path(__file__).resolve().parent / "fixtures"))
        import make
        make.main()
        return 0

    layers = [1, 2, 3] if args.layer == "all" else [int(args.layer)]
    exit_code = 0
    all_results: list[CaseResult] = []
    for n in layers:
        print(f"== Layer {n} ==")
        results = run_layer1(args) if n == 1 else run_layer(n, args)
        all_results += results
        report(results, args.verbose)
        key = f"layer{n}"
        if args.update_baseline and results and not args.dry_run:
            write_baseline(results, key)
        if args.compare and results and not args.dry_run:
            for p in compare_baseline(results, key, args.tolerance):
                print("  !!", p)
                if p.startswith("regression"):
                    exit_code = 1
        if any(r.status in ("fail", "error", "xpass") for r in results):
            exit_code = 1

    if all_results and not args.dry_run:
        RESULTS_DIR.mkdir(exist_ok=True)
        out = RESULTS_DIR / f"run-{datetime.now():%Y%m%d-%H%M%S}.json"
        out.write_text(json.dumps([r.to_json() for r in all_results], indent=1) + "\n", encoding="utf-8")
        print(f"\n  results: {out}")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
