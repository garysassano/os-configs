## Packages

Default to the latest stable version. Exceptions: the user asks otherwise, or the project documents a compatibility constraint.

## Tools

CLI tools are [mise](https://mise.jdx.dev/)-managed and on `$PATH`. `~/.config/mise/config.toml` is the authoritative list — read it before suggesting an install. Runtime check: `mise ls --installed`.

Prefer them over conventional equivalents: `rg`/`fd`/`bat`/`eza` over `grep`/`find`/`cat`/`ls`, `jq` for JSON, `yq` for YAML/XML/TOML, `taplo` for TOML lint/format, `shellcheck` + `shfmt` for shell.

Missing a tool? Propose adding it to `config.toml`. Never install imperatively (`cargo install`, `npm i -g`, `brew install`, manual binary downloads) — that breaks version pinning and cross-machine reproducibility.
