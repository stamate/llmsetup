#!/usr/bin/env bash
# Link llmsetup into place. Safe to run again: it only does what is missing.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
say() { printf 'install: %s\n' "$*"; }
short() { if [[ $1 == "$HOME"/* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi; }

# Append a line to a file, starting on a fresh line.
append() {
  [[ -s $1 && -n $(tail -c1 "$1") ]] && echo >> "$1"
  printf '%s\n' "$2" >> "$1"
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

link bin/llmsessions "$HOME/.local/bin/llmsessions"
link direnv/llmsetup.sh "${XDG_CONFIG_HOME:-$HOME/.config}/direnv/lib/llmsetup.sh"

# zsh functions, loaded at the end of ~/.zshrc (after oh-my-zsh).
zshrc=${ZDOTDIR:-$HOME}/.zshrc
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

for tool in direnv uv claude; do
  command -v "$tool" >/dev/null || say "warning: $tool is not installed"
done
command -v codex >/dev/null || say "note: codex is not installed (only needed for the Codex plugin)"
say "done; open a new terminal (or run: exec zsh)"
