# llmsetup: give a folder its own Claude Code (and Codex) config via direnv.
# Sourced from ~/.zshrc by install.sh, after oh-my-zsh. See README.md.

_llmsetup_help() {
  cat <<'EOF'
Usage: llmsetup

Give the current folder (and everything below it) its own Claude Code and Codex
setup: own login, settings, plugins, MCP servers and session history.

  - adds `use llmsetup` to .envrc and runs `direnv allow`
  - config goes in .claude-home/ and .codex-home/ inside the folder
  - installs the Codex plugin there, and signs you in to Claude and Codex
    if this folder isn't signed in yet
  - if this folder's Claude sessions or notes are still in ~/.claude, lists
    them and asks whether to move them in (subfolders: llmsessions --to-folder)

Safe to run again: it only does what's missing. Undo it by removing the
`use llmsetup` line from .envrc (the config folders are kept).

Sessions: `llmsessions --help` lists, resumes and moves them between
~/.claude and a folder's own config.
EOF
}

# Set up the current folder, or finish setting it up if it already is.
llmsetup() {
  case $1 in
    '') ;;
    -h|--help) _llmsetup_help; return ;;
    *) echo "llmsetup: unknown option '$1' (see llmsetup --help)" >&2; return 2 ;;
  esac
  if grep -Eqs '^[[:space:]]*(use llmsetup|export CLAUDE_CONFIG_DIR=)' .envrc; then
    echo "llmsetup: already set up in ${PWD/#$HOME/~}"
  else
    [[ $PWD != $HOME ]] || { echo "llmsetup: refusing to run in ~ (it would apply to every folder below)" >&2; return 1; }
    [[ $CLAUDE_CONFIG_DIR == */.claude-home ]] &&
      echo "llmsetup: was sharing ${${CLAUDE_CONFIG_DIR:h}/#$HOME/~}'s config; this folder now has its own"
    [[ -s .envrc && -n $(tail -c1 .envrc) ]] && echo >> .envrc
    echo 'use llmsetup' >> .envrc
  fi
  direnv allow || return
  _llmsetup_ready "$PWD"
  _llmsetup_offer_move
}

# This folder's sessions and notes still in ~/.claude: list them and offer to move them in.
_llmsetup_offer_move() {
  [[ -t 0 ]] && (( $+commands[llmsessions] )) || return 0
  local preview answer
  preview=$(llmsessions --to-folder -n 2>/dev/null) && [[ $preview == *"would move"* ]] || return 0
  echo "llmsetup: this folder still has Claude sessions or notes in ~/.claude:"
  print -r -- "${preview//would move/ }"
  read -r "answer?llmsetup: move them into this folder's config? [y/N] "
  if [[ $answer == [yY]* ]]; then
    llmsessions --to-folder
  else
    echo "llmsetup: left them in ~/.claude (move them later with: llmsessions --to-folder)"
  fi
}

# The folder's own Claude and Codex: Codex plugin, then logins. Each step only if missing.
_llmsetup_ready() (
  export CLAUDE_CONFIG_DIR="$1/.claude-home" CODEX_HOME="$1/.codex-home"
  mkdir -p "$CLAUDE_CONFIG_DIR" "$CODEX_HOME"
  if ! grep -qs 'codex@openai-codex' "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"; then
    echo "llmsetup: adding the Codex plugin for this folder"
    { claude plugin marketplace add openai/codex-plugin-cc && claude plugin install codex@openai-codex; } >/dev/null ||
      echo "llmsetup: Codex plugin install failed" >&2
  fi
  claude auth status >/dev/null 2>&1 || { echo "llmsetup: sign in to Claude for this folder"; claude auth login; }
  codex login status >/dev/null 2>&1 || { echo "llmsetup: sign in to Codex for this folder"; codex login; }
)

# Tab title: prefix "llm:<folder>" while an llmsetup config is active. Uses oh-my-zsh's
# `title`, runs after its own title hook and only overrides it in set-up folders.
_llmsetup_title() {
  (( $+functions[title] )) || return 0
  [[ $CLAUDE_CONFIG_DIR == */.claude-home ]] || return 0
  local tag="llm:${${CLAUDE_CONFIG_DIR:h:t}//\%/%%}"
  title "$tag %15<..<%~%<<" "$tag %~"
}
precmd_functions=(${precmd_functions:#_llmsetup_title} _llmsetup_title)
