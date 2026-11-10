# llmsetup: give a folder its own Claude Code (and Codex) config via direnv.
# Sourced from ~/.zshrc by install.sh, after oh-my-zsh. See README.md.

# Set up the current folder, or finish setting it up if it already is.
llmsetup() {
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
