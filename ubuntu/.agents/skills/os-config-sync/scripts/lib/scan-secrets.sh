#!/usr/bin/env bash

# Shared privacy scan. Sourced by every sync script so the pattern cannot drift
# between them; a weaker copy in one script would silently defeat the other.
#
# Usage: scan_for_secrets <path>...
# Returns non-zero and prints the offending lines when anything matches.

# shellcheck disable=SC2034  # consumed by callers that want to report it
SECRET_PATTERN='(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|^[[:space:]]*"?(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|private[_-]?key)"?[[:space:]]*[:=])'

scan_for_secrets() {
	local -a existing=()
	local path

	for path in "$@"; do
		[[ -e "$path" ]] && existing+=("$path")
	done

	# rg exits 1 when nothing matches, which is the success case here.
	if [[ ${#existing[@]} -eq 0 ]]; then
		return 0
	fi

	if rg -n -i "$SECRET_PATTERN" "${existing[@]}"; then
		printf 'Possible secret detected; inspect and sanitize the source before syncing.\n' >&2
		return 1
	fi

	return 0
}
