#!/usr/bin/env bash
# Install llmsetup. Safe to run again: it only does what is missing.
#
#   from a clone:  ./install.sh
#   in one go:     curl -fsSL https://raw.githubusercontent.com/stamate/llmsetup/main/install.sh | bash
#
# The one-liner keeps a copy in ~/.local/share/llmsetup and updates it when run again.
# Overrides: LLMSETUP_REPO (git URL), LLMSETUP_REF (branch), LLMSETUP_DIR (where the copy goes).
set -euo pipefail
script=${BASH_SOURCE[0]:-}  # empty when piped from curl (read here: inside a function it says "bash")

say() { printf 'install: %s\n' "$*"; }
short() { if [[ $1 == "$HOME"/* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi; }

# Append a line to a file, starting on a fresh line.
append() {
  [[ -s $1 && -n $(tail -c1 "$1") ]] && echo >> "$1"
  printf '%s\n' "$2" >> "$1"
}

# Piped from curl: fetch or update our copy, then run the installer inside it.
fetch_and_run() {
  local url=${LLMSETUP_REPO:-https://github.com/stamate/llmsetup.git}
  local dest=${LLMSETUP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/llmsetup}
  command -v git >/dev/null || { echo "install: git is required" >&2; exit 1; }
  if [[ -d $dest/.git ]]; then
    git -C "$dest" pull --ff-only --quiet
    say "updated $(short "$dest")"
  else
    mkdir -p "$(dirname "$dest")"
    git clone --quiet ${LLMSETUP_REF:+--branch "$LLMSETUP_REF"} "$url" "$dest"
    say "downloaded llmsetup to $(short "$dest")"
  fi
  exec bash "$dest/install.sh"
}

# Point $2 at the repo file $1, keeping a different existing file as .bak.
link() {
  local src=$repo/$1 dst=$2
  [[ -L $dst && $(readlink "$dst") == "$src" ]] && return
  mkdir -p "$(dirname "$dst")"
  if [[ -f $dst && ! -L $dst ]] && ! cmp -s "$src" "$dst"; then
    mv "$dst" "$dst.bak"
    say "kept your old $(short "$dst") as $(short "$dst").bak"
  fi
  rm -f "$dst"
  ln -s "$src" "$dst"
  say "linked $(short "$dst")"
}

main() {
  if [[ -f $script && -f $(dirname "$script")/zsh/llmsetup.zsh ]]; then
    repo=$(cd "$(dirname "$script")" && pwd)
  else
    fetch_and_run
  fi

  link bin/llmsessions "$HOME/.local/bin/llmsessions"
  link direnv/llmsetup.sh "${XDG_CONFIG_HOME:-$HOME/.config}/direnv/lib/llmsetup.sh"

  # zsh functions, loaded at the end of ~/.zshrc (after oh-my-zsh).
  local zshrc=${ZDOTDIR:-$HOME}/.zshrc source_line
  if [[ $repo == "$HOME"/* ]]; then
    source_line="source \"\$HOME/${repo#"$HOME"/}/zsh/llmsetup.zsh\"  # llmsetup"
  else
    source_line="source \"$repo/zsh/llmsetup.zsh\"  # llmsetup"
  fi
  if ! grep -qs 'zsh/llmsetup.zsh' "$zshrc"; then
    append "$zshrc" "$source_line"
    say "added the llmsetup functions to $(short "$zshrc")"
  fi
  if grep -qs '^llmsetup()' "$zshrc"; then
    say "warning: $(short "$zshrc") still defines llmsetup() itself; remove that copy"
  fi

  # Never commit the per-folder config dirs.
  local ignore entry
  ignore=$(git config --global core.excludesFile 2>/dev/null || true)
  ignore=${ignore/#\~/$HOME}
  ignore=${ignore:-${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore}
  mkdir -p "$(dirname "$ignore")"
  for entry in .claude-home/ .codex-home/; do
    if ! grep -qxF "$entry" "$ignore" 2>/dev/null; then
      append "$ignore" "$entry"
      say "added $entry to $(short "$ignore")"
    fi
  done

  local tool
  for tool in direnv uv claude; do
    command -v "$tool" >/dev/null || say "warning: $tool is not installed"
  done
  command -v codex >/dev/null || say "note: codex is not installed (only needed for the Codex plugin)"
  say "done; open a new terminal (or run: exec zsh)"
}

main "$@"
