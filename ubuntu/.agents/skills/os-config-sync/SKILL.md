---
name: os-config-sync
description: Refresh the Ubuntu snapshot in the os-configs repository from the current machine's shell startup files, global agent instructions, user-authored agent and Codex skills, Codex configuration, mise configuration, and durable command wrappers. Use when asked to update, synchronize, capture, or publish local Ubuntu configuration changes in os-configs.
---

# OS Config Sync

Synchronize the maintained Ubuntu configuration from the live home directory into this repository without copying credentials, generated system skills, plugin caches, binaries, or temporary development launchers.

## Workflow

1. Work from the `os-configs` repository and confirm the worktree state before changing files. Preserve unrelated changes.
2. Read `scripts/sync-from-home.sh` before running it. Update its explicit wrapper allowlist when a new durable wrapper belongs in the snapshot.
3. Run `scripts/sync-from-home.sh`. The script copies:
   - `~/.agents/AGENTS.md`
   - the `~/.codex/AGENTS.md` compatibility symlink to the canonical global instructions
   - `~/.bashrc`, `~/.bash_aliases`, and `~/.profile`
   - all visible directories under `~/.agents/skills/`
   - all visible user-authored directories under `~/.codex/skills/`; the hidden `.system/` directory and plugin caches are excluded
   - `~/.codex/config.toml`
   - `~/.config/mise/config.toml`
   - `~/.gitconfig` and `~/git-mushi/.gitconfig`, which together preserve directory-scoped Git identity and credential selection
   - explicitly allowlisted wrappers from `~/.local/bin/`
4. Review the complete diff. Remove machine-generated state, credentials, tokens, caches, compiled binaries, transient test files, and wrappers tied to temporary build paths.
5. Run the validations printed by the script, plus the skill validator for every new or changed skill when it is available.
6. Confirm executable bits for scripts and wrappers, run `git diff --check`, then commit and push only when requested.

## Boundaries

- Treat the live home directory as the source and `ubuntu/` as the snapshot destination.
- Keep `ubuntu/.agents/skills/os-config-sync/` repository-owned; the sync operation must not delete it merely because it is absent from the live skills directory.
- Keep `ubuntu/.agents/AGENTS.md` canonical and `ubuntu/.codex/AGENTS.md` as a relative symlink to it.
- Do not copy `~/.codex/skills/.system/`, `~/.codex/plugins/`, credentials, authentication databases, session history, memories, caches, logs, or binaries.
- Copy Git credential-helper configuration and usernames, but never credentials returned by the helper.
- Do not infer that every file in `~/.local/bin/` is a wrapper. Add only reviewed, portable shell wrappers to the allowlist.
- Preserve mise as the owner of tool versions. Wrappers should resolve mise-managed executables dynamically rather than pinning mise installation paths or versions.
- Keep shell initialization consistent with the captured tool configuration: activate mise before invoking mise-managed tools and put `~/.local/bin` before mise when local wrappers must take precedence.
- Stop before staging if the privacy scan reports a possible secret; inspect and sanitize the source instead of weakening the scan.

## Script

Run:

```bash
ubuntu/.agents/skills/os-config-sync/scripts/sync-from-home.sh
```

The script is intentionally local-to-repository and does not commit or push.
