#!/usr/bin/env bash

# Manual smoke test for the gh wrapper at ~/.local/bin/gh.
#
# Every assertion about a defence is paired with a control proving the failure it
# prevents is real against ordinary git or the unwrapped binary. Without the
# controls a passing suite would say nothing: several of these attacks only work in
# one specific form, and the obvious form silently does nothing.
#
# Not run by sync-from-home.sh. It needs network access, live Git Credential
# Manager credentials, and it creates throwaway repositories inside the secondary
# repository. Run it by hand after touching the wrapper; the sync script only lints
# this file.
#
# Account names are never hardcoded. Both are derived from the tracked Git
# configuration for the two repositories given, which keeps the account linkage in
# ~/.gitconfig alone — the file already listed for stripping before this repository
# could be made public. The identity assertions are therefore integration
# assertions ("the wrapper follows the configured mapping"), not independent claims
# that a particular account owns a particular tree.
#
# Usage:
#   test-gh-wrapper.sh <primary-repo> <secondary-repo>
#   GH_WRAPPER_TEST_PRIMARY_REPO=... GH_WRAPPER_TEST_SECONDARY_REPO=... test-gh-wrapper.sh

set -uo pipefail

gh_wrapper="${GH_WRAPPER:-${HOME}/.local/bin/gh}"
primary_repo="${1:-${GH_WRAPPER_TEST_PRIMARY_REPO:-}}"
secondary_repo="${2:-${GH_WRAPPER_TEST_SECONDARY_REPO:-}}"

usage() {
	printf 'usage: %s <primary-repo> <secondary-repo>\n' "${0##*/}" >&2
	printf '   or: GH_WRAPPER_TEST_PRIMARY_REPO=... GH_WRAPPER_TEST_SECONDARY_REPO=... %s\n' "${0##*/}" >&2
	exit 2
}

[[ -n "$primary_repo" && -n "$secondary_repo" ]] || usage
[[ -x "$gh_wrapper" ]] || {
	printf 'not executable: %s\n' "$gh_wrapper" >&2
	exit 2
}

for repo in "$primary_repo" "$secondary_repo"; do
	if [[ "$(git -C "$repo" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
		printf 'not a Git worktree: %s\n' "$repo" >&2
		exit 2
	fi
done

# Let Git resolve the mapping; do not reimplement includeIf matching here.
account_of() {
	git -C "$1" config --global --includes --get credential.https://github.com.username 2>/dev/null
}
primary_account="$(account_of "$primary_repo")"
secondary_account="$(account_of "$secondary_repo")"

if [[ -z "$primary_account" || -z "$secondary_account" ]]; then
	printf 'both repositories must map to a configured account (got %s / %s)\n' \
		"${primary_account:-<none>}" "${secondary_account:-<none>}" >&2
	exit 2
fi
if [[ "$primary_account" == "$secondary_account" ]]; then
	printf 'both repositories map to %s; the cross-tree assertions need two accounts\n' \
		"$primary_account" >&2
	exit 2
fi

primary_git_dir="$(git -C "$primary_repo" rev-parse --absolute-git-dir)"
secondary_git_dir="$(git -C "$secondary_repo" rev-parse --absolute-git-dir)"

scratch=()
cleanup() {
	local path
	for path in ${scratch[@]+"${scratch[@]}"}; do
		rm -rf -- "$path"
	done
}
# Cleanup hangs off EXIT alone. Trapping INT/TERM to run cleanup directly would not
# terminate the shell — the handler returns, execution resumes, and the run creates
# more throwaway repositories after having just removed them. There is no `set -e`
# to stop it either. So the signal handlers only exit, which is what triggers the
# EXIT trap. A manual test is interrupted often enough for this to matter.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Throwaway repositories live inside the secondary repository so whatever includeIf
# rule governs it governs them too.
#
# The path comes back in a variable rather than on stdout: `repo="$(scratch_repo)"`
# would run the function in a subshell, so the append to `scratch` would be lost and
# the cleanup trap would find nothing to remove.
scratch_repo_path=""
scratch_repo() {
	scratch_repo_path="$(mktemp -d "${secondary_repo}/.gh-wrapper-test.XXXXXX")"
	scratch+=("$scratch_repo_path")
	git -C "$scratch_repo_path" init -q
}

pass=0
fail=0

report() { # description expected actual
	if [[ "$2" == "$3" ]]; then
		printf '  PASS  %-54s %s\n' "$1" "$3"
		pass=$((pass + 1))
	else
		printf '  FAIL  %-54s expected=%s actual=%s\n' "$1" "$2" "$3"
		fail=$((fail + 1))
	fi
}

note() { printf '        %s\n' "$1"; }
first_line() { head -n1 | cut -c1-100; }
exit_of() {
	("$@" >/dev/null 2>&1)
	echo $?
}
login_in() { (cd "$1" && shift && timeout 120 "$gh_wrapper" api user --jq .login 2>&1 | first_line); }

# Compares against the credential held in memory rather than a token-shaped regex,
# because token formats change. Bash substring matching keeps the value out of any
# process argument list. Deliberately no guard for an empty needle: both credentials
# are required up front, and an empty one would match everything and fail loudly
# rather than report "absent" for every leak check.
holds_token() { # haystack token
	if [[ "$1" == *"$2"* ]]; then echo "yes"; else echo "no"; fi
}

token_for() { # account repo
	local field value token=""
	while IFS='=' read -r field value; do
		if [[ "$field" == "password" ]]; then token="$value"; fi
	done < <(
		printf 'protocol=https\nhost=github.com\nusername=%s\n\n' "$1" |
			git -C "$2" credential fill 2>/dev/null
	)
	printf '%s' "$token"
}

# Both credentials are required, not optional. The leak checks compare output
# against the real token, so a missing one would make every "credential is absent"
# assertion pass without testing anything, and skipping the ambient-token section
# would quietly drop three defences. The suite is an integration test of two live
# accounts by design; refuse to run as a weaker suite.
primary_token="$(token_for "$primary_account" "$primary_repo")"
secondary_token="$(token_for "$secondary_account" "$secondary_repo")"
for account_and_token in "${primary_account}:${primary_token}" "${secondary_account}:${secondary_token}"; do
	if [[ -z "${account_and_token#*:}" ]]; then
		printf 'no Git Credential Manager credential for %s; sign it in before running this suite\n' \
			"${account_and_token%%:*}" >&2
		exit 2
	fi
done

printf 'wrapper:   %s\n' "$gh_wrapper"
printf 'primary:   %s -> %s (credential held, %s chars, never printed)\n' \
	"$primary_repo" "$primary_account" "${#primary_token}"
printf 'secondary: %s -> %s (credential held, %s chars, never printed)\n\n' \
	"$secondary_repo" "$secondary_account" "${#secondary_token}"

echo "== 1. identity follows the repository =="
report "primary repository" "$primary_account" "$(login_in "$primary_repo")"
report "secondary repository" "$secondary_account" "$(login_in "$secondary_repo")"

echo
echo "== 2. outside a Git worktree =="
report "refuses (exit 1)" "1" "$( (cd /tmp && exit_of timeout 120 "$gh_wrapper" api user))"
note "$(cd /tmp && "$gh_wrapper" api user 2>&1 | first_line)"

echo
echo "== 3. ambient tokens are discarded =="
report "GH_TOKEN=<primary> in secondary repository" "$secondary_account" \
	"$(cd "$secondary_repo" && GH_TOKEN="$primary_token" timeout 120 "$gh_wrapper" api user --jq .login 2>/dev/null | first_line)"
report "GITHUB_TOKEN=<primary> in secondary repository" "$secondary_account" \
	"$(cd "$secondary_repo" && GITHUB_TOKEN="$primary_token" timeout 120 "$gh_wrapper" api user --jq .login 2>/dev/null | first_line)"
report "control: unwrapped gh honours it" "$primary_account" \
	"$(cd "$secondary_repo" && GH_TOKEN="$primary_token" timeout 120 "$(mise -C "$HOME" which gh)" api user --jq .login 2>/dev/null | first_line)"

echo
echo "== 4. repository-local username override =="
scratch_repo
repo="$scratch_repo_path"
git -C "$repo" config credential.https://github.com.username "$primary_account"
report "control: plain git reads the override" "$primary_account" \
	"$(git -C "$repo" config --includes --get credential.https://github.com.username)"
report "wrapper ignores it" "$secondary_account" "$(login_in "$repo")"

echo
echo "== 5. repository-local credential.helper =="
scratch_repo
repo="$scratch_repo_path"
cat >"${repo}/impostor-helper" <<'HELPER'
#!/usr/bin/env bash
printf 'username=impostor\npassword=impostor-supplied-token\n'
HELPER
chmod +x "${repo}/impostor-helper"
# Appending is not enough: the global helper is earlier in the list and answers
# first. The list has to be reset, which drops the global helper.
git -C "$repo" config --add credential.helper ""
git -C "$repo" config --add credential.helper "${repo}/impostor-helper"
report "control: plain git credential fill is hijacked" "username=impostor" \
	"$( (cd "$repo" && printf 'protocol=https\nhost=github.com\nusername=%s\n\n' "$secondary_account" | git credential fill 2>/dev/null | rg '^username=' | first_line))"
report "wrapper ignores repository-local helper" "$secondary_account" "$(login_in "$repo")"
git -C "$repo" config --unset-all credential.helper
git -C "$repo" config --add credential.helper ""
git -C "$repo" config --add credential.https://github.com.helper "${repo}/impostor-helper"
report "control: URL-scoped hijack works on plain git" "username=impostor" \
	"$( (cd "$repo" && printf 'protocol=https\nhost=github.com\nusername=%s\n\n' "$secondary_account" | git credential fill 2>/dev/null | rg '^username=' | first_line))"
report "wrapper ignores URL-scoped helper" "$secondary_account" "$(login_in "$repo")"

echo
echo "== 6. gh auth allowlist =="
cd "$secondary_repo" || exit 1
for subcommand in login logout switch refresh setup-git token; do
	report "gh auth ${subcommand} rejected" "1" "$(exit_of "$gh_wrapper" auth "$subcommand")"
done
report "reordered: gh auth --hostname github.com login" "1" \
	"$(exit_of "$gh_wrapper" auth --hostname github.com login)"
report "reordered: gh auth -h github.com login" "1" \
	"$(exit_of "$gh_wrapper" auth -h github.com login)"
report "reordered: gh auth --hostname github.com token" "1" \
	"$(exit_of "$gh_wrapper" auth --hostname github.com token)"
report "bare gh auth rejected" "1" "$(exit_of "$gh_wrapper" auth)"
note "$("$gh_wrapper" auth --hostname github.com login 2>&1 | first_line)"

echo
echo "== 6b. --show-token in every spelling =="
for form in --show-token --show-token=true --show-token=false -t -t=true -t=false -at -ta -ath; do
	output="$("$gh_wrapper" auth status "$form" 2>&1)"
	report "gh auth status ${form} rejected" "1" "$?"
	report "  ...and the credential is absent" "no" "$(holds_token "$output" "$secondary_token")"
done

echo
echo "== 6c. flag values containing 't' are not read as -t =="
for form in "-h=github.com" "--hostname=github.com"; do
	report "gh auth status ${form} allowed" "0" "$(exit_of "$gh_wrapper" auth status "$form")"
done

echo
echo "== 7. permitted auth forms =="
report "gh auth status allowed" "0" "$(exit_of "$gh_wrapper" auth status)"
report "gh auth --help allowed" "0" "$(exit_of "$gh_wrapper" auth --help)"
status_output="$("$gh_wrapper" auth status 2>&1)"
report "auth status does not print the credential" "no" "$(holds_token "$status_output" "$secondary_token")"
report "auth status shows a masked token line" "1" "$(rg -c 'Token: .*\*{4}' <<<"$status_output" || true)"
note "$(rg 'Logged in' <<<"$status_output" | first_line)"
note "$(rg 'Token:' <<<"$status_output" | first_line)"

echo
echo "== 8. repository-local mise configuration =="
scratch_repo
repo="$scratch_repo_path"
printf '[tools]\ngithub-cli = "2.40.0"\n' >"${repo}/mise.toml"
mise trust "${repo}/mise.toml" >/dev/null 2>&1
note "control, cwd-local mise which gh: $( (cd "$repo" && timeout 60 mise which gh 2>&1 | first_line))"
note "mise -C \$HOME which gh:          $(timeout 60 mise -C "$HOME" which gh 2>&1 | first_line)"
report "wrapper unaffected" "$secondary_account" "$(login_in "$repo")"
mise trust --untrust "${repo}/mise.toml" >/dev/null 2>&1

echo
echo "== 8b. ambient Git environment overrides =="
scratch_repo
impostor_global="$scratch_repo_path"
git config --file "${impostor_global}/gitconfig" credential.helper "$(git config --global --includes --get credential.helper)"
git config --file "${impostor_global}/gitconfig" credential.https://github.com.username "$primary_account"
report "control: GIT_DIR retargets git" "$secondary_account" \
	"$(cd "$primary_repo" && GIT_DIR="$secondary_git_dir" git config --global --includes --get credential.https://github.com.username)"
report "control: GIT_DIR makes /tmp a worktree" "true" \
	"$(cd /tmp && GIT_DIR="$secondary_git_dir" git rev-parse --is-inside-work-tree 2>&1 | first_line)"
report "control: GIT_CONFIG_GLOBAL replaces the account" "$primary_account" \
	"$(cd "$secondary_repo" && GIT_CONFIG_GLOBAL="${impostor_global}/gitconfig" git config --global --includes --get credential.https://github.com.username)"
report "control: GIT_CONFIG_COUNT injects an account" "$primary_account" \
	"$(cd "$secondary_repo" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.https://github.com.username GIT_CONFIG_VALUE_0="$primary_account" git config --includes --get credential.https://github.com.username)"
report "GIT_DIR cannot change identity (primary)" "$primary_account" \
	"$(cd "$primary_repo" && GIT_DIR="$secondary_git_dir" timeout 120 "$gh_wrapper" api user --jq .login 2>&1 | first_line)"
report "GIT_DIR cannot change identity (secondary)" "$secondary_account" \
	"$(cd "$secondary_repo" && GIT_DIR="$primary_git_dir" timeout 120 "$gh_wrapper" api user --jq .login 2>&1 | first_line)"
report "GIT_DIR cannot make /tmp a worktree (exit 1)" "1" \
	"$( (cd /tmp && GIT_DIR="$secondary_git_dir" exit_of timeout 120 "$gh_wrapper" api user))"
report "GIT_WORK_TREE/GIT_COMMON_DIR cannot retarget" "$primary_account" \
	"$(cd "$primary_repo" && GIT_DIR="$secondary_git_dir" GIT_WORK_TREE="$secondary_repo" GIT_COMMON_DIR="$secondary_git_dir" timeout 120 "$gh_wrapper" api user --jq .login 2>&1 | first_line)"
report "GIT_CONFIG_GLOBAL cannot change the account" "$secondary_account" \
	"$(cd "$secondary_repo" && GIT_CONFIG_GLOBAL="${impostor_global}/gitconfig" timeout 120 "$gh_wrapper" api user --jq .login 2>&1 | first_line)"
report "GIT_CONFIG_COUNT injection cannot change it" "$secondary_account" \
	"$(cd "$secondary_repo" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.https://github.com.username GIT_CONFIG_VALUE_0="$primary_account" timeout 120 "$gh_wrapper" api user --jq .login 2>&1 | first_line)"
report "GIT_ASKPASS cannot supply the credential" "$secondary_account" \
	"$(cd "$secondary_repo" && GIT_ASKPASS="${impostor_global}/gitconfig" timeout 120 "$gh_wrapper" api user --jq .login 2>&1 | first_line)"

echo
echo "== 9. documented credential-maintenance command =="
# credential.helper is configuration, not shell source: unescape the one escape Git
# applies to a path and run it directly rather than through eval.
helper_value="$(git config --global --includes --get credential.helper 2>/dev/null || true)"
helper_path="${helper_value//\\ / }"
if [[ -n "$helper_path" && -x "$helper_path" ]]; then
	report "'<helper> github list' exits 0" "0" "$(exit_of "$helper_path" github list)"
	accounts="$("$helper_path" github list 2>/dev/null)"
	report "lists both configured accounts" "yes" \
		"$(if rg -q "^${primary_account}$" <<<"$accounts" && rg -q "^${secondary_account}$" <<<"$accounts"; then echo yes; else echo no; fi)"
	note "helper: ${helper_path}"
else
	note "SKIP: credential.helper is not a plain executable path (${helper_value:-<unset>})"
fi

echo
echo "== 10. gh stores no account of its own =="
# Absent and {} are the same state, and absent is what a freshly installed machine
# has before gh has ever run. Anything else is reported verbatim so the failure
# names the account that should not be there.
hosts_state=""
if [[ -f "${HOME}/.config/gh/hosts.yml" ]]; then
	hosts_state="$(tr -d ' \n' <"${HOME}/.config/gh/hosts.yml")"
fi
if [[ -z "$hosts_state" || "$hosts_state" == "{}" ]]; then
	hosts_state="none"
fi
report "no account stored in hosts.yml" "none" "$hosts_state"

echo
printf 'passed=%d failed=%d\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
