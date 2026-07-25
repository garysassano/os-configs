## Packages

Default to the latest stable version. Exceptions: the user asks otherwise, or the project documents a compatibility constraint.

## Repos

`~/git/` is personal work on the main GitHub account. `~/git-<name>/` is a
secondary account or client work: separate identity, separate credentials, and
possibly client-confidential material. Never copy content, credentials, or
configuration out of a `~/git-<name>/` tree into anything under `~/git/`, and
don't read from one unless the task is about that client.

## Tools

CLI tools are [mise](https://mise.jdx.dev/)-managed and on `$PATH`. `~/.config/mise/config.toml` is the authoritative list — read it before suggesting an install. Runtime check: `mise ls --installed`.

Prefer them over conventional equivalents: `rg`/`fd`/`bat`/`eza` over `grep`/`find`/`cat`/`ls`, `jq` for JSON, `yq` for YAML/XML/TOML, `taplo` for TOML lint/format, `shellcheck` + `shfmt` for shell.

Missing a tool? Propose adding it to `config.toml`. Never install imperatively (`cargo install`, `npm i -g`, `brew install`, manual binary downloads) — that breaks version pinning and cross-machine reproducibility.
