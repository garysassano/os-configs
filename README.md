# os-configs

Personal machine configuration, versioned so a rebuild is reproducible rather
than remembered. The live machine is the source of truth; this repository is a
snapshot of it, refreshed by scripts rather than by hand.

Primary environment is Ubuntu 24.04 under WSL2, with VS Code running on the
Windows host and connecting into the WSL remote.

## Layout

| Path | Contents |
| --- | --- |
| `ubuntu/` | WSL environment — shell, agent configuration, mise, git, Codex, Claude Code, VS Code remote extensions |
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

**Terminal.** VS Code's integrated terminal is the only terminal; it runs fish
and Explorer's *Open in Terminal* opens it in place rather than an external
window. Ghostty filled the external-window role until July 2026 and was dropped
once the integrated terminal stopped corrupting TUI output — see the
`gpuAcceleration` note in `windows/vs-code/settings.json`.

**Tools.** `ubuntu/.config/mise/config.toml` is the authoritative list of CLI
tooling. Everything is installed through [mise](https://mise.jdx.dev/) so
versions are pinned and reproducible; nothing is installed imperatively via
`cargo install`, `npm i -g`, or `brew`. Tools that churn or break across versions
are pinned explicitly, the rest track `latest`. The adjacent `.taplo.toml` owns
the formatting policy for this config, including alphabetical key ordering;
VS Code's Even Better TOML extension keeps its bundled Taplo server and only
triggers that policy on save. VS Code points to that configuration explicitly
so Taplo also applies it when a TOML file is opened outside the current
workspace. The Biome extension is intentionally left to
auto-discover a project-local binary and configuration first, then fall back to
the mise-managed Biome on `PATH`; no versioned install path or project-specific
`biome.json` path belongs in global VS Code settings.
Prettier and markdownlint are pointed at explicitly for the same reason Taplo is: `prettier.prettierPath` resolves to the mise install so Ctrl-S matches the terminal, and `markdownlint.configFile` resolves to `ubuntu/.markdownlint.jsonc`, which turns MD013 off so prose is never hard-wrapped.
Both are base configuration only — a repository pinning its own Prettier or shipping its own `.markdownlint.*` still wins.

**Agents.** `ubuntu/.agents/` is the canonical source for agent configuration —
one `AGENTS.md` and one skills directory, shared across every harness. No
cross-harness standard exists for where those live, so `ubuntu/.agents/link.sh`
symlinks them into each one.

| Canonical | Fanned out to |
| --- | --- |
| `AGENTS.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.codex-kiro/AGENTS.md`, `~/.config/opencode/AGENTS.md` |
| `skills/` | `~/.claude/skills/`, `~/.codex/skills/`, `~/.codex-kiro/skills/`, `~/.kiro/skills/` |

Claude Code reads `CLAUDE.md` and never `AGENTS.md`, hence the rename in that
one target. `~/.claude/skills/` also serves opencode, which reads Claude Code
skills. The generated symlinks are gitignored — they describe one machine's
installed harnesses, and `link.sh` regenerates them.

Harness settings sit beside the instructions: `ubuntu/.codex/config.toml` and
`ubuntu/.claude/settings.json`. Claude Code splits its configuration across two
files, so `ubuntu/.claude.json` carries the preference keys of the second one,
filtered to an allowlist — the rest of that file is the signed-in account,
per-project history, and caches, and stays out.

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

## Restoring onto a new machine

Files sit at the path they occupy in the real home directory, but the tree is not
a blanket copy target. Two paths are repository-owned and have no live-home
counterpart, so copying them into `~` is wrong:

| Path | Why it is not a home file |
| --- | --- |
| `ubuntu/.agents/skills/os-config-sync/` | The sync skill itself, edited here rather than under `~`. Placing it in `~/.agents/skills/` would make the skill loop copy it back over itself. |
| `ubuntu/vs-code/` | VS Code remote artifacts, restored by the steps below rather than by path. |

Everything else under `ubuntu/` restores to the matching path in `~`.

`ubuntu/.claude.json` is the one partial file in the tree — Claude Code's
preference keys only, since the rest of that file is the signed-in account,
per-project history, and caches. Restore it to a machine with no `~/.claude.json`
yet and the first launch fills the remainder in around it, preserving the
preferences. Copying it over an existing one would replace that machine's account
and history with nothing.

1. **Prerequisites.** WSL2 with Ubuntu 24.04, Git for Windows on the host so Git
   Credential Manager exists at the path `credential.helper` names, and
   [mise](https://mise.jdx.dev/).
2. **Restore the live-home files**, excluding the two paths above. `~/.profile`
   matters more than it looks — see *What is here*.
3. **`mise install`** to materialise the pinned toolchain from
   `ubuntu/.config/mise/config.toml`.
4. **Create the account trees** before anything needs them. `~/git/` is the
   primary account and `~/git-<name>/` each secondary one; the `includeIf` rules
   in `ubuntu/.gitconfig` select identity by tree, so a tree that does not exist
   selects nothing.
5. **Sign each account into Git Credential Manager**, which is where the tokens
   live — this repository holds none:

   ```bash
   helper="$(git config --global --get credential.helper)"
   "${helper//\\ / }" github login   # once per account; list them with: github list
   ```

   The expansion undoes the escaping Git applies to a helper path containing
   spaces; the configured value is not a shell command and running it through
   `eval` would treat it as one.

   Never run `gh auth login`. It gives `gh` a stored account, and that account
   becomes a global default overriding the per-directory selection the wrapper
   exists to guarantee.
6. **Leave `~/.config/gh/hosts.yml` absent or `{}`.** Either state is correct;
   anything else means step 5 was done the wrong way.
7. **`ubuntu/.agents/link.sh`** to fan the canonical agent configuration into each
   installed harness (see below).
8. **Verify**, from the cloned repository:

   ```bash
   ubuntu/.agents/skills/os-config-sync/scripts/test-gh-wrapper.sh ~/git/<repo> ~/git-<name>/<repo>
   ```

   It needs two repositories mapping to different accounts, and exits non-zero
   with an explanation if either account or its credential is missing.

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
