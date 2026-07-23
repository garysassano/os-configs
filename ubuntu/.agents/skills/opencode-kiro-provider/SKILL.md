---
name: opencode-kiro-provider
description: |
  Maintain, rebuild, run, and troubleshoot the local Kiro-enabled OpenCode and
  opencode-kiro-auth plugin; verify Kiro model effort variants, authentication,
  quota usage, and find the latest available kiro-cli version. Use when working
  in ~/git/opencode-upstream or ~/git-silver/opencode-kiro-auth, debugging which
  OpenCode binary is active, or checking Kiro CLI compatibility.
---

# OpenCode Kiro provider

Maintain the local OpenCode build and the external `opencode-kiro-auth` plugin.
Both can read Kiro credentials and OpenCode has shell/filesystem access, so
review updates before running them.

## Current layout

- Clean OpenCode checkout: `~/git/opencode-upstream`, branch `dev` tracking
  `origin/dev`.
- OpenCode build output:
  `~/git/opencode-upstream/packages/opencode/dist/opencode-linux-x64/bin/opencode`.
- Plugin checkout: `~/git-silver/opencode-kiro-auth`, branch
  `feat/kiro-provider-hardening`.
- Preserved older checkout: `~/git/opencode`. Do not reset, clean, or otherwise
  modify it unless explicitly asked.
- Global OpenCode config: `~/.config/opencode/opencode.jsonc`; it loads the
  plugin from `/home/user/git-silver/opencode-kiro-auth`.
- TUI config: `~/.config/opencode/tui.jsonc`; `variant_cycle` is
  `shift+tab,ctrl+t` and `variant_list` is `ctrl+shift+t`.
- Local wrapper: `~/.local/bin/opencode`; it launches the clean checkout's
  dist binary and prepends the pinned `kiro-cli` installation to `PATH`.
- `~/.bashrc` prepends `~/.local/bin` after activating mise so bare `opencode`
  resolves to the wrapper. If an existing shell predates that change, run
  `source ~/.bashrc` or use the wrapper explicitly. Always verify with
  `type -a opencode` and inspect `/proc/<pid>/exe` when diagnosing a process.
- User-authored skills live under `~/.agents/skills`. The matching directories
  under `~/.kiro/skills` are symlinks, not independent copies. OpenCode also
  embeds a `customize-opencode` skill in its binary; it is not a file under
  `~/.config/opencode/skills`.

Do not assume the revisions or versions recorded here remain current. Inspect
the repositories and binaries before changing anything.

## Inspect before updating

Run these independently in their respective worktrees:

```bash
git -C ~/git/opencode-upstream status --short --branch
git -C ~/git/opencode-upstream log --oneline -5
git -C ~/git-silver/opencode-kiro-auth status --short --branch
git -C ~/git-silver/opencode-kiro-auth log --oneline -5
type -a opencode
~/.local/bin/opencode --version
```

Never discard a dirty worktree. Preserve unrelated user changes and do not use
`reset --hard`, `clean`, or checkout-based reverts. Fetch and merge/rebase only
when the requested update strategy is clear. Do not update the preserved
`~/git/opencode` checkout as a substitute for the clean checkout.

## Build and validate the plugin

Use the scripts declared by the plugin rather than inventing commands. The
normal comprehensive validation is:

```bash
cd ~/git-silver/opencode-kiro-auth
bun install
bun run check
bun test
bun run typecheck
bun run build
npm pack --dry-run
git diff --check
```

Keep model metadata and effort support grounded in Kiro's advertised catalog.
At the latest verified state:

- `claude-opus-4.8`: `low`, `medium`, `high`, `xhigh`, `max`
- `claude-opus-4.7`: `low`, `medium`, `high`, `xhigh`, `max`
- `gpt-5.6-sol`, `gpt-5.6-terra`, and `gpt-5.6-luna`: `low`, `medium`,
  `high`, `xhigh`, `max` (`Min` in Kiro UI maps to API value `low`)
- `claude-opus-4.6`: `low`, `medium`, `high`, `max`
- `claude-sonnet-4.6`: `low`, `medium`, `high`, `max`
- `claude-sonnet-5` is available.
- Do not infer effort variants for models that Kiro does not advertise as
  supporting effort.

OpenCode passes the selected variant through provider options. The plugin must
place Claude effort in `additionalModelRequestFields.output_config.effort` and
GPT-5.6 effort in `additionalModelRequestFields.reasoning.effort` before
calculating content length. Do not map credit budgets to effort unless Kiro
documents that behavior.

## Build OpenCode

From the clean checkout:

```bash
cd ~/git/opencode-upstream
bun install
bun ./packages/opencode/script/build.ts --single
packages/opencode/dist/opencode-linux-x64/bin/opencode --version
```

Also run the most relevant OpenCode typecheck/tests for any OpenCode source
changes. The plugin is external, so plugin-only edits normally require a plugin
build plus an OpenCode process restart, not OpenCode source changes.

## Run the correct binary

Use the wrapper explicitly:

```bash
~/.local/bin/opencode
```

The expected wrapper shape is:

```bash
#!/usr/bin/env bash
export OPENCODE_DISABLE_CHANNEL_DB="${OPENCODE_DISABLE_CHANNEL_DB:-1}"
export PATH="/home/user/.local/share/mise/installs/aqua-kiro-dev-kiro-cli/<version>/kirocli/bin:${PATH}"
exec /home/user/git/opencode-upstream/packages/opencode/dist/opencode-linux-x64/bin/opencode "$@"
```

Keep `<version>` aligned with an installed mise-managed Kiro CLI. Do not run
`opencode upgrade` on the development build.

Configuration and plugins are loaded at process startup. After rebuilding or
changing config/plugin files, quit the existing TUI normally and relaunch it
through `~/.local/bin/opencode`. Do not kill the TUI that hosts the current
agent session. A separately running server may remain if it already uses the
new dist binary and was restarted after the plugin/config changes.

If `~/.bashrc` was changed while the parent terminal was already open, quitting
the TUI returns to a shell with the old PATH. In that shell, use either:

```bash
source ~/.bashrc
type -a opencode
opencode
```

or bypass shell resolution completely with `~/.local/bin/opencode`. The first
`type -a` result must be `~/.local/bin/opencode`, and the wrapper's version must
start with `0.0.0-dev-`.

To identify a running process without guessing:

```bash
readlink -f /proc/<pid>/exe
tr '\0' ' ' < /proc/<pid>/cmdline
```

## Verify effort variants

1. Confirm the live provider catalog includes the expected model and variants.
2. In a freshly restarted TUI, select a GPT-5.6 tier, `Claude Opus 4.8`,
   `Claude Opus 4.6`, or `Claude Sonnet 4.6`.
3. Press `Ctrl+Shift+T` to open the explicit variant picker. This is the best
   diagnostic because it either lists the supported levels or displays `No
   variants available` for the current model.
4. Press `Shift+Tab` or `Ctrl+T` to cycle variants.
5. Send a minimal request and verify the response. For wire-level confidence,
   inspect debug logs or use the local server API and confirm `xhigh`/`max`
   survives unchanged into Kiro's model-specific effort field.

If variants are absent, first check that the TUI itself is the rebuilt dist
binary. A rebuilt server does not update an older TUI process, and a bare
`opencode` command from a shell with stale PATH can silently launch the mise
release. In the verified failure, both restarted TUI processes resolved to
`~/.local/share/mise/installs/opencode/1.17.20/opencode` even though the dev
server catalog correctly contained every Kiro variant. Fix or reload PATH, then
restart the TUI; do not change the plugin when the live catalog is already
correct. Also inspect `~/.local/state/opencode/model.json`: the first `recent`
entry indicates the most recently selected model. To remove ambiguity, launch
a fresh TUI with `~/.local/bin/opencode -m kiro/gpt-5.6-sol` or
`~/.local/bin/opencode -m kiro/claude-opus-4.8`, then open the picker with
`Ctrl+Shift+T`.

## Authentication and quota checks

- Kiro authentication uses the existing Kiro CLI token or an explicitly chosen
  AWS flow.
- Keep access-token refresh deduplicated per account and use the newly returned
  auth state immediately after refresh.
- Treat SDK metadata status `200` as response-stream context, not an HTTP error;
  preserve and log the underlying event-stream failure instead of reporting
  `Kiro Error: 200`.
- AWS profile ARN validation must be partition-aware. Browser launch should be
  shell-free, OIDC polling bounded, and GovCloud should use FIPS endpoints.
- Usage lookup failures should not break chat requests. Report usage as credits,
  not requests.
- Credential, OIDC cache, database, WAL, and SHM files must remain private.

## Find the latest kiro-cli

The aqua registry entry `kiro.dev/kiro-cli` is an HTTP package, so
`mise ls-remote` and `mise latest` may not list versions. Compare the official
`stable/latest` artifact with likely versioned artifacts:

```bash
curl -sI 'https://prod.download.cli.kiro.dev/stable/latest/kirocli-x86_64-linux-musl.zip'

for v in 2.12.1 2.12.2 2.13.0 2.14.0; do
  curl -sI "https://prod.download.cli.kiro.dev/stable/$v/kirocli-x86_64-linux-musl.zip"
done
```

Match successful responses and `content-length` against `stable/latest`;
nonexistent versions commonly return HTTP 403. The latest verified version on
2026-07-15 was `2.12.2`, but always recheck. Prefer changing the exact pin in
`~/.config/mise/config.toml` and running `mise install` over `kiro-cli update`,
which would drift the mise-managed installation. Account for mise's
`minimum_release_age` policy when a new release is not immediately installable.

## Skill discovery

This canonical file is `~/.agents/skills/opencode-kiro-provider/SKILL.md`.
`~/.kiro/skills/opencode-kiro-provider` symlinks to it, so edit only the
canonical file. OpenCode automatically discovers `~/.agents/skills`; no copy
under `~/.config/opencode/skills` is needed. Restart OpenCode after editing a
skill because running sessions retain the skill content loaded at startup.
