#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../.." && pwd)"
ubuntu_dir="${repo_root}/ubuntu"

required_sources=(
	"${HOME}/.agents/AGENTS.md"
	"${HOME}/.agents/skills"
	"${HOME}/.bash_aliases"
	"${HOME}/.bashrc"
	"${HOME}/.codex/config.toml"
	"${HOME}/.codex/skills"
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

scan_sources=(
	"${HOME}/.agents/AGENTS.md"
	"${HOME}/.agents/skills"
	"${HOME}/.bash_aliases"
	"${HOME}/.bashrc"
	"${HOME}/.codex/config.toml"
	"${HOME}/.codex/skills"
	"${HOME}/.config/mise/config.toml"
	"${HOME}/.gitconfig"
	"${HOME}/.profile"
	"${HOME}/git-mushi/.gitconfig"
)

secret_pattern='(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|^[[:space:]]*(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|private[_-]?key)[[:space:]]*=)'

if rg -n -i "$secret_pattern" "${scan_sources[@]}"; then
	printf 'Possible secret detected; inspect and sanitize the source before syncing.\n' >&2
	exit 1
fi

mkdir -p \
	"${ubuntu_dir}/.agents/skills" \
	"${ubuntu_dir}/.codex/skills" \
	"${ubuntu_dir}/.config/mise" \
	"${ubuntu_dir}/.local/bin" \
	"${ubuntu_dir}/git-mushi"

cp -a "${HOME}/.agents/AGENTS.md" "${ubuntu_dir}/.agents/AGENTS.md"
ln -sfn ../.agents/AGENTS.md "${ubuntu_dir}/.codex/AGENTS.md"
cp -a "${HOME}/.bash_aliases" "${ubuntu_dir}/.bash_aliases"
cp -a "${HOME}/.bashrc" "${ubuntu_dir}/.bashrc"
cp -a "${HOME}/.codex/config.toml" "${ubuntu_dir}/.codex/config.toml"
cp -a "${HOME}/.config/mise/config.toml" "${ubuntu_dir}/.config/mise/config.toml"
cp -a "${HOME}/.gitconfig" "${ubuntu_dir}/.gitconfig"
cp -a "${HOME}/.profile" "${ubuntu_dir}/.profile"
cp -a "${HOME}/git-mushi/.gitconfig" "${ubuntu_dir}/git-mushi/.gitconfig"

for source in "${HOME}/.agents/skills/"*; do
	[[ -d "$source" ]] || continue
	cp -a "$source" "${ubuntu_dir}/.agents/skills/"
done

for source in "${HOME}/.codex/skills/"*; do
	[[ -d "$source" ]] || continue
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

taplo lint "${ubuntu_dir}/.codex/config.toml" "${ubuntu_dir}/.config/mise/config.toml"
shellcheck "${ubuntu_dir}/.local/bin/gh" "$0"
shfmt -d "${ubuntu_dir}/.local/bin/gh" "$0"
git -C "$repo_root" diff --check

printf 'Ubuntu configuration snapshot refreshed. Review the complete git diff before staging.\n'
