#!/usr/bin/env bash
# migration: fixture step 1->2 (adds a file, re-renders the AGENTS.md block)
set -eu
PROJ="$1"
echo "v2" > "$PROJ/.harness/v2.marker"
printf 'v2 generated text\n' > "$PROJ/.harness/.blk"
bash "$HARNESS_RENDER_BLOCK" $HARNESS_RENDER_FLAGS "$PROJ/AGENTS.md" "$PROJ/.harness/.blk" >/dev/null
rm -f "$PROJ/.harness/.blk"
