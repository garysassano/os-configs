# Global Agent Defaults

When starting a new project, use the latest available stable version of any package by default unless the user explicitly asks for a different version or the project has a documented compatibility constraint.

## Available Tools

A curated set of CLI tools is managed by [mise](https://mise.jdx.dev/) and available on `$PATH`. The authoritative list is at `~/.config/mise/config.toml`. Read that file when you need to know what is available before suggesting installs.

To list installed versions at runtime: `mise ls --installed`.

Prefer these mise-managed tools over alternatives. For example, use `rg` over `grep`, `fd` over `find`, `bat` over `cat`, `eza` over `ls`, `jq` for JSON, `yq` for YAML/JSON/XML/TOML, `taplo` for TOML formatting/linting, `shellcheck` and `shfmt` for shell scripts.

If a needed tool is not declared in `~/.config/mise/config.toml`, suggest adding it to that file rather than installing it imperatively (e.g., `cargo install`, `npm install -g`, `brew install`, manual binary downloads). Mise-declared tools are version-pinned and reproducible across machines.
