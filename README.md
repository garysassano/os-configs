# os-configs

Personal machine configuration, versioned so a rebuild is reproducible rather
than remembered. The live machine is the source of truth; this repository is a
snapshot of it, refreshed by scripts rather than by hand.

Primary environment is Ubuntu 24.04 under WSL2, with VS Code running on the
Windows host and connecting into the WSL remote.

## Layout

| Path | Contents |
| --- | --- |
| `ubuntu/` | WSL environment — shell, agent configuration, mise, git, Codex, VS Code remote extensions |
| `windows/` | Windows host — VS Code settings and extensions, fonts, scheduled tasks |
| `macos/` | VS Code keybindings only; kept as an archive, not synced |

Files sit at the path they occupy in the real home directory, so
`ubuntu/.config/fish/config.fish` is `~/.config/fish/config.fish`.

## What is here

**Shell.** fish is the interactive shell; `ubuntu/.config/fish/config.fish` holds
all of it. `ubuntu/.profile` looks stock but is load-bearing: agent harnesses
spawn `bash -lc`, `~/.bashrc` returns early on its non-interactive guard, and the
appended mise shims block is the only reason a spawned bash resolves `rg` to the
mise build rather than `/usr/bin/rg`. Do not delete it. `~/.bashrc` and
`~/.bash_aliases` were reset to the Ubuntu skeleton in July 2026 and are no
longer tracked.

**Tools.** `ubuntu/.config/mise/config.toml` is the authoritative list of CLI
tooling. Everything is installed through [mise](https://mise.jdx.dev/) so
versions are pinned and reproducible; nothing is installed imperatively via
`cargo install`, `npm i -g`, or `brew`. Tools that churn or break across versions
are pinned explicitly, the rest track `latest`.

**Agents.** `ubuntu/.agents/` is the canonical source for agent configuration —
one `AGENTS.md` and one skills directory, shared across every harness. No
cross-harness standard exists for where those live, so `ubuntu/.agents/link.sh`
symlinks them into each one.

| Canonical | Fanned out to |
| --- | --- |
| `AGENTS.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.codex-kiro/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.config/opencode/AGENTS.md` |
| `skills/` | `~/.claude/skills/`, `~/.codex/skills/`, `~/.codex-kiro/skills/`, `~/.kiro/skills/` |

Claude Code reads `CLAUDE.md` and never `AGENTS.md`, hence the rename in that
one target. `~/.claude/skills/` also serves opencode, which reads Claude Code
skills. The generated symlinks are gitignored — they describe one machine's
installed harnesses, and `link.sh` regenerates them.

**Git identity.** `ubuntu/.gitconfig` and `ubuntu/git-mushi/.gitconfig` together
give directory-scoped identity and credential selection. The `gh` wrapper in
`ubuntu/.local/bin/` pulls the matching token from the credential helper so the
right account is used per checkout.

## Refreshing the snapshot

Both scripts read the live machine and write here. Neither commits, pushes, nor
touches the live machine. Review the diff before staging.

```bash
ubuntu/.agents/skills/os-config-sync/scripts/sync-from-home.sh
ubuntu/.agents/skills/os-config-sync/scripts/sync-vscode.sh
```

`sync-from-home.sh` captures the shell, agent, mise, git, and Codex
configuration. `sync-vscode.sh` captures VS Code settings, keybindings,
snippets, and the two extension lists — Windows host and WSL remote are separate
sets and not interchangeable. It replaced the manual `Default.code-profile`
export, which was 78% window-layout state and produced unreadable diffs.

Both refuse to run when a credential-shaped string appears in a source file; the
shared scan lives in `scripts/lib/scan-secrets.sh`. Full operating notes are in
`ubuntu/.agents/skills/os-config-sync/SKILL.md`.

## Applying to a machine

```bash
ubuntu/.agents/link.sh --dry-run   # preview
ubuntu/.agents/link.sh             # create the harness symlinks
```

`link.sh` is idempotent and only ever creates symlinks pointing into
`~/.agents`, prunes symlinks left dangling by a deleted skill, and skips
harnesses that are not installed. Run it after installing a harness, after
adding or removing a skill, and after every `npx skills`, which writes real
directories into the harnesses it was told about and silently skips the rest.

Restoring VS Code is not one command, which is the cost of dropping the profile
export. Copy the files back, then:

```bash
xargs -n1 code --install-extension < ubuntu/vs-code/extensions.txt
```

## Conventions

- Never commit credentials, tokens, session history, caches, or binaries.
- Never commit the derived harness symlinks; `link.sh` owns them.
- Keep mise the owner of tool versions. Wrappers resolve mise-managed
  executables dynamically rather than pinning install paths.
- Shell scripts are checked with `shellcheck -x` and `shfmt`, TOML with `taplo`.
