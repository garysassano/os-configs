#!/usr/bin/env bash

# Snapshot VS Code configuration from its live locations into the repository.
#
# Replaces the manual `Default.code-profile` export. That format is 78%
# `globalState` — window layouts, recently opened paths, walkthrough progress —
# which is machine state, not configuration, and it double-escapes every payload
# into a single line so diffs are unreadable. The raw files below are the same
# configuration in a reviewable form, and none of them require a manual export.
#
# This runs on WSL and reads the Windows-side installation over /mnt/c. Two
# extension sets exist and are not interchangeable: UI extensions install on the
# Windows host, workspace extensions install into the WSL remote.
#
# Restoring is not one click. Copy the files back, then:
#   xargs -n1 code --install-extension < ubuntu/vs-code/extensions.txt

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../.." && pwd)"

windows_user_dir="/mnt/c/Users/Gary/AppData/Roaming/Code/User"
windows_dest="${repo_root}/windows/vs-code"
ubuntu_dest="${repo_root}/ubuntu/vs-code"

[[ -d "$windows_user_dir" ]] || {
	printf 'Windows VS Code user directory is missing: %s\n' "$windows_user_dir" >&2
	exit 1
}

# shellcheck source-path=SCRIPTDIR source=lib/scan-secrets.sh
. "${script_dir}/lib/scan-secrets.sh"

# settings.json is a common place for API keys pasted into extension settings.
scan_for_secrets \
	"${windows_user_dir}/settings.json" \
	"${windows_user_dir}/keybindings.json" \
	"${windows_user_dir}/snippets" || exit 1

mkdir -p "$windows_dest" "$ubuntu_dest"

# settings.json and keybindings.json are JSON with comments; taplo and jq both
# reject them, so they are copied verbatim without validation.
for file in settings.json keybindings.json; do
	source="${windows_user_dir}/${file}"
	if [[ -f "$source" ]]; then
		# Strip CRLF so the snapshot diffs cleanly against a Linux checkout.
		sed 's/\r$//' "$source" >"${windows_dest}/${file}"
	else
		printf 'Skipping absent file: %s\n' "$source" >&2
	fi
done

# Snippets are per-language files; an empty directory is normal.
rm -rf "${windows_dest}/snippets"
if compgen -G "${windows_user_dir}/snippets/*" >/dev/null; then
	mkdir -p "${windows_dest}/snippets"
	for snippet in "${windows_user_dir}"/snippets/*; do
		[[ -f "$snippet" ]] || continue
		sed 's/\r$//' "$snippet" >"${windows_dest}/snippets/$(basename -- "$snippet")"
	done
fi

# Keep only `publisher.name` identifiers. The remote CLI prefixes its output
# with a banner ("Extensions installed on WSL: Ubuntu:") that would otherwise
# sort into the list, and C-locale sort puts that capital E ahead of everything.
extension_ids() {
	tr -d '\r' | rg '^[A-Za-z0-9][A-Za-z0-9_-]*\.[A-Za-z0-9][A-Za-z0-9_-]*$' | LC_ALL=C sort -u
}

# Windows extensions. code.cmd is a batch file and needs cmd.exe; invoking it
# directly makes /bin/sh try to run `@echo`. cmd.exe rejects a UNC working
# directory, so run it from a drive-backed path.
windows_extensions="$(cd /mnt/c && cmd.exe /c "code --list-extensions" 2>/dev/null | extension_ids)"
if [[ -z "$windows_extensions" ]]; then
	printf 'Windows extension list came back empty; refusing to overwrite the snapshot.\n' >&2
	exit 1
fi
printf '%s\n' "$windows_extensions" >"${windows_dest}/extensions.txt"

# WSL remote extensions, a separate set installed into the VS Code server.
ubuntu_extensions="$(code --list-extensions 2>/dev/null | extension_ids)"
if [[ -z "$ubuntu_extensions" ]]; then
	printf 'WSL remote extension list came back empty; refusing to overwrite the snapshot.\n' >&2
	exit 1
fi
printf '%s\n' "$ubuntu_extensions" >"${ubuntu_dest}/extensions.txt"

git -C "$repo_root" diff --check

printf 'VS Code snapshot refreshed: %s Windows extensions, %s WSL remote extensions.\n' \
	"$(wc -l <"${windows_dest}/extensions.txt")" \
	"$(wc -l <"${ubuntu_dest}/extensions.txt")"
