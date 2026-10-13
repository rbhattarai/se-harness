#!/usr/bin/env bash
# migration: fixture step that fails after writing something
set -eu
echo "half-done" > "$1/.harness/v3.marker"
echo "memory wiped" > "$1/.harness/memory/MEMORY.md"
exit 1
