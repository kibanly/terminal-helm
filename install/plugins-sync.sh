#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  terminal-helm · plugins to the commits in install/plugins.lock
#    install/plugins-sync.sh          each installed plugin to its locked commit (`update`, Ctrl+a U)
#    install/plugins-sync.sh --bump   the lock to each plugin's newest commit (make bump-plugins):
#                                     review the diff, test, commit it, then `update` moves to it
#  The lock is the only way plugin code changes: a `git pull` (tpm's own update) would run
#  whatever is upstream that day in every shell and in tmux.
#  A missing plugin is left to ./install.sh, which clones it.
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

repo=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
lock=$repo/install/plugins.lock
[ -r "$lock" ] || { echo "✘ no $lock" >&2; exit 1; }

plugin_dir() {
  case $1 in
    tmux/*) echo "$HOME/.tmux/plugins/${1#tmux/}" ;;
    zsh/*)  echo "$HOME/.zsh/plugins/${1#zsh/}" ;;
  esac
}

bump() {
  local name url commit new changed=0
  bump_tmp=$(mktemp "$lock.XXXXXX") || exit 1       # global: the EXIT trap runs after bump returns
  trap 'rm -f "$bump_tmp"' EXIT
  local tmp=$bump_tmp
  while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*(#|$) ]]; then printf '%s\n' "$line" >> "$tmp"; continue; fi
    read -r name url commit <<< "$line"
    new=$(git ls-remote "$url" HEAD 2>/dev/null | awk 'NR==1 {print $1}')
    if [[ ! $new =~ ^[0-9a-f]{40}$ ]]; then
      echo "✘ ${name#*/}: could not ask $url (kept at ${commit:0:7})" >&2
      printf '%s\n' "$line" >> "$tmp"; continue
    fi
    if [ "$new" = "$commit" ]; then
      echo "  ${name#*/} ${commit:0:7} (newest already)"
    else
      echo "  ${name#*/} ${commit:0:7} → ${new:0:7}   $url/compare/${commit:0:12}...${new:0:12}"
      changed=1
    fi
    printf '%s\n' "${line/$commit/$new}" >> "$tmp"
  done < "$lock"
  cat "$tmp" > "$lock"
  if [ "$changed" = 1 ]; then
    echo "→ install/plugins.lock changed: read the compare links, test (make test smoke), commit it"
  fi
}

sync() {
  local name url commit dir rc=0 head
  while read -r name url commit; do
    dir=$(plugin_dir "$name")
    [ -n "$dir" ] && [ -d "$dir/.git" ] || continue
    head=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
    if [ "$head" = "$commit" ]; then echo "  ${name#*/} ${commit:0:7}"; continue; fi
    # fetch only when the commit is not there yet (a newer lock)
    if ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null \
       && ! git -C "$dir" fetch -q origin 2>/dev/null; then
      echo "✘ ${name#*/}: could not fetch from $url" >&2; rc=1; continue
    fi
    if git -C "$dir" reset -q --hard "$commit" 2>/dev/null; then
      echo "  ${name#*/} ${head:0:7} → ${commit:0:7}"
    else
      echo "✘ ${name#*/}: commit ${commit:0:7} not found in $url" >&2; rc=1
    fi
  done < <(grep -v '^[[:space:]]*#' "$lock" | grep -v '^[[:space:]]*$')
  return $rc
}

case ${1:-} in
  --bump)    bump ;;
  "")        sync ;;
  -h|--help) sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)         echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
esac
