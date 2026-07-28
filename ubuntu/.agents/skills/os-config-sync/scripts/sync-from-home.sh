#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../.." && pwd)"
ubuntu_dir="${repo_root}/ubuntu"

required_sources=(
	"${HOME}/.agents/AGENTS.md"
	"${HOME}/.agents/link.sh"
	"${HOME}/.agents/skills"
	"${HOME}/.codex/config.toml"
	"${HOME}/.codex/skills"
	"${HOME}/.config/fish/config.fish"
	"${HOME}/.config/ghostty/config"
	"${HOME}/.config/mise/.taplo.toml"
	"${HOME}/.config/mise/config.toml"
	"${HOME}/.gitconfig"
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
	"${ubuntu_dir}/.codex/skills" \
	"${ubuntu_dir}/.config/fish" \
	"${ubuntu_dir}/.config/ghostty" \
	"${ubuntu_dir}/.config/mise" \
	"${ubuntu_dir}/.local/bin" \
	"${ubuntu_dir}/git-mushi"

cp -a "${HOME}/.agents/AGENTS.md" "${ubuntu_dir}/.agents/AGENTS.md"
cp -a "${HOME}/.agents/link.sh" "${ubuntu_dir}/.agents/link.sh"
ln -sfn ../.agents/AGENTS.md "${ubuntu_dir}/.codex/AGENTS.md"
cp -a "${HOME}/.codex/config.toml" "${ubuntu_dir}/.codex/config.toml"
# Only config.fish is durable. conf.d/, functions/, and completions/ are empty,
# and fish_variables is regenerated stock state (colors, key bindings).
cp -a "${HOME}/.config/fish/config.fish" "${ubuntu_dir}/.config/fish/config.fish"
cp -a "${HOME}/.config/ghostty/config" "${ubuntu_dir}/.config/ghostty/config"
cp -a "${HOME}/.config/mise/.taplo.toml" "${ubuntu_dir}/.config/mise/.taplo.toml"
cp -a "${HOME}/.config/mise/config.toml" "${ubuntu_dir}/.config/mise/config.toml"
cp -a "${HOME}/.gitconfig" "${ubuntu_dir}/.gitconfig"
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
