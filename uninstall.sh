#!/usr/bin/env bash
# Remove llmsetup. Safe to run again.
#
#   from a clone:  ./uninstall.sh
#   in one go:     curl -fsSL https://raw.githubusercontent.com/stamate/llmsetup/main/uninstall.sh | bash
#
# Folders you set up keep their .claude-home / .codex-home (logins, sessions); this
# lists them so you can remove `use llmsetup` from their .envrc. The global gitignore
# entries stay, so those folders' configs never get committed by accident.
set -euo pipefail

say() { printf 'uninstall: %s\n' "$*"; }
short() { if [[ $1 == "$HOME"/* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi; }

# Remove $1 if it is our link (target ends in $2); put back a file install.sh set aside.
unlink_ours() {
  local dst=$1 suffix=$2
  if [[ -L $dst && $(readlink "$dst") == *"$suffix" ]]; then
    rm "$dst"
    say "removed $(short "$dst")"
    if [[ -e $dst.bak ]]; then
      mv "$dst.bak" "$dst"
      say "put back your earlier $(short "$dst")"
    fi
  fi
}

main() {
  local bin=$HOME/.local/bin/llmsessions
  local lib=${XDG_CONFIG_HOME:-$HOME/.config}/direnv/lib/llmsetup.sh
  local managed=${LLMSETUP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/llmsetup}

  # Where llmsetup is installed, read from the link before removing it.
  local repo=
  if [[ -L $bin ]]; then
    repo=$(readlink "$bin")
    repo=${repo%/bin/llmsessions}
  fi

  unlink_ours "$bin" /bin/llmsessions
  unlink_ours "$lib" /direnv/llmsetup.sh

  local zshrc=${ZDOTDIR:-$HOME}/.zshrc
  if grep -qs 'zsh/llmsetup.zsh' "$zshrc"; then
    cp "$zshrc" "$zshrc.llmsetup.bak"
    grep -v 'zsh/llmsetup.zsh' "$zshrc.llmsetup.bak" > "$zshrc" || true  # writes through a symlinked .zshrc
    say "removed the llmsetup line from $(short "$zshrc") (copy: $(short "$zshrc").llmsetup.bak)"
  fi

  if [[ -f $managed/zsh/llmsetup.zsh && -f $managed/install.sh ]]; then
    rm -rf "${managed:?}"
    say "deleted the downloaded copy in $(short "$managed")"
  elif [[ -n $repo && -d $repo ]]; then
    say "your clone in $(short "$repo") is left in place"
  fi

  # Folders that still say `use llmsetup`: direnv reports an error there until it's removed.
  local allow=${XDG_DATA_HOME:-$HOME/.local/share}/direnv/allow entry envrc folders=()
  for entry in "$allow"/*; do
    [[ -f $entry ]] || continue
    envrc=$(< "$entry")
    grep -qs '^[[:space:]]*use llmsetup' "$envrc" && folders+=("$(short "${envrc%/.envrc}")")
  done
  if (( ${#folders[@]} )); then
    say "these folders still have 'use llmsetup' in their .envrc; remove that line there:"
    printf '  %s\n' "${folders[@]}"
  fi
  say "done; open a new terminal for it to take effect"
}

main "$@"
