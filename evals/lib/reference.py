"""Reference solution + node helpers for the demo-loan-app CSV-export task (REQ-001).

The reference exists to prove the hidden acceptance tests are *valid*: they pass against a correct
implementation and fail against none. It is also the base for the unit-tester mutation eval.
Offline only: node_modules is linked from a local checkout, never installed.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from common import EVALS_DIR, REPO_ROOT, link_node_modules

UNITS = ("loan-webapp", "lending-webapp")
HIDDEN_DIR = EVALS_DIR / "hidden" / "csv-export"

LOAN_ROUTE_TAIL = '''
const LOAN_COLUMNS = ["id", "applicantName", "amount", "status", "approver", "createdAt"] as const;

function csvField(value: unknown): string {
    const s = String(value ?? "");
    return /[",\\r\\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

router.get("/export.csv", (req: Request, res: Response) => {
    const rows = readLoans().map((l) => LOAN_COLUMNS.map((c) => csvField(l[c])).join(","));
    const body = [LOAN_COLUMNS.join(","), ...rows].join("\\n") + "\\n";
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader(
        "Content-Disposition",
        `attachment; filename="loans-${new Date().toISOString().slice(0, 10)}.csv"`,
    );
    res.send(body);
});
'''

LENDOR_ROUTE_TAIL = '''
const APPROVER_COLUMNS = ["id", "name", "createdAt"] as const;

function csvField(value: unknown): string {
    const s = String(value ?? "");
    return /[",\\r\\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

router.get("/export.csv", (req: Request, res: Response) => {
    const rows = readApprovers().map((a) => APPROVER_COLUMNS.map((c) => csvField(a[c])).join(","));
    const body = [APPROVER_COLUMNS.join(","), ...rows].join("\\n") + "\\n";
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader(
        "Content-Disposition",
        `attachment; filename="loan-approvers-${new Date().toISOString().slice(0, 10)}.csv"`,
    );
    res.send(body);
});
'''


def apply_reference(root: Path) -> None:
    """Write the reference CSV export into a demo-loan-app fixture (routes + views)."""
    loan = root / "loan-webapp/src/routes/loan.ts"
    s = loan.read_text(encoding="utf-8")
    assert "export default router;" in s
    loan.write_text(s.replace("export default router;", LOAN_ROUTE_TAIL.strip("\n") + "\n\nexport default router;"),
                    encoding="utf-8")
    lend = root / "lending-webapp/src/routes/lendor.ts"
    s = lend.read_text(encoding="utf-8")
    lend.write_text(s.replace("export default router;", LENDOR_ROUTE_TAIL.strip("\n") + "\n\nexport default router;"),
                    encoding="utf-8")

    v = root / "loan-webapp/src/views/loan.ejs"
    s = v.read_text(encoding="utf-8")
    old = '<i class="bi bi-plus-lg me-1"></i> New Loan\n            </button>'
    assert old in s
    v.write_text(s.replace(old, old + '\n            <a class="btn btn-outline-secondary" href="/loan/export.csv">Export CSV</a>'),
                 encoding="utf-8")
    v = root / "lending-webapp/src/views/lendor.ejs"
    s = v.read_text(encoding="utf-8")
    old = '<i class="bi bi-person-plus me-1"></i> Add New Loan Approver\n            </button>'
    assert old in s
    v.write_text(s.replace(old, old + '\n            <a class="btn btn-outline-secondary" href="/lendor/export.csv">Export CSV</a>'),
                 encoding="utf-8")


def install_hidden_tests(root: Path) -> list[Path]:
    out = []
    for unit, name in (("loan-webapp", "loan.hidden.test.ts"), ("lending-webapp", "lendor.hidden.test.ts")):
        dst = root / unit / "test" / f"zz-{name}"
        shutil.copyfile(HIDDEN_DIR / name, dst)
        out.append(dst)
    return out


# --------------------------------------------------------------------------- node (offline)

def node_modules_source(unit: str) -> Path:
    env = os.environ.get("EVAL_NODE_MODULES_" + unit.upper().replace("-", "_"))
    if env:
        return Path(env)
    src = os.environ.get("EVAL_SRC_DEMO_LOAN_APP")
    base = Path(src) if src else (REPO_ROOT / ".." / "demo-loan-app")
    return (base / unit / "node_modules").resolve()


def link_deps(root: Path) -> bool:
    ok = True
    for unit in UNITS:
        ok &= link_node_modules(root / unit, node_modules_source(unit))
    return ok


def node_available() -> bool:
    return shutil.which("node") is not None and all(node_modules_source(u).is_dir() for u in UNITS)


def run_node(unit_dir: Path, script_rel: str, *args: str, timeout: int = 240) -> subprocess.CompletedProcess:
    env = dict(os.environ, CI="1", NO_COLOR="1", npm_config_offline="true")
    return subprocess.run([shutil.which("node"), script_rel, *args], cwd=unit_dir, capture_output=True,
                          text=True, encoding="utf-8", errors="replace", timeout=timeout, env=env)


def vitest(unit_dir: Path, *files: str) -> subprocess.CompletedProcess:
    return run_node(unit_dir, "node_modules/vitest/vitest.mjs", "run", "--reporter=dot", *files)


def eslint(unit_dir: Path) -> subprocess.CompletedProcess:
    return run_node(unit_dir, "node_modules/eslint/bin/eslint.js", ".")
