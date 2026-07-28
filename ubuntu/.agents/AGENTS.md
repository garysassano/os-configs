## Packages

Use latest stable unless the user asks otherwise or the project documents a compatibility constraint.

## GitHub CLI

Inside the target repository, always invoke `~/.local/bin/gh`, never bare `gh` or another `gh` executable. The wrapper selects the mapped GitHub account automatically. Never set `GH_TOKEN` or `GITHUB_TOKEN`, and use `gh auth` only for status or help. If credentials are missing, stop and ask the user to sign the mapped account into Git Credential Manager.

## Tools

mise owns tools. `~/.config/mise/config.toml` is authoritative; check it before proposing an installation. Check installed tools with `mise ls --installed`.

Prefer `rg` over `grep`, `fd` over `find`, `bat` over `cat`, and `eza` over `ls`. Use `jq` for JSON, `yq` for YAML/XML/TOML, `taplo` for TOML, and `shellcheck` plus `shfmt` for shell.

Missing tool: propose adding it to `config.toml`. Never install imperatively.
