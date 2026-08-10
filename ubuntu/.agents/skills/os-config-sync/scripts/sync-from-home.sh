#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../.." && pwd)"
ubuntu_dir="${repo_root}/ubuntu"

required_sources=(
	"${HOME}/.agents/.skill-lock.json"
	"${HOME}/.agents/AGENTS.md"
	"${HOME}/.agents/link.sh"
	"${HOME}/.agents/skills"
	"${HOME}/.cargo/config.toml"
	"${HOME}/.claude.json"
	"${HOME}/.claude/settings.json"
	"${HOME}/.codex/config.toml"
	"${HOME}/.codex/skills"
	"${HOME}/.config/fish/config.fish"
	"${HOME}/.config/git/allowed_signers"
	"${HOME}/.config/mise/.markdownlint.jsonc"
	"${HOME}/.config/mise/.taplo.toml"
	"${HOME}/.config/mise/config.toml"
	"${HOME}/.config/oh-my-posh/themes/multiverse-neon.omp.json"
	"${HOME}/.config/opencode/opencode.jsonc"
	"${HOME}/.gitconfig"
	"${HOME}/.granted/config"
	"${HOME}/.local/share/applications/wsl-explorer.desktop"
	"${HOME}/.profile"
	"${HOME}/.reasonix/config.toml"
)

for source in "${required_sources[@]}"; do
	if [[ ! -e "$source" ]]; then
		printf 'Required source is missing: %s\n' "$source" >&2
		exit 1
	fi
done

# shellcheck source-path=SCRIPTDIR source=lib/scan-secrets.sh
. "${script_dir}/lib/scan-secrets.sh"

# The gh wrapper and its test handle live credentials, so both are scanned even
# though neither is a required source: the wrapper is copied by the allowlist below,
# and the test is repository-owned with no counterpart under ~.
scan_for_secrets "${required_sources[@]}" \
	"${HOME}/.local/bin/gh" \
	"${script_dir}/test-gh-wrapper.sh" || exit 1

mkdir -p \
	"${ubuntu_dir}/.agents/skills" \
	"${ubuntu_dir}/.cargo" \
	"${ubuntu_dir}/.claude" \
	"${ubuntu_dir}/.codex/skills" \
	"${ubuntu_dir}/.config/fish" \
	"${ubuntu_dir}/.config/git" \
	"${ubuntu_dir}/.config/mise" \
	"${ubuntu_dir}/.config/oh-my-posh/themes" \
	"${ubuntu_dir}/.config/opencode" \
	"${ubuntu_dir}/.granted" \
	"${ubuntu_dir}/.local/bin" \
	"${ubuntu_dir}/.local/share/applications" \
	"${ubuntu_dir}/.reasonix"

cp -a "${HOME}/.agents/AGENTS.md" "${ubuntu_dir}/.agents/AGENTS.md"
cp -a "${HOME}/.agents/link.sh" "${ubuntu_dir}/.agents/link.sh"
# npx skills' own state: which skills under ~/.agents/skills are vendored copies
# rather than hand-written, and which harnesses it writes into. Without it a rebuilt
# machine cannot tell a vendored skill from a local one, and `npx skills update`
# has nothing to update.
cp -a "${HOME}/.agents/.skill-lock.json" "${ubuntu_dir}/.agents/.skill-lock.json"
cp -a "${HOME}/.cargo/config.toml" "${ubuntu_dir}/.cargo/config.toml"
cp -a "${HOME}/.claude/settings.json" "${ubuntu_dir}/.claude/settings.json"
# ~/.claude.json mixes preferences with app-managed state — oauthAccount, machineID,
# per-project history, rotating caches — so only the preference keys are captured.
# Settings Claude Code keeps here rather than in settings.json, autoInstallIdeExtension
# among them, would otherwise be lost on a rebuild. Extend the list as new ones appear.
claude_global_keys='[
	"autoCompactEnabled", "autoConnectIde", "autoInstallIdeExtension",
	"autoScrollEnabled", "copyFullResponse", "diffTool", "editorMode",
	"externalEditorContext", "fileCheckpointingEnabled", "messageIdleNotifThresholdMs",
	"preferredNotifChannel", "respectGitignore", "showMessageTimestamps",
	"showTurnDuration", "terminalProgressBarEnabled", "theme", "todoFeatureEnabled",
	"verbose"
]'
jq --argjson keys "$claude_global_keys" \
	'with_entries(select(.key as $k | $keys | index($k)))' \
	"${HOME}/.claude.json" >"${ubuntu_dir}/.claude.json"
ln -sfn ../.agents/AGENTS.md "${ubuntu_dir}/.codex/AGENTS.md"
cp -a "${HOME}/.codex/config.toml" "${ubuntu_dir}/.codex/config.toml"
# Only config.fish is durable. conf.d/, functions/, and completions/ are kept empty
# deliberately — everything interactive lives in config.fish so there is one file to
# read and one file to sync — and fish_variables is regenerated stock state.
cp -a "${HOME}/.config/fish/config.fish" "${ubuntu_dir}/.config/fish/config.fish"
# Maps a signing identity to its public key so `git log --show-signature` can name
# the signer; without it git reports "No principal matched" for otherwise valid
# signatures. Public keys only — the private half is never captured.
cp -a "${HOME}/.config/git/allowed_signers" "${ubuntu_dir}/.config/git/allowed_signers"
# Base markdownlint rules for every repository. VS Code's user settings point at
# this path, so it has to exist under ~ for a rebuilt machine to lint the same way.
cp -a "${HOME}/.config/mise/.markdownlint.jsonc" "${ubuntu_dir}/.config/mise/.markdownlint.jsonc"
cp -a "${HOME}/.config/mise/.taplo.toml" "${ubuntu_dir}/.config/mise/.taplo.toml"
cp -a "${HOME}/.config/mise/config.toml" "${ubuntu_dir}/.config/mise/config.toml"
cp -a "${HOME}/.config/oh-my-posh/themes/multiverse-neon.omp.json" \
	"${ubuntu_dir}/.config/oh-my-posh/themes/multiverse-neon.omp.json"
# A named file, never the directory: ~/.config/opencode accumulates provider state
# beside it, and the Kiro integration that used to live here kept a live clientSecret
# in kiro-oidc-clients.json. That integration was removed on 2026-08-07; naming the
# file explicitly keeps the next one from being captured by accident.
cp -a "${HOME}/.config/opencode/opencode.jsonc" "${ubuntu_dir}/.config/opencode/opencode.jsonc"
cp -a "${HOME}/.gitconfig" "${ubuntu_dir}/.gitconfig"
# WSL-only: granted cannot defer to $BROWSER or xdg-open, so it names the Windows
# Firefox binary by absolute path. A macOS machine needs its own copy.
cp -a "${HOME}/.granted/config" "${ubuntu_dir}/.granted/config"
# The URL handler $BROWSER and xdg-open resolve to. WSL-only: it execs
# /mnt/c/WINDOWS/explorer.exe. Registering it as the default is a separate,
# unsynced step — see "Rebuilding a machine" in README.md.
cp -a "${HOME}/.local/share/applications/wsl-explorer.desktop" \
	"${ubuntu_dir}/.local/share/applications/wsl-explorer.desktop"
cp -a "${HOME}/.profile" "${ubuntu_dir}/.profile"
# Named file, never the directory: ~/.reasonix/.env holds provider API keys.
cp -a "${HOME}/.reasonix/config.toml" "${ubuntu_dir}/.reasonix/config.toml"

for source in "${HOME}/.agents/skills/"*; do
	[[ -d "$source" ]] || continue
	[[ -L "$source" ]] && continue
	cp -a "$source" "${ubuntu_dir}/.agents/skills/"
done

# Skip symlinks: link.sh fans the canonical ~/.agents/skills into every harness,
# so a symlink here is a derived copy of a skill already captured above. Copying
# it would snapshot a dangling absolute path into the repository.
for source in "${HOME}/.codex/skills/"*; do
	[[ -d "$source" ]] || continue
	[[ -L "$source" ]] && continue
	cp -a "$source" "${ubuntu_dir}/.codex/skills/"
done

wrappers=(gh)
for wrapper in "${wrappers[@]}"; do
	source="${HOME}/.local/bin/${wrapper}"
	if [[ ! -f "$source" ]]; then
		printf 'Allowlisted wrapper is missing: %s\n' "$source" >&2
		exit 1
	fi
	cp -a "$source" "${ubuntu_dir}/.local/bin/${wrapper}"
done

taplo lint "${ubuntu_dir}/.codex/config.toml" "${ubuntu_dir}/.config/mise/.taplo.toml" \
	"${ubuntu_dir}/.config/mise/config.toml" "${ubuntu_dir}/.reasonix/config.toml"
# -x so the sourced lib/scan-secrets.sh is followed rather than reported as SC1091.
# test-gh-wrapper.sh is linted but never run here: it needs network access, live
# credentials, and it creates throwaway repositories. Run it by hand.
shellcheck -x "${ubuntu_dir}/.local/bin/gh" "${ubuntu_dir}/.agents/link.sh" \
	"${script_dir}/lib/scan-secrets.sh" "${script_dir}/sync-vscode.sh" \
	"${script_dir}/test-gh-wrapper.sh" "$0"
shfmt -d "${ubuntu_dir}/.local/bin/gh" "${ubuntu_dir}/.agents/link.sh" \
	"${script_dir}/lib/scan-secrets.sh" "${script_dir}/sync-vscode.sh" \
	"${script_dir}/test-gh-wrapper.sh" "$0"
git -C "$repo_root" diff --check

printf 'Ubuntu configuration snapshot refreshed. Review the complete git diff before staging.\n'
