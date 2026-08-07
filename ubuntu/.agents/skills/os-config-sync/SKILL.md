---
name: os-config-sync
description: Refresh the Ubuntu snapshot in the os-configs repository from the current machine's shell startup files, global agent instructions, user-authored agent and Codex skills, Codex configuration, mise configuration, and durable command wrappers. Use when asked to update, synchronize, capture, or publish local Ubuntu configuration changes in os-configs.
---

# OS Config Sync

Synchronize the maintained Ubuntu configuration from the live home directory into this repository without copying credentials, generated system skills, plugin caches, binaries, or temporary development launchers.

## Workflow

1. Work from the `os-configs` repository and confirm the worktree state before changing files. Preserve unrelated changes.
2. Read `scripts/sync-from-home.sh` before running it. Update its explicit wrapper allowlist when a new durable wrapper belongs in the snapshot.
3. Run `scripts/sync-from-home.sh`. The script copies:
   - `~/.agents/AGENTS.md`
   - `~/.agents/link.sh`, the harness fan-out script
   - `~/.agents/.skill-lock.json`, npx skills' record of which skills are vendored and which harnesses it targets
   - the `~/.codex/AGENTS.md` compatibility symlink to the canonical global instructions
   - `~/.config/fish/config.fish`, the interactive shell configuration
   - `~/.profile`, which is stock Ubuntu apart from a mise shims block; see below
   - all visible directories under `~/.agents/skills/`
   - all visible user-authored directories under `~/.codex/skills/`; the hidden `.system/` directory and plugin caches are excluded
   - `~/.claude/settings.json`, and the preference keys of `~/.claude.json` filtered through an explicit allowlist; the rest of that file is app-managed state and stays out
   - `~/.codex/config.toml`
   - `~/.config/mise/config.toml` and the adjacent `.taplo.toml` formatting policy
   - `~/.cargo/config.toml` and `~/.config/oh-my-posh/themes/multiverse-neon.omp.json`
   - `~/.config/opencode/kiro.json` and `~/.config/opencode/opencode.jsonc`, named individually rather than by directory: the sibling `kiro-oidc-clients.json` holds a live `clientSecret`
   - `~/.gnupg/gpg-agent.conf` and `~/.granted/config`, both WSL-only — they point at `pinentry.exe` and the Windows Firefox binary, so a macOS machine needs its own copies rather than these
   - `~/.gitconfig` and `~/git-mushi/.gitconfig`, which together preserve directory-scoped Git identity and credential selection. `~/git-mushi/` is a personal secondary account and is the only `~/git-<name>/` tree captured; client trees are never synced
   - `~/.reasonix/config.toml`, named individually rather than by directory: the sibling `.env` holds provider API keys
   - explicitly allowlisted wrappers from `~/.local/bin/`
4. Review the complete diff. Remove machine-generated state, credentials, tokens, caches, compiled binaries, transient test files, and wrappers tied to temporary build paths.
5. Run the validations printed by the script, plus the skill validator for every new or changed skill when it is available.
6. Confirm executable bits for scripts and wrappers, run `git diff --check`, then commit and push only when requested.

## Shells

fish is the interactive shell; `~/.config/fish/config.fish` holds everything.
`~/.bashrc` and `~/.bash_aliases` were reset to the Ubuntu skeleton on
2026-07-25 and are no longer tracked.

`~/.profile` stays tracked and must not be deleted. It is stock Ubuntu plus one
appended block that puts `~/.local/share/mise/shims` on `PATH`. That block is
load-bearing: agent harnesses spawn `bash -lc`, `~/.bashrc` returns early on the
non-interactive guard, and without the shims a spawned bash resolves `rg` to
`/usr/bin/rg` rather than the mise-managed build the global AGENTS.md tells
agents to prefer. Only `config.fish` gets `mise activate`, and only when
interactive.

Capture only `config.fish`. `conf.d/`, `functions/`, and `completions/` are
empty, and `fish_variables` is regenerated stock state.

## Harness fan-out

`~/.agents/` is the single source of truth. Every harness reads its own path, and
no cross-harness standard exists, so `~/.agents/link.sh` symlinks the canonical
files into each one. It is idempotent — run it after installing a harness, after
adding or deleting a skill, and after every `npx skills` invocation, which writes
real directories into the harnesses it was told about and silently skips the rest.

| Canonical | Harness targets |
| --- | --- |
| `~/.agents/AGENTS.md` | `~/.claude/CLAUDE.md` (Claude Code reads `CLAUDE.md` only), `~/.codex/AGENTS.md`, `~/.codex-kiro/AGENTS.md`, `~/.config/opencode/AGENTS.md` |
| `~/.agents/skills/` | `~/.claude/skills/` (also serves opencode), `~/.codex/skills/`, `~/.codex-kiro/skills/`, `~/.kiro/skills/` |

Preview with `link.sh --dry-run`. The script creates only symlinks pointing into
`~/.agents`, prunes only symlinks that point at a deleted skill, skips harnesses
whose config directory does not exist, and backs up a non-empty regular file to
`.bak` before replacing it. Harness-owned real directories, such as the
Codex-only skills and every `.system/` directory, are never touched.

Add a new harness by extending `instruction_targets` or `skill_targets` in
`link.sh`. Verify the path the harness actually reads before adding it; do not
infer the filename from another harness.

## Boundaries

- Treat the live home directory as the source and `ubuntu/` as the snapshot destination.
- Keep `ubuntu/.agents/skills/os-config-sync/` repository-owned; the sync operation must not delete it merely because it is absent from the live skills directory.
- Keep `ubuntu/.agents/AGENTS.md` canonical and `ubuntu/.codex/AGENTS.md` as a relative symlink to it.
- Never commit the derived harness symlinks. `link.sh` regenerates them from `~/.agents/`; snapshotting them would encode one machine's installed harnesses.
- Treat `ubuntu/.claude.json` as a filtered subset rather than a copy, in both directions: capture only the allowlisted preference keys, and never restore it over an existing `~/.claude.json`, which would drop that machine's account and project history.
- Do not copy `~/.codex/skills/.system/`, `~/.codex/plugins/`, credentials, authentication databases, session history, memories, caches, logs, or binaries.
- Copy Git credential-helper configuration and usernames, but never credentials returned by the helper.
- Do not infer that every file in `~/.local/bin/` is a wrapper. Add only reviewed, portable shell wrappers to the allowlist.
- Preserve mise as the owner of tool versions. Wrappers should resolve mise-managed executables dynamically rather than pinning mise installation paths or versions.
- Keep shell initialization consistent with the captured tool configuration: activate mise before invoking mise-managed tools and put `~/.local/bin` before mise when local wrappers must take precedence.
- Stop before staging if the privacy scan reports a possible secret; inspect and sanitize the source instead of weakening the scan.

## VS Code

`scripts/sync-vscode.sh` replaced the manual `Default.code-profile` export on
2026-07-25. That format was 78% `globalState` — window layouts, recently opened
paths, walkthrough progress — and double-escaped every payload onto one line, so
diffs were unreadable and each refresh needed a manual export from the UI.

It captures `settings.json`, `keybindings.json`, and `snippets/` from
`/mnt/c/Users/Gary/AppData/Roaming/Code/User/`, plus two extension lists that are
not interchangeable: UI extensions install on the Windows host, workspace
extensions install into the WSL remote.

| Snapshot | Source |
| --- | --- |
| `windows/vs-code/settings.json`, `keybindings.json`, `snippets/` | Windows user directory over `/mnt/c` |
| `windows/vs-code/extensions.txt` | `cmd.exe /c "code --list-extensions"` |
| `ubuntu/vs-code/extensions.txt` | `code --list-extensions` in the WSL remote |

`code.cmd` is a batch file, so it needs `cmd.exe`; running it directly makes
`/bin/sh` try to execute `@echo`. The remote CLI prefixes its output with a
banner line, so both lists are filtered to `publisher.name` identifiers. An empty
list aborts rather than truncating the snapshot.

Restoring is not one click, which is the cost of dropping the export:

```bash
xargs -n1 code --install-extension < ubuntu/vs-code/extensions.txt
```

## Scripts

Run from the repository root; neither script commits or pushes:

```bash
ubuntu/.agents/skills/os-config-sync/scripts/sync-from-home.sh
ubuntu/.agents/skills/os-config-sync/scripts/sync-vscode.sh
```
