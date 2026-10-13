#!/usr/bin/env bash
# Thin wrapper: pick a working python and hand everything to run-evals.py.
# usage: bash evals/run-evals.sh [fixtures | --layer 1|2|3|all] [options]   (see --help)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for c in python3 python; do
  if "$c" -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >/dev/null 2>&1; then
    exec "$c" -I "$HERE/run-evals.py" "$@"
  fi
done
echo "ERROR: python >= 3.10 not found" >&2
exit 2
