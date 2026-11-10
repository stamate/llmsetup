# Per-folder Claude Code / Codex config. In an .envrc:  use llmsetup
use_llmsetup() {
  export CLAUDE_CONFIG_DIR="$PWD/.claude-home"
  export CODEX_HOME="$PWD/.codex-home"
  mkdir -p "$CLAUDE_CONFIG_DIR" "$CODEX_HOME"   # Codex won't start if CODEX_HOME is missing
}
