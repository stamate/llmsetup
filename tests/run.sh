#!/usr/bin/env bash
# Tests for llmsessions and llmsetup, run against fake data in a temp folder.
# Nothing outside that folder is read or changed. Usage: tests/run.sh
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export UV_CACHE_DIR=${UV_CACHE_DIR:-$(uv cache dir)}
export UV_PYTHON_INSTALL_DIR=${UV_PYTHON_INSTALL_DIR:-$(uv python dir)}
T=$(mktemp -d)
H=$T/home            # fake $HOME
P=$H/work/proj       # a project folder with an llmsetup store
helper=
trap '[[ -n $helper ]] && kill "$helper" 2>/dev/null; rm -rf "${T:?}"' EXIT

fails=0
check() {  # check <description> <bash condition>
  if eval "$2"; then printf '  ok    %s\n' "$1"; else printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); fi
}

# ---------- fake Claude data ----------
session() {  # session <file> <cwd> <age, e.g. 2H> [extra JSON lines…]
  local file=$1 cwd=$2 age=$3; shift 3
  mkdir -p "$(dirname "$file")"
  { printf '{"type":"attachment","cwd":"%s"}\n' "$cwd"; printf '%s\n' "$@"; } > "$file"
  touch -t "$(date -v-"$age" +%Y%m%d%H%M.%S)" "$file"
}
user='{"type":"user","message":{"content":"hi"}}'
G=$H/.claude
session "$G/projects/-proj/s1.jsonl" "$P" 2H "$user" '{"type":"ai-title","aiTitle":"ai name"}' '{"type":"custom-title","customTitle":"First"}'
session "$G/projects/-proj/s1/subagents/a.jsonl" "$P" 2H "$user"
session "$G/projects/-proj/s2.jsonl" "$P" 3H "$user" '{"type":"ai-title","aiTitle":"Second"}'
session "$G/projects/-proj/s3.jsonl" "$P" 4H                      # no user message: hidden
session "$G/projects/-proj/s4.jsonl" "$P" 1H "$user" '{"type":"custom-title","customTitle":"Open one"}'
session "$G/projects/-other/o1.jsonl" "$H/work/other" 5d "$user"   # folder no longer exists
mkdir -p "$G/file-history/s1" "$G/todos" "$G/sessions" "$G/projects/-proj/memory" "$P/.claude-home"
echo v1 > "$G/file-history/s1/v1"
echo '[]' > "$G/todos/s1-agent.json"
echo '[]' > "$G/todos/s10-agent.json"                             # different session, shared prefix
echo notes > "$G/projects/-proj/memory/MEMORY.md"
sleep 300 & helper=$!                                               # stands in for an open session
printf '{"pid":%d,"sessionId":"s4"}\n' "$helper" > "$G/sessions/$helper.json"
mkdir -p "$H/.local/share/direnv/allow"
echo "$P/.envrc" > "$H/.local/share/direnv/allow/x"

sessions() {  # sessions <folder> <CLAUDE_CONFIG_DIR or ""> [args…]
  local dir=$1 cfg=$2; shift 2
  (cd "$dir" && env -u CLAUDE_CONFIG_DIR HOME="$H" XDG_DATA_HOME="$H/.local/share" COLUMNS=120 \
    ${cfg:+CLAUDE_CONFIG_DIR="$cfg"} "$repo/bin/llmsessions" "$@" < /dev/null 2>&1)
}
files() { (cd "$H" && find . -type f | sort); }

echo "llmsessions"
out=$(sessions "$P" "")
check "lists this folder's sessions with titles" '[[ $out == *First* && $out == *Second* && $out == *"Open one"* ]]'
check "custom title wins over the AI title" '[[ $out != *"ai name"* ]]'
check "hides sessions without a user message" '[[ $(grep -c global <<< "$out") == 3 ]]'
out=$(sessions "$H" "" -a)
check "overview counts sessions per folder" '[[ $out == *"global         3  ~/work/proj"* ]]'
check "overview marks deleted folders" '[[ $out == *"~/work/other (gone)"* ]]'

before=$(files)
sessions "$P" "$P/.claude-home" --to-folder -n > /dev/null
check "dry run changes nothing" '[[ $(files) == "$before" ]]'

out=$(sessions "$P" "$P/.claude-home" --to-folder)
F=$P/.claude-home
check "moves the transcript and its subagents" '[[ -f $F/projects/-proj/s1.jsonl && -f $F/projects/-proj/s1/subagents/a.jsonl ]]'
check "moves file-history and todos of the session" '[[ -f $F/file-history/s1/v1 && -f $F/todos/s1-agent.json ]]'
check "leaves another session with the same prefix" '[[ -f $G/todos/s10-agent.json && ! -e $F/todos/s10-agent.json ]]'
check "skips a session that is still open" '[[ $out == *"Open one: still running"* && -f $G/projects/-proj/s4.jsonl ]]'
check "moves Claude's memory for the folder" '[[ -f $F/projects/-proj/memory/MEMORY.md ]]'
check "listing shows the moved sessions in the folder store" '[[ $(grep -c folder <<< "$out") -ge 2 ]]'

sessions "$P" "$P/.claude-home" --to-global > /dev/null
check "moving back restores every file" '[[ $(files) == "$before" ]]'
out=$(sessions "$H/work" "" --to-folder)
check "refuses --to-folder without an llmsetup store" '[[ $out == *"run llmsetup here first"* ]]'

# ---------- llmsetup with stand-in claude, codex and direnv ----------
mkdir -p "$T/stub" "$T/state" "$H/work/new"
echo 1 > "$T/state/claude"; echo 1 > "$T/state/codex"     # 1 = not logged in
cat > "$T/stub/claude" <<EOF
#!/bin/sh
echo "claude \$*" >> "$T/calls"
case "\$1 \$2" in
  "auth status") exit \$(cat "$T/state/claude") ;;
  "auth login") echo 0 > "$T/state/claude" ;;
  "plugin install") mkdir -p "\$CLAUDE_CONFIG_DIR/plugins"
    echo '{"plugins":{"codex@openai-codex":[]}}' > "\$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" ;;
esac
EOF
cat > "$T/stub/codex" <<EOF
#!/bin/sh
echo "codex \$*" >> "$T/calls"
case "\$*" in
  "login status") exit \$(cat "$T/state/codex") ;;
  "login") echo 0 > "$T/state/codex" ;;
esac
EOF
printf '#!/bin/sh\necho "direnv $*" >> "%s/calls"\n' "$T" > "$T/stub/direnv"
chmod +x "$T/stub/"*

setup() {  # setup <folder>: run llmsetup there in a clean zsh
  (cd "$1" && HOME="$H" PATH="$T/stub:$PATH" zsh -f -c \
    "source '$repo/zsh/llmsetup.zsh'; llmsetup; print \"leak=\${CLAUDE_CONFIG_DIR-none}\"" 2>&1)
}

echo "llmsetup"
out=$(setup "$H/work/new")
check "writes 'use llmsetup' to .envrc" '[[ $(cat "$H/work/new/.envrc") == "use llmsetup" ]]'
check "adds the Codex plugin to the folder's own config" \
  'grep -q "plugin install codex@openai-codex" "$T/calls" && [[ -f $H/work/new/.claude-home/plugins/installed_plugins.json ]]'
check "signs in to Claude and Codex when needed" 'grep -qx "claude auth login" "$T/calls" && grep -qx "codex login" "$T/calls"'
check "leaves the calling shell's settings alone" '[[ $out == *leak=none* ]]'
: > "$T/calls"
out=$(setup "$H/work/new")
check "second run says it's already set up" '[[ $out == *"already set up"* ]]'
check "second run installs and signs in to nothing" '! grep -qE "install|auth login|^codex login$" "$T/calls"'
out=$(setup "$H")
check "refuses to run in ~" '[[ $out == *"refusing to run in ~"* && ! -e $H/.envrc ]]'

# ---------- install.sh / uninstall.sh, the way curl runs them ----------
src=$T/src                      # this checkout's current files as a git repo to install from
mkdir -p "$src"
(cd "$repo" && tar --exclude=.git -cf - .) | (cd "$src" && tar -xf -)
git -C "$src" init -q -b main
git -C "$src" add -A
git -C "$src" -c user.name=test -c user.email=test@example.invalid commit -q -m test
I=$T/fresh                      # another fake home
mkdir -p "$I/.local/bin" "$I/work/p" "$I/.local/share/direnv/allow"
echo 'export KEEP=1' > "$I/.zshrc"
echo 'my own script' > "$I/.local/bin/llmsessions"
echo 'use llmsetup' > "$I/work/p/.envrc"
echo "$I/work/p/.envrc" > "$I/.local/share/direnv/allow/p"

piped() {  # piped <script>: run it like `curl … | bash`, in the fake home
  env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u ZDOTDIR -u LLMSETUP_DIR HOME="$I" GIT_CONFIG_NOSYSTEM=1 \
    LLMSETUP_REPO="file://$src" bash < "$src/$1" 2>&1
}
copy=$I/.local/share/llmsetup

echo "install / uninstall"
out=$(piped install.sh)
check "one-liner downloads llmsetup" '[[ -f $copy/zsh/llmsetup.zsh ]]'
check "links llmsessions and the direnv helper into the copy" \
  '[[ $(readlink "$I/.local/bin/llmsessions") == "$copy/bin/llmsessions" && $(readlink "$I/.config/direnv/lib/llmsetup.sh") == "$copy/direnv/llmsetup.sh" ]]'
check "keeps a different existing llmsessions as .bak" '[[ $(cat "$I/.local/bin/llmsessions.bak") == "my own script" ]]'
check "adds the zsh line and keeps the rest of .zshrc" 'grep -q "zsh/llmsetup.zsh" "$I/.zshrc" && grep -qx "export KEEP=1" "$I/.zshrc"'
check "adds both entries to the global gitignore" 'grep -qx .claude-home/ "$I/.config/git/ignore" && grep -qx .codex-home/ "$I/.config/git/ignore"'
out=$(piped install.sh)
check "running it again updates instead of downloading" '[[ $out == *"updated ~/.local/share/llmsetup"* ]]'
check "running it again adds nothing twice" \
  '[[ $(grep -c llmsetup.zsh "$I/.zshrc") == 1 && $(grep -cx .claude-home/ "$I/.config/git/ignore") == 1 ]]'

out=$(piped uninstall.sh)
check "uninstall removes the links and puts back the old file" \
  '[[ ! -e $I/.config/direnv/lib/llmsetup.sh && $(cat "$I/.local/bin/llmsessions") == "my own script" && ! -e $I/.local/bin/llmsessions.bak ]]'
check "uninstall removes only the llmsetup line from .zshrc" '! grep -q llmsetup.zsh "$I/.zshrc" && grep -qx "export KEEP=1" "$I/.zshrc"'
check "uninstall deletes the downloaded copy" '[[ ! -e $copy ]]'
check "uninstall lists folders that still use llmsetup" '[[ $out == *"~/work/p"* ]]'
check "uninstall keeps the gitignore entries" 'grep -qx .claude-home/ "$I/.config/git/ignore"'
out=$(piped uninstall.sh); status=$?
check "running uninstall again is harmless" '[[ $status == 0 && $(cat "$I/.local/bin/llmsessions") == "my own script" ]]'

echo
if (( fails )); then echo "$fails failed"; exit 1; fi
echo "all passed"
