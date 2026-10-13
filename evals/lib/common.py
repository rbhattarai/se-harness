"""Shared plumbing for the eval harness: paths, bash discovery, fixtures, JSONL, results.

Standard library only (matches the repo's no-dependency stance).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

EVALS_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = EVALS_DIR.parent
PLUGIN_DIR = REPO_ROOT / "plugins" / "se-harness"
SCRIPTS_DIR = PLUGIN_DIR / "scripts"
DATASETS_DIR = EVALS_DIR / "datasets"
GOLDEN_DIR = EVALS_DIR / "golden"
FIXTURES_DIR = EVALS_DIR / "fixtures"
CACHE_DIR = FIXTURES_DIR / ".cache"
BASELINES_DIR = EVALS_DIR / "baselines"
RESULTS_DIR = EVALS_DIR / "results"


# --------------------------------------------------------------------------- bash

def find_bash() -> str:
    """Git Bash on Windows (never the WSL launcher in System32), else PATH bash."""
    env = os.environ.get("EVAL_BASH")
    if env:
        return env
    if os.name == "nt":
        for cand in (
            r"C:\Program Files\Git\bin\bash.exe",
            r"C:\Program Files\Git\usr\bin\bash.exe",
            r"C:\Program Files (x86)\Git\bin\bash.exe",
        ):
            if Path(cand).exists():
                return cand
        found = shutil.which("bash")
        if found and "system32" not in found.lower():
            return found
        sys.exit("ERROR: Git Bash not found; set EVAL_BASH to a bash executable")
    return shutil.which("bash") or sys.exit("ERROR: bash not found")


BASH = None


def bash() -> str:
    global BASH
    if BASH is None:
        BASH = find_bash()
    return BASH


def posix(p: Path | str) -> str:
    return Path(p).as_posix()


# --------------------------------------------------------------------------- jsonl

def load_jsonl(path: Path) -> list[dict]:
    rows = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as e:
            sys.exit(f"ERROR: {path.name}:{n}: {e}")
    return rows


# --------------------------------------------------------------------------- results

@dataclass
class Check:
    name: str
    ok: bool
    detail: str = ""


@dataclass
class CaseResult:
    id: str
    layer: int
    suite: str
    status: str = "pass"          # pass | fail | xfail | xpass | error | skip
    checks: list[Check] = field(default_factory=list)
    score: float | None = None    # 0..1 for graded (L2/L3) cases
    samples: list[float] = field(default_factory=list)
    cost_usd: float = 0.0
    note: str = ""
    known_gap: str = ""

    @property
    def failed_checks(self) -> list[Check]:
        return [c for c in self.checks if not c.ok]

    def to_json(self) -> dict:
        return {
            "id": self.id, "layer": self.layer, "suite": self.suite, "status": self.status,
            "score": self.score, "samples": self.samples, "cost_usd": round(self.cost_usd, 4),
            "known_gap": self.known_gap, "note": self.note,
            "failed": [{"name": c.name, "detail": c.detail} for c in self.failed_checks],
        }


def finalize(res: CaseResult) -> CaseResult:
    """Fold known_gap into the status: a failing known gap is xfail, a passing one is xpass."""
    failing = bool(res.failed_checks) or res.status in ("fail", "error")
    if res.known_gap:
        res.status = "xfail" if failing else "xpass"
    elif res.status not in ("skip", "error"):
        res.status = "fail" if failing else "pass"
    return res


# --------------------------------------------------------------------------- fixtures

def run(cmd: list[str], cwd: Path | None = None, stdin: str | None = None,
        timeout: int = 60, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, input=stdin, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout, env=env)


def git(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    return run(["git", "-c", "user.name=eval", "-c", "user.email=eval@example.invalid",
                "-c", "commit.gpgsign=false", "-c", "core.autocrlf=false", *args], cwd=cwd)


def cache_path(name: str) -> Path:
    return CACHE_DIR / name


def build_fixture(name: str, dest: Path, init_git: bool = True) -> Path:
    """Materialize fixture `name` into `dest`: cached source snapshot + optional overlay.

    A fixture name is `<snapshot>[+<overlay>]`, e.g. `demo-loan-app+harness`. Snapshots live in
    evals/fixtures/.cache (built by `run-evals.sh fixtures`); overlays are committed under
    evals/fixtures/overlays/<snapshot>-<overlay>. The special name `empty` is a bare directory.
    """
    dest.mkdir(parents=True, exist_ok=True)
    if name != "empty":
        snap, _, overlay = name.partition("+")
        src = cache_path(snap)
        if not src.is_dir():
            sys.exit(f"ERROR: fixture snapshot '{snap}' not built. Run: bash evals/run-evals.sh fixtures")
        shutil.copytree(src, dest, dirs_exist_ok=True)
        if overlay:
            ov = FIXTURES_DIR / "overlays" / f"{snap}-{overlay}"
            if not ov.is_dir():
                sys.exit(f"ERROR: overlay {ov} missing")
            shutil.copytree(ov, dest, dirs_exist_ok=True)
    if init_git:
        git(dest, "init", "-q", "-b", "main")
        git(dest, "add", "-A")
        git(dest, "commit", "-q", "-m", "eval baseline", "--allow-empty")
    return dest


def apply_files(root: Path, files: dict | None) -> None:
    """files: {relpath: content | null}. null deletes. Content is written with LF endings."""
    for rel, content in (files or {}).items():
        p = root / rel
        if content is None:
            p.unlink(missing_ok=True)
            continue
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="") as fh:
            fh.write(content)


def apply_appends(root: Path, appends: dict | None) -> None:
    for rel, content in (appends or {}).items():
        with open(root / rel, "a", encoding="utf-8", newline="") as fh:
            fh.write(content)


class Sandbox:
    """Throwaway directory; removes node_modules links before rmtree so a junction is never followed."""

    def __init__(self, keep: bool = False):
        self.keep = keep
        self.path = Path(tempfile.mkdtemp(prefix="se-eval-"))

    def __enter__(self) -> Path:
        return self.path

    def __exit__(self, *exc):
        if not self.keep:
            cleanup(self.path)


def cleanup(path: Path) -> None:
    for nm in path.rglob("node_modules"):
        try:
            if nm.is_symlink() or (os.name == "nt" and os.path.isjunction(nm)):
                os.unlink(nm) if nm.is_symlink() else os.rmdir(nm)
        except OSError:
            pass

    def onerr(func, p, _exc):
        try:
            os.chmod(p, 0o700)
            func(p)
        except OSError:
            pass

    shutil.rmtree(path, onerror=onerr)


def link_node_modules(unit_dir: Path, source: Path) -> bool:
    """Offline dependency access: junction/symlink an existing node_modules (no network)."""
    if not source.is_dir():
        return False
    target = unit_dir / "node_modules"
    try:
        os.symlink(source, target, target_is_directory=True)
        return True
    except OSError:
        pass
    if os.name == "nt":
        r = subprocess.run(["cmd", "/c", "mklink", "/J", str(target), str(source)],
                           capture_output=True, text=True)
        if r.returncode == 0:
            return True
    return False
