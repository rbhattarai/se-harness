#!/usr/bin/env bash
# irreversible-cmd.sh — sourced by gate-check.sh and contract-check.sh (not run directly).
# Defines is_irreversible "<shell command>": 0 when the command would push, open a PR, or
# deploy/publish; 1 otherwise.
#
# It reads commands the way a shell does, not as a bag of words: split into simple commands,
# drop env assignments / sudo-style wrappers / path prefixes, find the real program and
# subcommand, and look through `bash -c '…'` / `eval`. So:
#   caught    git push · git -C . push · git  push (any spacing) · /usr/bin/git push · FOO=1 git push ·
#             sudo git push · bash -c 'git push' · git p''ush · git ${X:-push} · gh api …/pulls ·
#             aws deploy … · gcloud deploy … · kubectl apply · helm upgrade · npm publish …
#   ignored   echo "git push" · grep -rn "gh pr create" docs/ · git commit -m "explain git push" ·
#             git log --grep="terraform apply"   (the words appear as data, not as the program)
# Best effort by design: no shell parser, so truly obfuscated commands can still slip through —
# the gate is a seatbelt against an agent skipping the human, not a sandbox.

# After a hit, IRR_KIND says what kind: push | pr | deploy (contract-check only cares about push/pr).
IRR_KIND=""

_irr_strip_quotes() { local t="$1"; t="${t//\'/}"; t="${t//\"/}"; printf '%s' "$t"; }

# _irr_segment "<one simple command>"
_irr_segment() {
  local seg="$1" tok=() t i=0 n prog sub
  # tokenize on whitespace, dropping quote characters (so p''ush -> push, "git" -> git)
  read -r -a tok <<< "$seg"
  n=${#tok[@]}
  for ((i = 0; i < n; i++)); do tok[i]=$(_irr_strip_quotes "${tok[i]}"); done
  i=0
  # leading ( { and env assignments and transparent wrappers
  while ((i < n)); do
    t="${tok[i]}"
    case "$t" in
      "("|"{"|"!") i=$((i + 1)); continue ;;
      [A-Za-z_]*=*) i=$((i + 1)); continue ;;
      sudo|command|exec|nohup|time|env|nice|builtin|then|do|else|if|while|until|elif) i=$((i + 1)); continue ;;
      -*) if ((i > 0)); then i=$((i + 1)); continue; fi ;;
    esac
    break
  done
  ((i < n)) || return 1
  prog="${tok[i]##*/}"; prog="${prog%.exe}"
  i=$((i + 1))

  case "$prog" in
    bash|sh|zsh|dash|ksh)
      # bash -c '<cmd>' : judge the inner command
      local j
      for ((j = i; j < n; j++)); do
        case "${tok[j]}" in
          -c|-lc|-ic|-cl|-ci) is_irreversible "${tok[*]:$((j + 1))}" --keep-kind; return $? ;;
        esac
      done
      return 1 ;;
    eval) is_irreversible "${tok[*]:$i}" --keep-kind; return $? ;;
    git)
      # skip git's global options (-C <dir>, -c <k=v>, --git-dir <p>, --no-pager, ...) to find the subcommand
      while ((i < n)); do
        case "${tok[i]}" in
          -C|-c|--git-dir|--work-tree|--namespace|--exec-path) i=$((i + 2)) ;;
          -*) i=$((i + 1)) ;;
          *) break ;;
        esac
      done
      sub="${tok[i]:-}"
      case "$sub" in
        push|send-pack) IRR_KIND=push; return 0 ;;
        *'$'*|*'`'*) IRR_KIND=push; return 0 ;;     # subcommand hidden behind an expansion: can't prove it's safe
      esac
      return 1 ;;
    gh)
      local a="${tok[i]:-}" b="${tok[i + 1]:-}" rest="${tok[*]:$i}"
      [[ "$a $b" == "pr create" ]] && { IRR_KIND=pr; return 0; }
      [[ "$a $b" == "release create" ]] && { IRR_KIND=deploy; return 0; }
      if [[ "$a" == api ]]; then
        # REST calls that create a PR / release: POST (explicit method, or implied by -f/-F fields)
        [[ "$rest" =~ /(pulls|releases)([[:space:]/]|$) ]] && [[ "$rest" =~ (-X[[:space:]]*POST|--method[[:space:]]+POST|[[:space:]]-[fF][[:space:]]|--(raw-)?field) ]] && { IRR_KIND=pr; return 0; }
      fi
      return 1 ;;
    docker|podman)
      local rest="${tok[*]:$i}"
      [[ "${tok[i]:-}" == push ]] && return 0
      [[ "${tok[i]:-}" == compose && "${tok[i + 1]:-}" == push ]] && return 0
      [[ "$rest" =~ (^|[[:space:]])(buildx[[:space:]]+)?build.*[[:space:]]--push([[:space:]]|$) ]] && return 0
      return 1 ;;
    docker-compose) [[ "${tok[i]:-}" == push ]] && return 0; return 1 ;;
    terraform|tofu) [[ "${tok[i]:-}" == apply ]] && return 0; return 1 ;;
    kubectl) [[ "${tok[i]:-}" == apply ]] && return 0; return 1 ;;
    helm) [[ "${tok[i]:-}" == upgrade || "${tok[i]:-}" == install ]] && return 0; return 1 ;;
    vercel|netlify|firebase|flyctl|fly|wrangler|serverless|sls)
      local k; for ((k = i; k < n; k++)); do [[ "${tok[k]}" == deploy || "${tok[k]}" == publish ]] && return 0; done; return 1 ;;
    npm|pnpm|yarn) [[ "${tok[i]:-}" == publish ]] && return 0; return 1 ;;
    twine) [[ "${tok[i]:-}" == upload ]] && return 0; return 1 ;;
    aws|gcloud)
      local k; for ((k = i; k < n; k++)); do [[ "${tok[k]}" == deploy ]] && return 0; done; return 1 ;;
    az)
      local k; for ((k = i; k < n; k++)); do [[ "${tok[k]}" == deploy || "${tok[k]}" == up ]] && return 0; done; return 1 ;;
  esac
  return 1
}

# is_irreversible "<full command line>"
is_irreversible() {
  local cmd="$1" seg
  [[ "${2:-}" == --keep-kind ]] || IRR_KIND=""
  # JSON-escaped newlines/tabs arrive as backslash sequences; treat them as separators/spaces
  cmd="${cmd//\\n/;}"; cmd="${cmd//\\t/ }"
  cmd=$(printf '%s' "$cmd" | tr '\n\t' ';  ' | sed -E 's/&&|\|\||[;|&]/\n/g')
  while IFS= read -r seg; do
    [[ -n "${seg//[[:space:]]/}" ]] || continue
    if _irr_segment "$seg"; then [[ -n "$IRR_KIND" ]] || IRR_KIND=deploy; return 0; fi
  done <<< "$cmd"
  return 1
}
