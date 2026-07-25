## Packages

Default to the latest stable version. Exceptions: the user asks otherwise, or the project documents a compatibility constraint.

## Repos

`~/git/` is personal work on the main GitHub account. `~/git-<name>/` is a
secondary account or client work: separate identity, separate credentials, and
possibly client-confidential material. Never copy content, credentials, or
configuration out of a `~/git-<name>/` tree into anything under `~/git/`, and
don't read from one unless the task is about that client.

## GitHub CLI

`gh` runs through `~/.local/bin/gh`, which picks the account from the working
directory: `~/.gitconfig`'s `includeIf` rules map each tree to an account, and the
wrapper hands `gh` that account's Git Credential Manager token. Never choose an
account yourself and never supply one.

- Run `gh` from inside the repository it should act on. Outside a Git worktree the
  wrapper refuses rather than guessing, so `--repo` from an arbitrary directory
  does not work.
- Never set `GH_TOKEN` or `GITHUB_TOKEN`. The wrapper discards them, but a `gh`
  reached any other way would honour them and act as the wrong account.
- Of `gh auth`, only `status` and the help forms are permitted; every other shape
  is rejected. gh stores no account here, and giving it one creates a global
  default that overrides per-directory selection, so `~/.config/gh/hosts.yml` stays
  `{}`. `--show-token` is refused too, since transcripts are kept.
- Credentials are maintained through Git Credential Manager, not gh. It is not on
  `$PATH`; invoke the configured helper by its path (`git config --global --get
  credential.helper` prints it):
  `/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe github
  list|login|logout <account>`.

This is a guardrail against accidental identity leakage, not a security boundary —
`$(mise which gh)` bypasses it.

## Tools

CLI tools are [mise](https://mise.jdx.dev/)-managed and on `$PATH`. `~/.config/mise/config.toml` is the authoritative list — read it before suggesting an install. Runtime check: `mise ls --installed`.

Prefer them over conventional equivalents: `rg`/`fd`/`bat`/`eza` over `grep`/`find`/`cat`/`ls`, `jq` for JSON, `yq` for YAML/XML/TOML, `taplo` for TOML lint/format, `shellcheck` + `shfmt` for shell.

Missing a tool? Propose adding it to `config.toml`. Never install imperatively (`cargo install`, `npm i -g`, `brew install`, manual binary downloads) — that breaks version pinning and cross-machine reproducibility.
