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

echo
if (( fails )); then echo "$fails failed"; exit 1; fi
echo "all passed"
