#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../.." && pwd)"
ubuntu_dir="${repo_root}/ubuntu"
# The canonical agent configuration is OS-independent — the same AGENTS.md, skills,
# link.sh, and skill lock on every machine — so it lives outside the per-OS trees.
shared_dir="${repo_root}/shared"

required_sources=(
	"${HOME}/.agents/.skill-lock.json"
	"${HOME}/.agents/AGENTS.md"
	"${HOME}/.agents/link.sh"
	"${HOME}/.agents/skills"
	"${HOME}/.claude.json"
	"${HOME}/.claude/settings.json"
	"${HOME}/.codex/config.toml"
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
	"${shared_dir}/.agents/skills" \
	"${ubuntu_dir}/.claude" \
	"${ubuntu_dir}/.codex" \
	"${ubuntu_dir}/.config/fish" \
	"${ubuntu_dir}/.config/git" \
	"${ubuntu_dir}/.config/mise" \
	"${ubuntu_dir}/.config/oh-my-posh/themes" \
	"${ubuntu_dir}/.config/opencode" \
	"${ubuntu_dir}/.granted" \
	"${ubuntu_dir}/.local/bin" \
	"${ubuntu_dir}/.local/share/applications" \
	"${ubuntu_dir}/.reasonix"

cp -a "${HOME}/.agents/AGENTS.md" "${shared_dir}/.agents/AGENTS.md"
cp -a "${HOME}/.agents/link.sh" "${shared_dir}/.agents/link.sh"
# npx skills' own state: which skills under ~/.agents/skills are vendored copies
# rather than hand-written, and which harnesses it writes into. Without it a rebuilt
# machine cannot tell a vendored skill from a local one, and `npx skills update`
# has nothing to update.
cp -a "${HOME}/.agents/.skill-lock.json" "${shared_dir}/.agents/.skill-lock.json"
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
# opencodex shims Codex while it runs: it injects a routed model, its generated
# model_catalog_json, the localhost proxy openai_base_url, and a
# [tui.model_availability_nux] block, then strips them again when it restores the
# shim (codexShimAutoRestore in ~/.opencodex/config.json). All of it is live state
# regenerated every run — the proxy port and the catalog it points at change
# between sessions — so a raw copy churns the diff and freezes a dead port. Drop
# it, the way the macOS sync does; opencodex reinjects it on the next machine.
# Filtered by line rather than through yq so the MCP, marketplace, project, and
# plugin sections keep the explanatory comments a TOML round-trip would discard.
awk '
	/^# Auto-injected by opencodex$/ { next }
	/^model = / { next }
	/^model_catalog_json = / { next }
	/^openai_base_url = / { next }
	/^\[tui\.model_availability_nux\]/ { drop = 1; next }
	drop && /^\[/ { drop = 0 }
	drop { next }
	{ print }
' "${HOME}/.codex/config.toml" >"${ubuntu_dir}/.codex/config.toml"
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

# The skills sync is additive on purpose. Every real directory under
# ~/.agents/skills is refreshed, but a repository skill missing there is left
# alone, never deleted — a skill authored on another machine must survive a sync
# run from this one. Removal is therefore always deliberate: delete the skill from
# ~/.agents/skills and `git rm` it here. The cost is drift, so the loop below
# surfaces repository-only skills as a note rather than acting on them.
for source in "${HOME}/.agents/skills/"*; do
	[[ -d "$source" ]] || continue
	[[ -L "$source" ]] && continue
	cp -a "$source" "${shared_dir}/.agents/skills/"
done

# os-config-sync is the one repository-owned skill with no ~ counterpart, so it is
# never flagged. Any other repository-only skill is drift to review by hand.
for repo_skill in "${shared_dir}/.agents/skills/"*/; do
	name="$(basename "$repo_skill")"
	[[ "$name" == "os-config-sync" ]] && continue
	if [[ ! -e "${HOME}/.agents/skills/${name}" ]]; then
		printf 'Note: %s is in the repository but not under ~/.agents/skills; remove it by hand if that is intended.\n' \
			"$name" >&2
	fi
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
shellcheck -x "${ubuntu_dir}/.local/bin/gh" "${shared_dir}/.agents/link.sh" \
	"${script_dir}/lib/scan-secrets.sh" "${script_dir}/sync-vscode.sh" \
	"${script_dir}/test-gh-wrapper.sh" "$0"
shfmt -d "${ubuntu_dir}/.local/bin/gh" "${shared_dir}/.agents/link.sh" \
	"${script_dir}/lib/scan-secrets.sh" "${script_dir}/sync-vscode.sh" \
	"${script_dir}/test-gh-wrapper.sh" "$0"
git -C "$repo_root" diff --check

printf 'Ubuntu configuration snapshot refreshed. Review the complete git diff before staging.\n'
