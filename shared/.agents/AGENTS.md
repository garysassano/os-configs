## Packages

Use latest stable unless the user asks otherwise or the project documents a compatibility constraint.

## GitHub CLI

Inside the target repository, always invoke `~/.local/bin/gh`, never bare `gh` or another `gh` executable. The wrapper selects the mapped GitHub account automatically. Never set `GH_TOKEN` or `GITHUB_TOKEN`, and use `gh auth` only for status or help. If credentials are missing, stop and ask the user to sign the mapped account into Git Credential Manager.

## Tools

mise owns tools. `~/.config/mise/config.toml` is authoritative; check it before proposing an installation. Check installed tools with `mise ls --installed`.

Prefer `rg` over `grep`, `fd` over `find`, `bat` over `cat`, and `eza` over `ls`. Use `jq` for JSON, `yq` for YAML/XML/TOML, `taplo` for TOML, and `shellcheck` plus `shfmt` for shell.

Missing tool: propose adding it to `config.toml`. Never install imperatively.

## Skills

`~/.agents/skills/` is the canonical location for every skill. Write new skills there as `~/.agents/skills/<name>/SKILL.md`, never directly into a harness directory such as `~/.claude/skills/` — a skill created there is invisible to the other harnesses and will be missed by anything that reasons about the canonical set.

After adding, renaming, or removing a skill, run `~/.agents/link.sh` to fan symlinks out to every installed harness (`--dry-run` prints the plan first). It is idempotent and only prunes symlinks it created, so re-running it after `npx skills` or after installing a new harness is always safe.

Cross-references between skills should name the other skill rather than link a relative path, because the same file is read through symlinks at several different depths.

## Markdown

Never hard-wrap prose. Write one paragraph or one sentence per line and let the editor soft-wrap it; do not reflow a paragraph into 80-column lines, and do not re-wrap existing prose when editing nearby text. Prettier owns markdown formatting and does not reflow paragraphs; markdownlint's MD013 line-length rule is off deliberately. Hard wrapping is still correct inside code blocks and tables, where the source layout is the content.
