# os-configs

Snapshot of a live machine's configuration. See `README.md` for layout.

## The direction matters

The home directory is the source; this repository is the destination. Editing a
file here does not change the machine, and the next sync overwrites it. To
change configuration, edit the real file under `~`, then run the sync script and
review the diff.

Two paths are the exception and are edited here, because they are the source:
`shared/.agents/skills/os-config-sync/` and `README.md`.

`shared/.agents/skills/os-config-sync/scripts/test-gh-wrapper.sh` lives inside that
exception. It has no counterpart under `~`, and it survives syncs because the skill
loop only copies directories that exist in `~/.agents/skills/` and never deletes
repository-only ones. The sync lints it and does not run it: it needs network
access, live Git Credential Manager credentials, and it creates throwaway
repositories. Run it by hand after changing `ubuntu/.local/bin/gh`:

```
shared/.agents/skills/os-config-sync/scripts/test-gh-wrapper.sh <primary-repo> <secondary-repo>
```

## Do not

- Delete `ubuntu/.profile` or strip it to the Ubuntu default. It looks stock, but
  agent harnesses spawn `bash -lc`, `~/.bashrc` returns early on its
  non-interactive guard, and its mise shims block is the only thing putting
  mise-managed tools on PATH for those shells. Its block ordering is also
  deliberate: the shims must land behind `~/.local/bin` so the `gh` credential
  wrapper wins.
- Commit the harness symlinks that `link.sh` creates. They are gitignored; they
  describe one machine's installed harnesses.
- Weaken `scripts/lib/scan-secrets.sh` or the rules in `scripts/lib/gitleaks.toml` to get a sync to pass. Sanitize the source file instead.
  The two custom rules deliberately retain the policy for credential-shaped configuration keys and generic `sk-` model-provider keys; deleting one is not a simplification.
  Adding a `keywords` prefilter to `config-credential-key` counts as weakening it because keywords stop the regex from running unless one matches, so an incomplete list silently disables the rule.
- Add a tool by installing it imperatively. Declare it in the live machine's
  `~/.config/mise/config.toml`, then sync the matching OS snapshot. For tools
  outside the mise registry, add a `[tool_alias]` entry and use that alias in
  `[tools]`; explicit `cargo:` entries are the intended exception.
- Run `gh auth login`, or let `~/.config/gh/hosts.yml` gain an account. It stays
  `{}` on purpose: a stored account is a global default that any `gh` reaching past
  `ubuntu/.local/bin/gh` would use in every tree, which is exactly the per-directory
  selection that wrapper exists to guarantee. Credentials belong to Git Credential
  Manager. The wrapper blocks the command, but nothing stops a human from running
  the real binary.
- Sync anything from a `~/git-<name>/` tree. Account- and client-specific Git
  configuration remains local, and client trees may hold confidential material.
- Sync macOS work configuration such as
  `~/.config/mise/config.devops.toml`, `shared_tasks/`, `packages/`, or
  organization documentation. The Mac sync copies only its explicit allowlist.

## Before making this repository public

It is private, and two things assume that. The `includeIf` entries in
`ubuntu/.gitconfig` name local account trees, and `windows/vs-code/settings.json`
reflects a real working setup. Strip both before flipping visibility.

## Checks

`shellcheck -x` and `shfmt` for shell, `taplo lint` for TOML. `sync-from-home.sh`
runs all three before it finishes.
