#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../.." && pwd)"
ubuntu_dir="${repo_root}/ubuntu"

required_sources=(
	"${HOME}/.agents/AGENTS.md"
	"${HOME}/.agents/link.sh"
	"${HOME}/.agents/skills"
	"${HOME}/.cargo/config.toml"
	"${HOME}/.claude.json"
	"${HOME}/.claude/settings.json"
	"${HOME}/.codex/config.toml"
	"${HOME}/.codex/skills"
	"${HOME}/.config/fish/config.fish"
	"${HOME}/.config/mise/.taplo.toml"
	"${HOME}/.config/mise/config.toml"
	"${HOME}/.config/oh-my-posh/themes/multiverse-neon.omp.json"
	"${HOME}/.config/opencode/kiro.json"
	"${HOME}/.config/opencode/opencode.jsonc"
	"${HOME}/.gitconfig"
	"${HOME}/.gnupg/gpg-agent.conf"
	"${HOME}/.granted/config"
	"${HOME}/.profile"
	"${HOME}/git-mushi/.gitconfig"
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
	"${ubuntu_dir}/.config/mise" \
	"${ubuntu_dir}/.config/oh-my-posh/themes" \
	"${ubuntu_dir}/.config/opencode" \
	"${ubuntu_dir}/.gnupg" \
	"${ubuntu_dir}/.granted" \
	"${ubuntu_dir}/.local/bin" \
	"${ubuntu_dir}/git-mushi"

cp -a "${HOME}/.agents/AGENTS.md" "${ubuntu_dir}/.agents/AGENTS.md"
cp -a "${HOME}/.agents/link.sh" "${ubuntu_dir}/.agents/link.sh"
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
# Only config.fish is durable. conf.d/, functions/, and completions/ are empty,
# and fish_variables is regenerated stock state (colors, key bindings).
cp -a "${HOME}/.config/fish/config.fish" "${ubuntu_dir}/.config/fish/config.fish"
cp -a "${HOME}/.config/mise/.taplo.toml" "${ubuntu_dir}/.config/mise/.taplo.toml"
cp -a "${HOME}/.config/mise/config.toml" "${ubuntu_dir}/.config/mise/config.toml"
cp -a "${HOME}/.config/oh-my-posh/themes/multiverse-neon.omp.json" \
	"${ubuntu_dir}/.config/oh-my-posh/themes/multiverse-neon.omp.json"
# Named files, never the directory: ~/.config/opencode also holds
# kiro-oidc-clients.json, whose clientSecret is a live credential.
cp -a "${HOME}/.config/opencode/kiro.json" "${ubuntu_dir}/.config/opencode/kiro.json"
cp -a "${HOME}/.config/opencode/opencode.jsonc" "${ubuntu_dir}/.config/opencode/opencode.jsonc"
cp -a "${HOME}/.gitconfig" "${ubuntu_dir}/.gitconfig"
# WSL-only: pinentry.exe and the Windows Firefox paths have no macOS counterpart.
cp -a "${HOME}/.gnupg/gpg-agent.conf" "${ubuntu_dir}/.gnupg/gpg-agent.conf"
cp -a "${HOME}/.granted/config" "${ubuntu_dir}/.granted/config"
cp -a "${HOME}/.profile" "${ubuntu_dir}/.profile"
cp -a "${HOME}/git-mushi/.gitconfig" "${ubuntu_dir}/git-mushi/.gitconfig"

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
	"${ubuntu_dir}/.config/mise/config.toml"
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
