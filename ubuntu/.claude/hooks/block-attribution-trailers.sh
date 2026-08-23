#!/usr/bin/env bash
# Refuse only commands that CREATE a commit and carry an attribution trailer.
# Matching the trailer alone false-positives on read-only greps and log queries.
set -uo pipefail
c=$(jq -r '.tool_input.command // ""')
printf '%s' "$c" | grep -qE 'git[[:space:]]+(commit|tag|merge|revert|cherry-pick|rebase)|gh[[:space:]]+pr[[:space:]]+create' || exit 0
printf '%s' "$c" | grep -qiE 'Claude-Session|Co-Authored-By:[[:space:]]*Claude' || exit 0
printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: this commit message contains a Claude attribution trailer. Remove the trailer line and commit again."}}'
