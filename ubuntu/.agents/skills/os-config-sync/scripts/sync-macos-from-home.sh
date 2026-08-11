#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../.." && pwd)"
macos_dir="${repo_root}/macos"

required_sources=(
	"${HOME}/.codex/config.toml"
	"${HOME}/.config/fish/config.fish"
	"${HOME}/.config/mise/.markdownlint.jsonc"
	"${HOME}/.config/mise/.taplo.toml"
	"${HOME}/.config/mise/config.toml"
	"${HOME}/.config/oh-my-posh/themes/multiverse-neon.omp.json"
	"${HOME}/.config/opencode/opencode.json"
	"${HOME}/.profile"
	"${HOME}/Library/Application Support/Code/User/keybindings.json"
	"${HOME}/Library/Application Support/Code/User/settings.json"
)

for source in "${required_sources[@]}"; do
	if [[ ! -e "$source" ]]; then
		printf 'Required source is missing: %s\n' "$source" >&2
		exit 1
	fi
done

# shellcheck source-path=SCRIPTDIR source=lib/scan-secrets.sh
. "${script_dir}/lib/scan-secrets.sh"

if [[ ! -f "${HOME}/.claude.json" ]]; then
	printf 'Required source is missing: %s\n' "${HOME}/.claude.json" >&2
	exit 1
fi

claude_tmp="$(mktemp)"
codex_tmp="$(mktemp)"
extensions_tmp="$(mktemp)"
common_extensions_tmp="$(mktemp)"
trap 'rm -f "$claude_tmp" "$codex_tmp" "$extensions_tmp" "$common_extensions_tmp"' EXIT

# ~/.claude.json mixes preferences with account and app-managed state. Keep the
# same explicit preference allowlist as the Ubuntu sync.
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
	"${HOME}/.claude.json" >"$claude_tmp"

# OpenCodex injects its selected model, localhost proxy, generated catalog,
# marketplace revisions, hook hashes, and model-availability state into Codex's
# config. Keep only portable user preferences. Project trust is intentionally
# local too: this Mac has work and personal repositories under the same home.
yq -p=toml -o=toml '
	with_entries(select(
		.key == "approvals_reviewer" or
		.key == "features" or
		.key == "model_reasoning_effort" or
		.key == "notice" or
		.key == "personality" or
		.key == "plan_mode_reasoning_effort" or
		.key == "sandbox_mode" or
		.key == "tui"
	)) |
	del(.tui.model_availability_nux)
' "${HOME}/.codex/config.toml" >"$codex_tmp"

# Scan only Claude's filtered preferences, not its account, project history, or
# caches. Other macOS sources are named individually so nearby work content,
# including config.devops.toml, shared_tasks/, and packages/, cannot enter.
scan_for_secrets \
	"${required_sources[@]}" \
	"$claude_tmp" \
	"$codex_tmp" || exit 1

mkdir -p \
	"${macos_dir}/.codex" \
	"${macos_dir}/.config/fish" \
	"${macos_dir}/.config/mise" \
	"${macos_dir}/.config/oh-my-posh/themes" \
	"${macos_dir}/.config/opencode" \
	"${macos_dir}/vs-code"

install -m 0644 "$claude_tmp" "${macos_dir}/.claude.json"
install -m 0600 "$codex_tmp" "${macos_dir}/.codex/config.toml"
install -m 0644 "${HOME}/.profile" "${macos_dir}/.profile"

cp -a "${HOME}/.config/fish/config.fish" "${macos_dir}/.config/fish/config.fish"
cp -a "${HOME}/.config/mise/.markdownlint.jsonc" \
	"${macos_dir}/.config/mise/.markdownlint.jsonc"
cp -a "${HOME}/.config/mise/.taplo.toml" "${macos_dir}/.config/mise/.taplo.toml"
cp -a "${HOME}/.config/mise/config.toml" \
	"${macos_dir}/.config/mise/config.toml"
cp -a "${HOME}/.config/oh-my-posh/themes/multiverse-neon.omp.json" \
	"${macos_dir}/.config/oh-my-posh/themes/multiverse-neon.omp.json"
# Named file only: node_modules, package manager state, and the generated
# AGENTS.md symlink beside it are not durable configuration.
cp -a "${HOME}/.config/opencode/opencode.json" \
	"${macos_dir}/.config/opencode/opencode.json"
cp -a "${HOME}/Library/Application Support/Code/User/keybindings.json" \
	"${macos_dir}/vs-code/keybindings.json"
cp -a "${HOME}/Library/Application Support/Code/User/settings.json" \
	"${macos_dir}/vs-code/settings.json"

code --list-extensions | LC_ALL=C sort -u >"$extensions_tmp"
if [[ ! -s "$extensions_tmp" ]]; then
	printf 'VS Code returned an empty extension list; refusing to replace the snapshot.\n' >&2
	exit 1
fi

# The Mac uses the Windows host extension set as its baseline. remote-wsl is the
# sole platform-only exception; extra native Mac extensions are allowed.
grep -vx 'ms-vscode-remote.remote-wsl' \
	"${repo_root}/windows/vs-code/extensions.txt" >"$common_extensions_tmp"
missing_extensions="$(comm -23 "$common_extensions_tmp" "$extensions_tmp")"
if [[ -n "$missing_extensions" ]]; then
	printf 'Mac VS Code is missing extensions from the shared baseline:\n%s\n' \
		"$missing_extensions" >&2
	exit 1
fi
install -m 0644 "$extensions_tmp" "${macos_dir}/vs-code/extensions.txt"

taplo lint \
	"${macos_dir}/.codex/config.toml" \
	"${macos_dir}/.config/mise/.taplo.toml" \
	"${macos_dir}/.config/mise/config.toml"
fish_bin="$(mise which fish)"
fish_indent_bin="$(dirname "$fish_bin")/fish_indent"
"$fish_bin" --no-execute "${macos_dir}/.config/fish/config.fish"
"$fish_indent_bin" --check "${macos_dir}/.config/fish/config.fish"
omp_bin="$(mise which oh-my-posh)"
"$omp_bin" print primary \
	--config "${macos_dir}/.config/oh-my-posh/themes/multiverse-neon.omp.json" \
	--shell fish \
	--pwd "$repo_root" >/dev/null
shellcheck -x \
	"${script_dir}/lib/scan-secrets.sh" \
	"${script_dir}/sync-macos-from-home.sh"
shfmt -d \
	"${script_dir}/lib/scan-secrets.sh" \
	"${script_dir}/sync-macos-from-home.sh"
git -C "$repo_root" diff --check

printf 'macOS configuration snapshot refreshed. Review the complete git diff before staging.\n'
