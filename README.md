# llmsetup

Give any folder its own Claude Code setup, and find your sessions again.

- **`llmsetup`** makes the current folder (and everything below it) use its own Claude Code config: its own login, settings, plugins, MCP servers and session history. It does this with a [direnv](https://direnv.net) `.envrc`. It also gives the folder its own Codex home and installs the [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc) there. Then it signs you in to both, but only where that's still needed.
- **`llmsessions`** lists the Claude Code sessions for the folder you're in and resumes the one you pick. It can also show every folder that has sessions, or move sessions between your global config (`~/.claude`) and a folder's own config.
- **Tab title:** with oh-my-zsh, your terminal tab shows `llm:<folder>` while a folder's own config is active.

## Requirements

- macOS or Linux with **zsh**
- **[direnv](https://direnv.net)**, hooked into zsh (oh-my-zsh's `direnv` plugin, or `eval "$(direnv hook zsh)"`)
- **[uv](https://docs.astral.sh/uv/)**, which runs `llmsessions` (Python standard library only, nothing to install)
- **Claude Code** (`claude`)
- Optional: the **Codex CLI** (`codex`), for the Codex plugin, and **oh-my-zsh**, for the tab title

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/stamate/llmsetup/main/install.sh | bash
```

Then open a new terminal. This keeps a copy in `~/.local/share/llmsetup`. Run the same line again to update.

To work on llmsetup itself, clone it anywhere and install from the clone instead:

```bash
git clone https://github.com/stamate/llmsetup.git && llmsetup/install.sh
```

Either way, the installer is safe to run again. It:

- links `~/.local/bin/llmsessions` and `~/.config/direnv/lib/llmsetup.sh` to the files in the copy or clone, so updating that is enough
- adds one `source …/zsh/llmsetup.zsh` line to the end of `~/.zshrc`
- adds `.claude-home/` and `.codex-home/` to your global gitignore

If a different file is already in place, it's kept as `*.bak`.

## Use

```bash
cd ~/some/project && llmsetup     # set up this folder (or finish setting it up)
```
```bash
llmsessions                       # this folder's sessions; pick one to resume
```
```bash
llmsessions 1                     # resume the newest one straight away
```
```bash
llmsessions -a                    # every folder with sessions: global vs folder config
```
```bash
llmsessions --to-folder -n        # preview: move this folder's global sessions into its own config
```
```bash
llmsessions --to-folder           # …do it (or pick some: --to-folder 2 3)
```
```bash
llmsessions --to-global           # move them back to ~/.claude
```

## How it works

- **`.envrc`:** `llmsetup` adds `use llmsetup` to the folder's `.envrc`. The direnv helper then sets:
  - `CLAUDE_CONFIG_DIR=<folder>/.claude-home`
  - `CODEX_HOME=<folder>/.codex-home`
- **Subfolders** use the nearest set-up parent's config. A subfolder with an `.envrc` of its own replaces the parent's, unless that `.envrc` starts with `source_up`. Run `llmsetup` in a subfolder to give it a separate config.
- **Where sessions live:** `<config>/projects/<folder path>/<session id>.jsonl`, plus files named after the session ID (`file-history/`, `session-env/`, `todos/`, subagent transcripts). `llmsessions` reads these directly. It finds every folder's config through direnv's list of allowed `.envrc` files.
- **Moving a session** moves all of those files to the same place in the other config. Open sessions and anything that would overwrite an existing file are skipped. Moving all of a folder's sessions also moves Claude's memory for that folder.
- **Resuming** runs `claude --resume <id>` in the session's folder, with `CLAUDE_CONFIG_DIR` pointing at the config the session lives in. That way sessions from before `llmsetup` can still be resumed.

## Good to know

- **Separate sign-ins:** each set-up folder is signed in separately, to Claude and to Codex. `llmsetup` runs `claude auth login` / `codex login` only when that folder isn't signed in yet.
- **Nothing global carries over:** inside a set-up folder, Claude doesn't read `~/.claude`. Your global `CLAUDE.md`, settings, plugins and user-level MCP servers don't apply there.
- **Old sessions disappear:** Claude Code deletes sessions older than 30 days by default (`cleanupPeriodDays` in settings).
- **Not in `~`:** `llmsetup` refuses to run in your home folder, because it would then apply to every folder below it.

## Tests

```bash
tests/run.sh
```

The tests use fake session data and stand-in `claude` / `codex` / `direnv` commands in a temp folder. Nothing on your machine is read or changed.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/stamate/llmsetup/main/uninstall.sh | bash
```

Or run `./uninstall.sh` from a clone. It:

- removes the two links (putting back any file the installer had set aside as `*.bak`)
- removes the line from `~/.zshrc` (a copy is kept as `~/.zshrc.llmsetup.bak`)
- deletes the downloaded copy in `~/.local/share/llmsetup`; a clone you made yourself is left alone

It also lists the folders that still have `use llmsetup` in their `.envrc`. direnv reports an error in those folders until you remove that line. Their `.claude-home` / `.codex-home`, with your logins and sessions, are kept. So are the global gitignore entries, so those folders' configs never get committed by accident.

## License

MIT, see [LICENSE](LICENSE).
