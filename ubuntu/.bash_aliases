### PROJEN
alias pj="npx projen"

# --- cpr: checkout PR into worktree ---
### GIT / WORKTREES
# cpr: check out a GitHub Pull Request into a sibling worktree
# Usage: cpr <PR_NUMBER> [REMOTE]   # REMOTE defaults to 'origin'
# Creates: ../<branch> (slashes become dashes), then cd's into it.
# Requires: GitHub CLI (gh) + authentication (gh auth login)
cpr() {
  local pr_number="$1" remote="${2:-origin}"

  [[ -n "${pr_number:-}" ]] || { echo "Usage: cpr <PR_NUMBER> [REMOTE]" >&2; return 2; }
  command -v gh >/dev/null 2>&1 || { echo "cpr: missing gh (GitHub CLI)." >&2; return 127; }

  local branch worktree_dir
  branch="$(gh pr view "$pr_number" --json headRefName -q .headRefName)" || return
  worktree_dir="../${branch//\//-}"

  git fetch "$remote" "$branch" || return
  git worktree add "$worktree_dir" "$branch" || return
  cd "$worktree_dir" || return
  printf 'Switched to new worktree for PR #%s: %s\n' "$pr_number" "$branch"
}
# --- end cpr ---
