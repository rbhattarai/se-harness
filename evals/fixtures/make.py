"""Build pinned fixture snapshots into evals/fixtures/.cache (local, offline, git-ignored)."""
from __future__ import annotations

import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from common import CACHE_DIR, FIXTURES_DIR, REPO_ROOT  # noqa: E402


def build(name: str, spec: dict, force: bool) -> None:
    env_key = "EVAL_SRC_" + name.upper().replace("-", "_")
    src = Path(os.environ.get(env_key) or (REPO_ROOT / spec["path"])).resolve()
    dest = CACHE_DIR / name
    if dest.exists() and not force:
        print(f"  {name}: cached ({dest})")
        return
    if not (src / ".git").exists():
        print(f"  {name}: SKIP - no git checkout at {src} (set {env_key})")
        return
    sha = spec["sha"]
    r = subprocess.run(["git", "-C", str(src), "archive", "--format=tar", sha],
                       capture_output=True)
    if r.returncode != 0:
        print(f"  {name}: SKIP - git archive {sha} failed: {r.stderr.decode(errors='replace').strip()}")
        return
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(r.stdout)) as tf:
        tf.extractall(dest, filter="data")
    removed = 0
    for pat in spec.get("remove", []):
        for p in sorted(dest.glob(pat), reverse=True):
            if p.is_dir():
                shutil.rmtree(p, ignore_errors=True)
            else:
                p.unlink(missing_ok=True)
            removed += 1
    nfiles = sum(1 for _ in dest.rglob("*") if _.is_file())
    print(f"  {name}: {nfiles} files @ {sha[:9]} ({removed} paths removed) -> {dest}")


def main() -> None:
    force = "--force" in sys.argv
    sources = json.loads((FIXTURES_DIR / "sources.json").read_text(encoding="utf-8"))
    print("Building fixture snapshots (offline, git archive):")
    for name, spec in sources.items():
        if name.startswith("_"):
            continue
        build(name, spec, force)


if __name__ == "__main__":
    main()
