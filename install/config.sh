# shellcheck shell=bash
# shellcheck disable=SC2088  # "~/…" in messages is text to show, not a path
# ═══════════════════════════════════════════════════════════════
#  terminal-helm · your config files. Nothing is replaced and nothing is linked:
#    ~/.zshrc       gets, at its end:  source "<repo>/zsh/zshrc"
#    ~/.tmux.conf   gets, at its end:  TERMINAL_SETUP="<repo>" + source-file of tmux/tmux.conf
#    ~/.zshenv      gets, at its end:  skip_global_compinit=1 (Ubuntu's /etc/zsh/zshrc would run
#                   compinit too, before zsh/zshrc runs its own: completion loaded twice)
#  between two marks, so ./uninstall.sh can take exactly those lines out again.
#  ~/.tmux stays yours (tpm puts the plugins there; logs, session descriptions…).
#  The prompt reads the repo's starship.toml (STARSHIP_CONFIG, set by zsh/zshrc);
#  btop and micro get the repo's settings only when you have none.
#  An install from before (links into the repo) is turned into this.
#  Needs: REPO, BACKUP_DIR, lib.sh.
# ═══════════════════════════════════════════════════════════════

MARK_BEGIN="# >>> terminal-helm >>>"
MARK_END="# <<< terminal-helm <<<"

# config files copied once, when you have none: <in the repo> <in your home>
COPIES="
config/btop/btop.conf      .config/btop/btop.conf
config/micro/settings.json .config/micro/settings.json
"
# the ones the install copied itself (one per line): uninstall.sh removes only those, never a
# file you already had, even when it is the same as the repo's
COPIED_LIST="$HOME/.tmux/terminal-helm-copies"

# the names from before the project was renamed (terminal-setup → terminal-helm): migrate_old_name
OLD_MARK_BEGIN="# >>> terminal-setup >>>"
OLD_MARK_END="# <<< terminal-setup <<<"
OLD_COPIED_LIST="$HOME/.tmux/terminal-setup-copies"
OLD_BACKUPS="$HOME/.terminal-setup-backup"
# shellcheck disable=SC2034  # read by uninstall.sh
OLD_REPO_LINK="$HOME/.local/share/terminal-setup"

block_zsh() {
  printf '%s\n' "$MARK_BEGIN  (./uninstall.sh takes it out)" \
    "source \"$REPO/zsh/zshrc\"" "$MARK_END"
}
block_zshenv() {
  printf '%s\n' "$MARK_BEGIN  (./uninstall.sh takes it out)" \
    "skip_global_compinit=1   # zsh/zshrc runs compinit itself" "$MARK_END"
}
block_tmux() {
  printf '%s\n' "$MARK_BEGIN  (./uninstall.sh takes it out)" \
    "TERMINAL_SETUP=\"$REPO\"" 'source-file "$TERMINAL_SETUP/tmux/tmux.conf"' "$MARK_END"
}

# the marks count at the start of a line only, everywhere (has_block, block_in, the rewrites)
has_block()   { [ -f "$1" ] && awk -v b="$MARK_BEGIN" 'index($0,b)==1{f=1} END{exit !f}' "$1"; }
# a begin mark with no end mark after it (a line edited by hand): rewriting the file would
# drop everything below it, so the install and uninstall stop instead
check_marks() {   # check_marks <file> [<begin mark> <end mark>]
  local b=${2:-$MARK_BEGIN} e=${3:-$MARK_END}
  awk -v b="$b" -v e="$e" 'index($0,b)==1{on=1} on&&index($0,e)==1{on=0} END{exit on}' "$1" \
    || die "$(tilde "$1") has the line \"$b\" but no \"$e\" after it: put it back (or take both out), then run this again"
}
has_old_block() { [ -f "$1" ] && awk -v b="$OLD_MARK_BEGIN" 'index($0,b)==1{f=1} END{exit !f}' "$1"; }

# An install from before the rename: its marks get the new name (the lines between them stay
# as they are), and the list of copies and the backups move to where they go now. The old link
# for a folder with spaces stays: the shells open now still use it (uninstall.sh removes it).
migrate_old_name() {
  local f d new_backups=${BACKUP_DIR%/*}
  [ "${DRY_RUN:-0}" = 1 ] && {
    for f in .zshrc .tmux.conf .zshenv; do
      has_old_block "$HOME/$f" && info "[dry-run] ~/$f: terminal-setup marks → terminal-helm"
    done
    return 0
  }
  if [ -d "$OLD_BACKUPS" ]; then
    mkdir -p "$new_backups"
    for d in "$OLD_BACKUPS"/*/; do
      d=${d%/}; [ -e "$d" ] || continue
      [ -e "$new_backups/${d##*/}" ] || mv "$d" "$new_backups/"
    done
    rmdir "$OLD_BACKUPS" 2>/dev/null && ok "backups moved: $(tilde "$OLD_BACKUPS") → $(tilde "$new_backups")"
  fi
  if [ -f "$OLD_COPIED_LIST" ]; then
    cat "$OLD_COPIED_LIST" >> "$COPIED_LIST" && rm "$OLD_COPIED_LIST"
  fi
  for f in .zshrc .tmux.conf .zshenv; do
    has_old_block "$HOME/$f" || continue
    check_marks "$HOME/$f" "$OLD_MARK_BEGIN" "$OLD_MARK_END"
    backup_copy "$HOME/$f"
    awk -v ob="$OLD_MARK_BEGIN" -v oe="$OLD_MARK_END" -v nb="$MARK_BEGIN" -v ne="$MARK_END" '
      index($0,ob)==1 { $0 = nb substr($0, length(ob) + 1) }
      index($0,oe)==1 { $0 = ne substr($0, length(oe) + 1) }  { print }' "$HOME/$f" > "$HOME/$f.tmp"
    cat "$HOME/$f.tmp" > "$HOME/$f"; rm -f "$HOME/$f.tmp"
    ok "~/$f: marks renamed (terminal-setup → terminal-helm)"
  done
}
block_in()    { awk -v b="$MARK_BEGIN" -v e="$MARK_END" 'index($0,b)==1{on=1} on{print} index($0,e)==1{on=0}' "$1"; }
# the file without the block, and without the blank lines left at its end · the blank line just
# before the block goes with it (add_block put it there), so your lines come back as they were
without_block() {
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    index($0,b)==1 { sub(/[^\n]*\n$/, "", blank); on=1; next }  on { if (index($0,e)==1) on=0; next }
    /^[ \t]*$/ { blank = blank $0 "\n"; next }  { printf "%s%s\n", blank, $0; blank="" }' "$1"
}

# put the block at the end of $1 · if it is there already, refresh it in place (the repo moved…)
add_block() {
  local file=$1 block=$2 tmp
  if has_block "$file"; then
    check_marks "$file"
    if [ "$(block_in "$file")" = "$block" ]; then ok "$(tilde "$file") already loads terminal-helm"; return; fi
    [ "$DRY_RUN" = 1 ] && { info "[dry-run] update the terminal-helm lines in $(tilde "$file")"; return; }
    backup_copy "$file"
    tmp=$(mktemp)
    printf '%s\n' "$block" > "$tmp.block"
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" -v f="$tmp.block" '
      index($0,b)==1 { while ((getline l < f) > 0) print l; on=1; next }
      on { if (index($0,e)==1) on=0; next }  { print }' "$file" > "$tmp"
    cat "$tmp" > "$file"; rm -f "$tmp" "$tmp.block"
    ok "$(tilde "$file"): terminal-helm lines updated"
    return
  fi
  [ "$DRY_RUN" = 1 ] && { info "[dry-run] add to the end of $(tilde "$file"):"; printf '%s\n' "$block" | sed 's/^/          /'; return; }
  mkdir -p "$(dirname "$file")"
  if [ -s "$file" ]; then
    backup_copy "$file"
    [ -n "$(tail -c1 "$file")" ] && printf '\n' >> "$file"     # a last line with no newline
    printf '\n%s\n' "$block" >> "$file"
  else
    printf '%s\n' "$block" > "$file"
  fi
  ok "$(tilde "$file") loads terminal-helm (lines added at its end)"
}

# a copy of the file as it was, just in case (the file itself stays where it is) · a link
# (stow, chezmoi…) is copied with what it points to: that is what gets changed
backup_copy() {
  local rel=${1#"$HOME"/}
  [ -e "$BACKUP_DIR/$rel" ] && return
  mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  cp -L "$1" "$BACKUP_DIR/$rel" 2>/dev/null || cp -P "$1" "$BACKUP_DIR/$rel"
}

links_into_repo() {
  local f
  for f in .zshrc .zsh_aliases .zsh_functions .tmux .tmux.conf .config/starship.toml \
           .config/btop/btop.conf .config/micro/settings.json; do
    case $(readlink "$HOME/$f" 2>/dev/null || true) in "$REPO"/*) printf '%s\n' "$f" ;; esac
  done
}

# An install from before linked these into the repo: make them plain files again
# ~/.zshrc → what ~/.zshrc.local had (what you added), ~/.tmux → a folder with your
# plugins, logs and session descriptions, the rest goes (or becomes a copy)
unlink_old() {
  local f item
  for f in $(links_into_repo); do
    if [ "$DRY_RUN" = 1 ]; then info "[dry-run] ~/$f: link into the repo → plain file / folder"; continue; fi
    case $f in
      .zshrc)
        rm "$HOME/.zshrc"
        if [ -f "$HOME/.zshrc.local" ]; then
          cp "$HOME/.zshrc.local" "$HOME/.zshrc"
          backup_copy "$HOME/.zshrc.local" && rm "$HOME/.zshrc.local"
          ok "~/.zshrc: was a link, now your ~/.zshrc.local (+ the terminal-helm line)"
        else
          : > "$HOME/.zshrc"
          ok "~/.zshrc: was a link, now a file of yours"
        fi ;;
      .tmux)
        rm "$HOME/.tmux"; mkdir -p "$HOME/.tmux"
        for item in plugins logs resurrect descriptions.tsv; do
          [ -e "$REPO/tmux/$item" ] && mv "$REPO/tmux/$item" "$HOME/.tmux/"
        done
        ok "~/.tmux: was a link, now a folder with your plugins, logs and descriptions" ;;
      .tmux.conf)
        rm "$HOME/.tmux.conf"; : > "$HOME/.tmux.conf"
        ok "~/.tmux.conf: was a link, now a file of yours" ;;
      *)
        rm "$HOME/$f"
        ok "~/$f: link removed" ;;
    esac
  done
}

# things in your ~/.zshrc that do the same job as terminal-helm and may get in its way
zshrc_clashes() {
  [ -f "$HOME/.zshrc" ] || return 0
  local what
  what=$(without_block "$HOME/.zshrc" | grep -v '^[[:space:]]*#' | grep -oE 'oh-my-zsh\.sh|powerlevel10k|p10k|prezto|starship init|zinit|antigen|zplug' | sort -u | tr '\n' ' ' || true)
  [ -n "$what" ] || return 0
  warn "your ~/.zshrc also uses: ${what}— terminal-helm loads after it and wins, but"
  info "  two prompts or plugin managers can clash: take those lines out if something looks off"
}

configure() {
  step "Config files (your files load the repo's)"
  migrate_old_name
  [ -n "$(links_into_repo)" ] && unlink_old
  zshrc_clashes
  add_block "$HOME/.zshrc" "$(block_zsh)"
  add_block "$HOME/.tmux.conf" "$(block_tmux)"
  add_block "$HOME/.zshenv" "$(block_zshenv)"
  run mkdir -p "$HOME/.tmux/plugins"
  [ "${DRY_RUN:-0}" = 1 ] || touch "$COPIED_LIST"
  local src dst
  while read -r src dst; do
    [ -n "$src" ] || continue
    if [ -e "$HOME/$dst" ]; then
      if cmp -s "$REPO/$src" "$HOME/$dst"; then ok "~/$dst"
      else info "${D}~/$dst is yours: kept (the repo's is $src)${R}"; fi
      continue
    fi
    run mkdir -p "$(dirname "$HOME/$dst")"
    run cp "$REPO/$src" "$HOME/$dst"
    if [ "${DRY_RUN:-0}" != 1 ] && ! grep -qxF "$dst" "$COPIED_LIST" 2>/dev/null; then
      printf '%s\n' "$dst" >> "$COPIED_LIST"
    fi
    ok "~/$dst (copied from the repo: from now on it is yours)"
  done <<< "$COPIES"
}
