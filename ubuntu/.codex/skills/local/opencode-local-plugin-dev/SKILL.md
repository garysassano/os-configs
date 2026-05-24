---
name: opencode-local-plugin-dev
description: Build and test a local version of an OpenCode plugin (instead of the npm-cached one) by hot-swapping the plugin compiled dist/ into the OpenCode plugin cache (typically ~/.cache/opencode/node_modules). Use when you need to iterate on an OpenCode plugin locally, verify which plugin code OpenCode is running, or revert to the original cached plugin.
---

# OpenCode local plugin hot-swap

## What this does

OpenCode caches npm-installed plugins under `~/.cache/opencode/node_modules/<package>`.

For local development, the most reliable workflow is:

1. Build the plugin repo (so `dist/` is up to date).
2. Replace the cached plugin `dist/` with your local `dist/`.
3. Restart OpenCode and verify it loaded the plugin.
4. Restore the backup when done.

## Quick start

- Build + hot-swap:
  - Run: `scripts/opencode_plugin_hotswap.sh @zhafron/opencode-kiro-auth /path/to/opencode-kiro-auth`
- Restore:
  - Run: `scripts/opencode_plugin_restore.sh @zhafron/opencode-kiro-auth`

## Verify which code is running

- Check OpenCode logs for plugin load lines:
  - Logs: `~/.local/share/opencode/log/*.log`
  - Look for: `loading plugin path=@zhafron/opencode-kiro-auth`

## Notes

- Always restart OpenCode after a hot-swap.
- If you see stale behavior, do a clean build (delete the repo `dist/` and rebuild).
