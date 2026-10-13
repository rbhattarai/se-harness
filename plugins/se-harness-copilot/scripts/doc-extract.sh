#!/usr/bin/env bash
# doc-extract.sh — deterministic mechanics for /harness-mem-wiki's NAS-documents step:
# inventory a document tree by format, report which formats this machine can read, and extract
# one file to text/markdown. Reads doc-registry/{formats,extractors}.tsv. NEVER installs anything
# and makes no network calls (PRIVACY.md) — the command asks the user, then runs the install.
#
# usage:
#   doc-extract.sh --inventory [--skip-ext e1,e2] [--registry-extra DIR] <dir>...
#   doc-extract.sh --extract <file> [--extractor ID] [--max-chars N] [--max-bytes N] [--registry-extra DIR] [-o OUT]
#   doc-extract.sh --tool-status <extractor-id> [--registry-extra DIR]    # prints ready|missing
#   doc-extract.sh --install-cmd <extractor-id> [--registry-extra DIR]    # prints the install text
#
# --registry-extra DIR: optional {formats,extractors}.tsv whose rows are consulted BEFORE the
#   built-in ones (how a project adds a format or its own converter command).
# env DOC_REGISTRY_DIR overrides the built-in registry dir (tests).
#
# --inventory prints TAB-separated lines:
#   FORMAT <ext> <count> <bytes> <status> <extractor>
#     status: ready | missing (extractor = the recommended one to install) | unsupported |
#             flagged-ocr (images — never ingested) | declined (--skip-ext)
#   JUNK <count>        lock/temp/NAS-housekeeping files skipped (~$x, Thumbs.db, @eaDir, #recycle ...)
#   MISSING_PATH <path> a given directory does not exist
#
# --extract writes the text to stdout (or -o). exit codes:
#   0 ok · 1 usage · 4 no usable extractor (tool missing; message names it) · 5 unsupported format
#   6 extraction failed (corrupt/encrypted/tool error) · 7 flagged: image, or a PDF with almost
#   no text (scanned — needs OCR; nothing written) · 8 file larger than --max-bytes
#   (--max-chars truncates the output with a marker line instead; exit 0)

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG="${DOC_REGISTRY_DIR:-$SCRIPT_DIR/doc-registry}"
EXTRA=""

die() { echo "$*" >&2; exit 1; }

MODE=""; SKIP=""; FILE=""; FORCE_EXT=""; MAXC=0; MAXB=0; OUT=""; ARG1=""; DIRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --inventory) MODE=inv; shift ;;
    --extract) MODE=ext; FILE="${2:?--extract needs a file}"; shift 2 ;;
    --tool-status) MODE=tool; ARG1="${2:?id}"; shift 2 ;;
    --install-cmd) MODE=inst; ARG1="${2:?id}"; shift 2 ;;
    --skip-ext) SKIP="${2:-}"; shift 2 ;;
    --extractor) FORCE_EXT="${2:?id}"; shift 2 ;;
    --max-chars) MAXC="${2:?n}"; shift 2 ;;
    --max-bytes) MAXB="${2:?n}"; shift 2 ;;
    --registry-extra) EXTRA="${2:?dir}"; shift 2 ;;
    -o) OUT="${2:?path}"; shift 2 ;;
    -*) die "unknown option: $1" ;;
    *) DIRS+=("$1"); shift ;;
  esac
done
[ -n "$MODE" ] || die "usage: doc-extract.sh --inventory|--extract|--tool-status|--install-cmd (see header)"

reg_files() { # $1 = formats|extractors → existing registry files, extra first
  local f
  [ -n "$EXTRA" ] && [ -f "$EXTRA/$1.tsv" ] && echo "$EXTRA/$1.tsv"
  f="$REG/$1.tsv"; [ -f "$f" ] && echo "$f"
  return 0
}
# first row whose key (column 1) matches; prints the whole row
lookup() { # $1 = formats|extractors, $2 = key
  local f row
  while IFS= read -r f; do
    row=$(awk -F'\t' -v k="$2" '/^#/ || NF==0 {next} $1==k {print; exit}' "$f")
    [ -n "$row" ] && { printf '%s\n' "$row"; return 0; }
  done < <(reg_files "$1")
  return 1
}
field() { printf '%s' "$1" | awk -F'\t' -v n="$2" '{print $n}'; }

tool_ready() { # extractor id → 0 if its check passes
  local row chk
  row=$(lookup extractors "$1") || return 1
  chk=$(field "$row" 2)
  bash -c "$chk" >/dev/null 2>&1
}

# first READY extractor in a comma list; else prints the FIRST id and returns 1
pick_extractor() {
  local list="$1" id first=""
  IFS=',' read -ra ids <<< "$list"
  for id in "${ids[@]}"; do
    [ -n "$first" ] || first="$id"
    if tool_ready "$id"; then printf '%s\n' "$id"; return 0; fi
  done
  printf '%s\n' "$first"; return 1
}

ext_of() { local b; b=$(basename "$1"); case "$b" in *.*) printf '%s' "${b##*.}" | tr 'A-Z' 'a-z' ;; *) printf '%s' "(none)" ;; esac; }

is_junk() { # basename → 0 if housekeeping junk
  case "$1" in
    '~$'*|.~lock.*|Thumbs.db|.DS_Store|desktop.ini|*.tmp|'~'*.tmp) return 0 ;;
  esac
  return 1
}

case "$MODE" in
  tool)  if tool_ready "$ARG1"; then echo ready; else echo missing; exit 1; fi; exit 0 ;;
  inst)  row=$(lookup extractors "$ARG1") || die "unknown extractor: $ARG1"; field "$row" 4; exit 0 ;;

  inv)
    [ ${#DIRS[@]} -gt 0 ] || die "--inventory needs at least one directory"
    TMP=$(mktemp); junk=0
    for d in "${DIRS[@]}"; do
      if [ ! -d "$d" ]; then printf 'MISSING_PATH\t%s\n' "$d"; continue; fi
      while IFS= read -r -d '' f; do
        if is_junk "$(basename "$f")"; then junk=$((junk + 1)); continue; fi
        printf '%s\t%s\n' "$(ext_of "$f")" "$(wc -c < "$f" | tr -d ' ')" >> "$TMP"
      done < <(find "$d" \( -name '@eaDir' -o -name '#recycle' -o -name '$RECYCLE.BIN' -o -name '.Trashes' -o -name '.git' -o -name '.SynologyWorkingDirectory' \) -prune -o -type f -print0)
    done
    printf 'JUNK\t%s\n' "$junk"
    sort -t "$(printf '\t')" -k1,1 "$TMP" | awk -F'\t' '{c[$1]++; b[$1]+=$2} END {for (e in c) printf "%s\t%d\t%d\n", e, c[e], b[e]}' | sort |
    while IFS=$'\t' read -r e cnt bytes; do
      if [ -n "$SKIP" ] && printf ',%s,' "$SKIP" | grep -q ",$e,"; then
        printf 'FORMAT\t%s\t%s\t%s\tdeclined\t-\n' "$e" "$cnt" "$bytes"; continue
      fi
      row=$(lookup formats "$e") || { printf 'FORMAT\t%s\t%s\t%s\tunsupported\t-\n' "$e" "$cnt" "$bytes"; continue; }
      if [ "$(field "$row" 2)" = image ]; then
        printf 'FORMAT\t%s\t%s\t%s\tflagged-ocr\t-\n' "$e" "$cnt" "$bytes"; continue
      fi
      if x=$(pick_extractor "$(field "$row" 3)"); then st=ready; else st=missing; fi
      printf 'FORMAT\t%s\t%s\t%s\t%s\t%s\n' "$e" "$cnt" "$bytes" "$st" "$x"
    done
    rm -f "$TMP"
    exit 0 ;;

  ext)
    [ -f "$FILE" ] || die "file not found: $FILE"
    e=$(ext_of "$FILE")
    row=$(lookup formats "$e") || { echo "unsupported format: .$e" >&2; exit 5; }
    if [ "$(field "$row" 2)" = image ]; then
      echo "flagged: image (.$e) needs OCR — not ingested" >&2; exit 7
    fi
    bytes=$(wc -c < "$FILE" | tr -d ' ')
    if [ "$MAXB" -gt 0 ] && [ "$bytes" -gt "$MAXB" ]; then
      echo "too large: $bytes bytes > --max-bytes $MAXB" >&2; exit 8
    fi
    if [ -n "$FORCE_EXT" ]; then x="$FORCE_EXT"; tool_ready "$x" || { echo "extractor not ready: $x" >&2; exit 4; }
    else
      x=$(pick_extractor "$(field "$row" 3)") || {
        echo "no usable extractor for .$e — missing: $x; install: $(field "$(lookup extractors "$x")" 4)" >&2; exit 4; }
    fi
    erow=$(lookup extractors "$x") || { echo "unknown extractor: $x" >&2; exit 4; }
    tmpl=$(field "$erow" 3)
    q=$(printf '%q' "$FILE")
    cmd="${tmpl//\{in\}/$q}"
    RES=$(mktemp); ERR=$(mktemp)
    if ! bash -c "$cmd" > "$RES" 2> "$ERR"; then
      echo "extraction failed ($x): $(head -c 300 "$ERR" | tr '\n' ' ')" >&2
      rm -f "$RES" "$ERR"; exit 6
    fi
    chars=$(tr -d '[:space:]' < "$RES" | wc -c | tr -d ' ')
    if [ "$chars" -eq 0 ] && [ "$e" != pdf ]; then
      echo "extraction produced no text ($x) — empty, encrypted or unreadable" >&2; rm -f "$RES" "$ERR"; exit 6
    fi
    # scanned-PDF heuristic: almost no text, or vanishingly little text for the file's size
    if [ "$e" = pdf ] && { [ "$chars" -lt 50 ] || [ $((bytes / chars)) -gt 1500 ]; }; then
      echo "flagged: scanned or image-only PDF ($chars chars from $bytes bytes) — needs OCR; not ingested" >&2
      rm -f "$RES" "$ERR"; exit 7
    fi
    if [ "$MAXC" -gt 0 ]; then
      total=$(wc -c < "$RES" | tr -d ' ')
      if [ "$total" -gt "$MAXC" ]; then
        head -c "$MAXC" "$RES" > "$RES.cut"; mv "$RES.cut" "$RES"
        printf '\n[truncated at %s of %s chars]\n' "$MAXC" "$total" >> "$RES"
      fi
    fi
    if [ -n "$OUT" ]; then mv "$RES" "$OUT"; else cat "$RES"; rm -f "$RES"; fi
    rm -f "$ERR"
    exit 0 ;;
esac
