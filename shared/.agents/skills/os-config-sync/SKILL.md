---
name: os-config-sync
description: Refresh the Ubuntu or macOS snapshot in the os-configs repository from the current machine's maintained configuration. Use when asked to update, synchronize, capture, or publish local machine configuration changes in os-configs.
---

# OS Config Sync

Synchronize maintained configuration from the live home directory into this repository without copying credentials, generated system skills, plugin caches, binaries, or temporary development launchers.

## Workflow

1. Work from the `os-configs` repository and confirm the worktree state before changing files. Preserve unrelated changes.
2. Read `scripts/sync-from-home.sh` before running it. Update its explicit wrapper allowlist when a new durable wrapper belongs in the snapshot.
3. Run `scripts/sync-from-home.sh`. The script copies:
   - `~/.agents/AGENTS.md`
   - `~/.agents/link.sh`, the harness fan-out script
   - `~/.agents/.skill-lock.json`, npx skills' record of which skills are vendored and which harnesses it targets
   - `~/.config/fish/config.fish`, the interactive shell configuration
   - `~/.profile`, which is stock Ubuntu apart from a mise shims block; see below
   - all visible directories under `~/.agents/skills/`, additively: a repository skill with no counterpart here is left in place and flagged for manual review, never deleted

   The canonical `~/.agents/` set — `AGENTS.md`, `link.sh`, `.skill-lock.json`, and `skills/` — lands under `shared/.agents/` because it is OS-independent; the per-OS files below land under `ubuntu/`. The harness copies link.sh fans out (`~/.codex/AGENTS.md`, `~/.codex/skills/`, `~/.claude/skills/`, …) are symlinks, gitignored, and never captured.
   - `~/.claude/settings.json`, and the preference keys of `~/.claude.json` filtered through an explicit allowlist; the rest of that file is app-managed state and stays out
   - `~/.codex/config.toml`
   - `~/.config/mise/config.toml` and the adjacent `.taplo.toml` formatting policy
   - `~/.config/oh-my-posh/themes/multiverse-neon.omp.json`
   - `~/.config/opencode/opencode.jsonc`, named individually rather than by directory: that directory accumulates provider state beside it, and the Kiro integration removed on 2026-08-07 kept a live `clientSecret` in `kiro-oidc-clients.json`
   - `~/.config/git/allowed_signers`, which maps a signing identity to its public key so `git log --show-signature` can name the signer. Public keys only
   - `~/.granted/config`, WSL-only — granted cannot defer to `$BROWSER` or `xdg-open`, so it names the Windows Firefox binary by absolute path and a macOS machine needs its own copy
   - `~/.local/share/applications/wsl-explorer.desktop`, the URL handler `$BROWSER` and `xdg-open` resolve to; WSL-only, it execs `explorer.exe`
   - `~/.gitconfig`, which preserves directory-scoped Git identity and credential selection rules. Referenced account-specific `~/git-<name>/.gitconfig` files remain local and are never captured
   - `~/.reasonix/config.toml`, named individually rather than by directory: the sibling `.env` holds provider API keys
   - explicitly allowlisted wrappers from `~/.local/bin/`
4. Review the complete diff. Remove machine-generated state, credentials, tokens, caches, compiled binaries, transient test files, and wrappers tied to temporary build paths.
5. Run the validations printed by the script, plus the skill validator for every new or changed skill when it is available.
6. Confirm executable bits for scripts and wrappers, run `git diff --check`, then commit and push only when requested.

## macOS

Run `scripts/sync-macos-from-home.sh` on macOS. It captures:

- `~/.config/fish/config.fish`
- `~/.profile`, a shim-only fallback for POSIX login shells and explicit
  `bash -lc` subprocesses; interactive setup remains in fish
- the personal `~/.config/mise/config.toml`
- the adjacent Taplo and markdownlint policies
- the Oh My Posh theme at `~/.config/oh-my-posh/themes/multiverse-neon.omp.json`
- `~/.config/opencode/opencode.json`, named individually so generated package
  state and the `AGENTS.md` symlink beside it stay out
- the portable preference subset of `~/.codex/config.toml`; OpenCodex-injected
  model, proxy, catalog, plugin state, hooks, and project trust stay local
- the allowlisted preference subset of `~/.claude.json`
- VS Code settings, keybindings, and extensions

The Mac sync names every source file explicitly. It must never capture
`config.devops.toml`, `shared_tasks/`, `packages/`, README files, or any other
work or organization content near the personal mise config. It leaves the
work-specific `~/.gitconfig` out of this personal snapshot.

## Shells

fish is the interactive shell on both maintained systems;
`~/.config/fish/config.fish` holds everything. The OS snapshots remain separate
because paths, browser integration, and keyboard behavior differ.
`~/.bashrc` and `~/.bash_aliases` were reset to the Ubuntu skeleton on
2026-07-25 and are no longer tracked.

`~/.profile` stays tracked and must not be deleted. It is stock Ubuntu plus one
appended block that puts `~/.local/share/mise/shims` on `PATH`. That block is
load-bearing: agent harnesses spawn `bash -lc`, `~/.bashrc` returns early on the
non-interactive guard, and without the shims a spawned bash resolves `rg` to
`/usr/bin/rg` rather than the mise-managed build the global AGENTS.md tells
agents to prefer. Only `config.fish` gets `mise activate`, and only when
interactive.

macOS has a smaller `~/.profile` for the same class of explicit `bash -lc` and
POSIX-login subprocesses. Fish does not read it; it only exposes mise shims and
`~/.local/bin`, while interactive activation remains in `config.fish`.

Capture only `config.fish`. `conf.d/`, `functions/`, and `completions/` are kept
empty **deliberately** — every interactive setting lives in `config.fish` so there
is one file to read and one file to sync. A snippet dropped into `conf.d/` works on
the live machine but is silently absent from the snapshot, so a rebuild loses it.
If you add shell configuration, add it to `config.fish`. `fish_variables` is
regenerated stock state and stays untracked.

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
- On macOS, treat `macos/` as the snapshot destination and copy only the
  explicit allowlist in `sync-macos-from-home.sh`.
- Keep `shared/.agents/skills/os-config-sync/` repository-owned; the sync operation must not delete it merely because it is absent from the live skills directory.
- Keep `shared/.agents/AGENTS.md` canonical. The per-harness copies — `~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md`, and the rest — are link.sh symlinks, gitignored, and never tracked.
- Never commit the derived harness symlinks. `link.sh` regenerates them from `~/.agents/`; snapshotting them would encode one machine's installed harnesses.
- Treat `ubuntu/.claude.json` as a filtered subset rather than a copy, in both directions: capture only the allowlisted preference keys, and never restore it over an existing `~/.claude.json`, which would drop that machine's account and project history.
- Do not copy `~/.codex/plugins/`, credentials, authentication databases, session history, memories, caches, logs, or binaries. `~/.codex/skills/` is no longer captured at all — it holds only link.sh symlinks plus the excluded `.system/` tree.
- Filter portable Codex preferences out of `~/.codex/config.toml` on both OSes,
  dropping the block OpenCodex injects while it shims Codex. OpenCodex's own
  `~/.opencodex/` tree is never captured on either machine.
- Copy Git credential-helper configuration and usernames, but never credentials returned by the helper.
- Do not infer that every file in `~/.local/bin/` is a wrapper. Add only reviewed, portable shell wrappers to the allowlist.
- Preserve mise as the owner of tool versions. Wrappers should resolve mise-managed executables dynamically rather than pinning mise installation paths or versions.
- For any non-registry tool, declare a `[tool_alias]` and use the alias in
  `[tools]`. Keep explicit `cargo:` declarations for tools intentionally
  installed through the Cargo backend.
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

The macOS snapshot carries its own settings and keybindings because terminal
paths and keyboard remapping differ. Its extension list otherwise contains the
Windows host baseline, excluding only `ms-vscode-remote.remote-wsl`; additional
native Mac extensions are allowed.

## Scripts

Run from the repository root; none of these scripts commits or pushes:

```bash
shared/.agents/skills/os-config-sync/scripts/sync-from-home.sh
shared/.agents/skills/os-config-sync/scripts/sync-macos-from-home.sh
shared/.agents/skills/os-config-sync/scripts/sync-vscode.sh
```
