#!/usr/bin/env bash
# migration: fixture step 2->3 (adds a file)
set -eu
echo "v3" > "$1/.harness/v3.marker"
