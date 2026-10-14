#!/usr/bin/env bash
# langfuse-otel-env.sh — print the `export` lines that make GitHub Copilot CLI send its OpenTelemetry
# traces to a Langfuse instance. Copilot has no Langfuse plugin: it exports OTel natively and Langfuse
# is an OTLP backend (https://langfuse.com/integrations/developer-tools/github-copilot).
#
# usage:  eval "$(bash langfuse-otel-env.sh [--host URL] [--capture-content])"
#         bash langfuse-otel-env.sh --print-names        # just the variable names, no values
#   --host URL          Langfuse base URL (default: the recorded observability.host, else http://localhost:3000)
#   --capture-content   also set OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true — OPT-IN: prompts,
#                       responses and tool arguments are then stored in Langfuse
#
# Keys come from LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY in the environment or this repo's (then the
# workspace root's) gitignored .env.harness — never from an argument, never printed on their own. The Basic-auth
# header is base64(public:secret), which IS the secret in encoded form: it ends up in the shell that runs
# `eval`, so don't paste the output into a committed file or a chat. Missing keys → message on stderr, exit 1,
# NOTHING on stdout (so a failed `eval` is a no-op).
#
# The Claude Code plugin does not use this: it keeps its own copy of the keys in the OS keychain
# (`/plugin configure langfuse-observability@langfuse-observability`).

set -u
HOST=""; CAPTURE=0; NAMES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --capture-content) CAPTURE=1; shift ;;
    --print-names) NAMES=1; shift ;;
    *) echo "langfuse-otel-env: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ "$NAMES" -eq 1 ]; then
  printf '%s\n' COPILOT_OTEL_ENABLED OTEL_EXPORTER_OTLP_ENDPOINT OTEL_EXPORTER_OTLP_HEADERS \
    OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT
  exit 0
fi

env_value() { # env_value NAME — environment first, then .env.harness here, then the workspace root's
  local v f
  v="${!1:-}"
  if [ -z "$v" ]; then
    for f in .env.harness ../.env.harness; do
      [ -f "$f" ] || continue
      v=$(tr -d '\r' < "$f" | sed -nE "s/^(export[[:space:]]+)?$1=(.*)$/\2/p" | head -1)
      v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
      [ -n "$v" ] && break
    done
  fi
  printf '%s' "$v"
}

PK=$(env_value LANGFUSE_PUBLIC_KEY)
SK=$(env_value LANGFUSE_SECRET_KEY)
if [ -z "$PK" ] || [ -z "$SK" ]; then
  miss=""; [ -z "$PK" ] && miss="LANGFUSE_PUBLIC_KEY"; [ -z "$SK" ] && miss="$miss LANGFUSE_SECRET_KEY"
  echo "langfuse-otel-env: missing${miss:+:}$miss — fill them in .env.harness (create them in the Langfuse UI: project settings → API keys)" >&2
  exit 1
fi

if [ -z "$HOST" ]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # decision-review prints "observability<TAB>status<TAB>provider @ host<TAB>…"
  HOST=$(bash "$HERE/decision-review.sh" . 2>/dev/null | awk -F'\t' '$1 == "observability" { n = index($3, " @ "); if (n) print substr($3, n + 3) }')
fi
HOST="${HOST:-http://localhost:3000}"
HOST="${HOST%/}"

AUTH=$(printf '%s:%s' "$PK" "$SK" | base64 | tr -d '\n\r')
q() { printf "'%s'" "${1//\'/\'\\\'\'}"; }          # single-quote for safe eval

printf 'export COPILOT_OTEL_ENABLED=true\n'
printf 'export OTEL_EXPORTER_OTLP_ENDPOINT=%s\n' "$(q "$HOST/api/public/otel")"
printf 'export OTEL_EXPORTER_OTLP_HEADERS=%s\n' "$(q "Authorization=Basic $AUTH,x-langfuse-ingestion-version=4")"
[ "$CAPTURE" -eq 1 ] && printf 'export OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true\n'
echo "langfuse-otel-env: exporting for $HOST (content capture: $([ "$CAPTURE" -eq 1 ] && echo ON || echo off)). Start copilot from this shell." >&2
exit 0
