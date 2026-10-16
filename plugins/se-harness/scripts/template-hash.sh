#!/usr/bin/env bash
# template-hash.sh — fingerprint the plugin's templates for drift detection (Phase 6).
# Prints "name<TAB>hash" per template file, stable order. /harness-sync compares this
# against the template_hashes recorded in .harness/agentstack.lock to distinguish
# "templates changed upstream (re-render needed)" from "profile changed locally".

set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Locate templates: the plugin's own dir (marketplace install / repo checkout), an explicit
# override, or the sibling framework clone Copilot setups use (tools/harness/ -> ../se-harness).
TPL_DIR=""
for cand in "${SE_HARNESS_TEMPLATES:-}" "$SCRIPT_DIR/../templates" "$SCRIPT_DIR/templates" "$SCRIPT_DIR/../../../se-harness/plugins/se-harness/templates"; do
  [ -n "$cand" ] && [ -d "$cand" ] && { TPL_DIR="$cand"; break; }
done
[ -n "$TPL_DIR" ] || { echo "templates dir not found (looked next to the plugin; set SE_HARNESS_TEMPLATES to override)" >&2; exit 1; }

HASHER="md5sum"
command -v md5sum >/dev/null 2>&1 || HASHER="shasum -a 256"

find "$TPL_DIR" -type f | sort | while IFS= read -r f; do
  rel="${f#"$TPL_DIR"/}"
  h=$($HASHER "$f" | awk '{print $1}')
  printf '%s\t%s\n' "$rel" "$h"
done
