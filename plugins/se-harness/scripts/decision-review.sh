#!/usr/bin/env bash
# decision-review.sh — read-only. Report the recorded state of the choices a user may want to
# revisit, so /harness-sync (decision drift) and /harness-bootstrap --reconfigure can say
# "Observability: Langfuse @ http://localhost:3000, configured 2026-10-13 — change it with …"
# instead of re-deriving it from YAML by eye. Changes nothing, never prints a secret value.
#
# usage: decision-review.sh [project-dir]        (default: .)
# output: one TAB-separated line per topic:
#           topic <TAB> status <TAB> value <TAB> decided <TAB> detail
#         topics: observability | memory | methodology
#         status: configured | declined | deferred | unset | invalid(<raw>)
#           configured  a choice is recorded and in force
#           declined    "no thanks" — never re-asked; changeable with --reconfigure
#           deferred    "not yet" — re-asked on every /harness-sync
#           unset       never decided (projects created before the question existed land here)
# Resolution: this repo's .harness/profile.yaml first; if it records nothing for a topic, the
# workspace manifest's shared: block (./workspace.yaml or ../workspace.yaml) is the default.

set -u
cd "${1:-.}" 2>/dev/null || { echo "decision-review: no such directory: ${1:-.}" >&2; exit 1; }

PROFILE=".harness/profile.yaml"
WS=""
for c in workspace.yaml ../workspace.yaml; do [ -f "$c" ] && WS="$c" && break; done

# yaml_get <file> <dotted.path> — value of a scalar at that path (2-space indentation assumed,
# which is what every template ships). Strips trailing comments and surrounding quotes.
yaml_get() {
  [ -f "$1" ] || return 0
  tr -d '\r' < "$1" | awk -v want="$2" -v q="'" '
    /^[[:space:]]*(#|$)/ { next }
    {
      match($0, /^ */); n = RLENGTH
      line = substr($0, n + 1)
      if (line !~ /^[A-Za-z_][A-Za-z0-9_-]*:/) next
      k = line; sub(/:.*/, "", k)
      v = line; sub(/^[^:]*:[ \t]*/, "", v)
      for (i in stack) if (i + 0 >= n) delete stack[i]
      stack[n] = k
      path = ""
      for (i = 0; i <= n; i++) if (i in stack) path = path (path == "" ? "" : ".") stack[i]
      if (path == want) {
        if (v ~ /^"/)      { sub(/^"/, "", v); sub(/".*$/, "", v) }
        else if (substr(v, 1, 1) == q) { v = substr(v, 2); j = index(v, q); if (j) v = substr(v, 1, j - 1) }
        else               { sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v) }
        print v; exit
      }
    }'
}

# first non-empty of: profile value, workspace shared value
resolve() { # resolve <profile.path> <workspace.path>
  local v; v=$(yaml_get "$PROFILE" "$1")
  if [ -z "$v" ] || [ "$v" = "null" ]; then [ -n "$WS" ] && v=$(yaml_get "$WS" "$2"); fi
  [ "$v" = "null" ] && v=""
  printf '%s' "$v"
}

env_has() { # env_has NAME — non-empty assignment in this repo's or the workspace root's .env.harness
  local f
  for f in .env.harness ../.env.harness; do
    [ -f "$f" ] && tr -d '\r' < "$f" | grep -qE "^(export[[:space:]]+)?$1=.+" && return 0
  done
  [ -n "${!1:-}" ]
}

valid_status() { case "$1" in configured|declined|deferred|unset) return 0 ;; *) return 1 ;; esac; }

row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }

# ---- observability
st=$(resolve observability.status workspace.shared.observability.status)
prov=$(resolve observability.provider workspace.shared.observability.provider)
host=$(resolve observability.host workspace.shared.observability.host)
dec=$(resolve observability.decided workspace.shared.observability.decided)
[ -z "$st" ] && st=unset
valid_status "$st" || st="invalid($st)"
detail=""
if [ "$st" = configured ]; then
  case "$prov" in
    langfuse)
      # Keys are surface-specific: the Claude Code plugin keeps its own copy in the OS keychain, so a
      # project that only uses Claude Code legitimately has none in .env.harness. Copilot CLI reads them
      # from .env.harness via scripts/langfuse-otel-env.sh. Names only, never values.
      miss=""
      for v in LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY; do env_has "$v" || miss="$miss $v"; done
      if [ -z "$host" ]; then detail="host: not recorded (observability.host)"
      elif [ -z "$miss" ]; then detail=".env.harness: ok"
      else detail=".env.harness: missing${miss} (only the Copilot CLI path needs them there; the Claude Code plugin keeps its own in the OS keychain)"; fi ;;
    dash0)
      if [ -z "$host" ]; then detail="host: not recorded (observability.host = the Dash0 OTLP URL)"
      else detail="token and dataset live in the plugin's keychain/config (/plugin -> dash0 -> Configure), not .env.harness"; fi ;;
    other) detail="check the backend's own docs for required variables" ;;
    "") st="invalid(configured-without-provider)" ;;
  esac
fi
val="${prov:--}"; [ -n "$host" ] && val="$val @ $host"
row observability "$st" "$val" "${dec:--}" "$detail"

# ---- structural memory driver (null = deferred, valid and not nagged by the older contract —
# reported here as `deferred` so the sync review can offer it, never forced)
drv=$(resolve memory.structural_driver workspace.shared.memory.structural_driver)
if [ -n "$drv" ]; then row memory configured "$drv" - ""; else row memory deferred - - ""; fi

# ---- methodology
m=$(resolve methodology workspace.shared.methodology)
if [ -n "$m" ]; then row methodology configured "$m" - ""; else row methodology unset - - ""; fi
exit 0
