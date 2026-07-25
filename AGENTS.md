# os-configs

Snapshot of a live machine's configuration. See `README.md` for layout.

## The direction matters

The home directory is the source; this repository is the destination. Editing a
file here does not change the machine, and the next sync overwrites it. To
change configuration, edit the real file under `~`, then run the sync script and
review the diff.

Two paths are the exception and are edited here, because they are the source:
`ubuntu/.agents/skills/os-config-sync/` and `README.md`.

## Do not

- Delete `ubuntu/.profile` or strip it to the Ubuntu default. It looks stock, but
  agent harnesses spawn `bash -lc`, `~/.bashrc` returns early on its
  non-interactive guard, and its mise shims block is the only thing putting
  mise-managed tools on PATH for those shells. Its block ordering is also
  deliberate: the shims must land behind `~/.local/bin` so the `gh` credential
  wrapper wins.
- Commit the harness symlinks that `link.sh` creates. They are gitignored; they
  describe one machine's installed harnesses.
- Weaken `scripts/lib/scan-secrets.sh` to get a sync to pass. Sanitize the source
  file instead.
- Add a tool by installing it imperatively. Declare it in
  `ubuntu/.config/mise/config.toml`.
- Sync anything from a client's `~/git-<client>/` tree. Client configuration is
  not preserved here at all, and those trees may hold confidential material. The
  one tracked exception, `~/git-mushi/.gitconfig`, is a personal secondary
  account; it also serves as the worked example of the `includeIf` pattern, and
  one example is enough.

## Before making this repository public

It is private, and two things assume that. `ubuntu/git-mushi/.gitconfig` and the
`includeIf` in `ubuntu/.gitconfig` link the main account to a secondary one, and
`windows/vs-code/settings.json` reflects a real working setup. Strip both before
flipping visibility.

## Checks

`shellcheck -x` and `shfmt` for shell, `taplo lint` for TOML. `sync-from-home.sh`
runs all three before it finishes.
