#!/usr/bin/env bash

# Shared privacy scan. Sourced by every sync script so the policy cannot drift
# between them; a weaker copy in one script would silently defeat the others.
#
# Usage: scan_for_secrets <path>...
# Returns non-zero and prints rule ID, file, and line for every finding.
#
# gitleaks supplies the maintained default rules. lib/gitleaks.toml adds the
# two deliberately broad policy rules: credential-shaped configuration keys and
# sk- prefixed model-provider keys.

scan_secrets_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCAN_SECRETS_CONFIG="${scan_secrets_lib_dir}/gitleaks.toml"

scan_for_secrets() {
	local -a existing=()
	local -a pipeline_status=()
	local path
	local tool
	local status=0

	for path in "$@"; do
		[[ -e "$path" ]] && existing+=("$path")
	done

	if [[ ${#existing[@]} -eq 0 ]]; then
		return 0
	fi

	for tool in gitleaks jq; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			printf '%s is not on PATH; the secret scan cannot run. Install it with: mise install %s\n' \
				"$tool" "$tool" >&2
			return 1
		fi
	done

	# The raw JSON report stays in the pipe. jq emits only rule ID, file, and
	# line, so source text and values never reach the terminal or captured logs.
	# A gitleaks finding is non-zero but still has a valid report, so capture both
	# pipeline statuses instead of relying on pipefail inherited from the caller.
	for path in "${existing[@]}"; do
		if gitleaks dir "$path" \
			--config "$SCAN_SECRETS_CONFIG" \
			--ignore-gitleaks-allow \
			--no-banner \
			--log-level error \
			--report-format json \
			--report-path - |
			jq -r '.[] | [.RuleID, .File, .StartLine] | @tsv'; then
			pipeline_status=("${PIPESTATUS[@]}")
		else
			pipeline_status=("${PIPESTATUS[@]}")
		fi

		if [[ ${pipeline_status[0]} -ne 0 || ${pipeline_status[1]} -ne 0 ]]; then
			status=1
		fi
	done

	if [[ $status -ne 0 ]]; then
		printf 'Secret scan failed or found a possible secret; inspect and sanitize the source before syncing.\n' >&2
	fi

	return "$status"
}
