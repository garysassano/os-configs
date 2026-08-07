# ~/.config/fish/config.fish
# Ported from ~/.bashrc and ~/.bash_aliases on 2026-07-25.
# bash stays the login shell; this file drives interactive fish sessions.

# Silence fish's built-in two-line greeting. Defining it empty is enough:
# fish_greeting only builds the default text when the variable is unset.
set -g fish_greeting

### MISE (MUST LOAD FIRST)
if status is-interactive
    mise activate fish | source
else
    mise activate fish --shims | source
end

# `mise activate` defines its own `mise` function, which already handles the
# `deactivate`/`shell`/`sh` eval passthrough that _mise_passthrough did in bash.
# Copy it, then wrap it so a bare `mise upgrade` still skips kiro-cli.
# The `not functions -q __mise_activate` guard matters: without it, re-sourcing
# this file would copy the wrapper below onto itself and recurse forever.
if functions -q mise; and not functions -q __mise_activate
    functions --copy mise __mise_activate
    function mise --wraps mise -d 'mise, with kiro-cli excluded from `mise upgrade`'
        # aqua's registry entry for kiro.dev/kiro-cli has no repo_owner/repo_name,
        # so every version lookup emits two warnings. Exclude it from upgrades
        # unless it was named explicitly.
        #
        # NOTE: --exclude matches the installed tool name (`kiro-cli`). The
        # backend-qualified id (`aqua:kiro.dev/kiro-cli`) silently no-ops.
        if test (count $argv) -ge 1; and test "$argv[1]" = upgrade
            and not string match -q '*kiro-cli*' -- $argv[2..]
            command mise upgrade --exclude kiro-cli $argv[2..]
            return $status
        end
        __mise_activate $argv
    end
end

### PATH
# fish_add_path prepends, so the LAST call ends up first. Order below yields
# ~/.local/bin, ~/bin, ~/.cargo/bin, then mise's paths - matching bash, but
# without bash's duplicate ~/.local/bin. Non-existent dirs are skipped, so
# ~/.bun/bin (which does not exist yet) is simply picked up if it appears.
set -gx BUN_INSTALL $HOME/.bun
fish_add_path -g $BUN_INSTALL/bin
fish_add_path -g $HOME/.cargo/bin
fish_add_path -g $HOME/bin
fish_add_path -g $HOME/.local/bin

### OH MY POSH
if status is-interactive
    oh-my-posh init fish --strict --config $HOME/.config/oh-my-posh/themes/multiverse-neon.omp.json | source
end

### BROWSER
# Many CLIs check $BROWSER first and just print the URL when it is empty, which is
# why so many of them refused to open anything. Point it at xdg-open rather than a
# browser directly, so one place decides which browser opens: the default handler
# registered with xdg-settings. That resolves to wsl-explorer.desktop ->
# /mnt/c/WINDOWS/explorer.exe, handing the URL to the Windows default browser via
# WSL interop. explorer.exe is a Windows built-in, so this needs no wslu, which was
# archived upstream on 2025-03-01 and removed from this machine.
#
# xdg-open strips itself out of $BROWSER internally, so this cannot recurse.
# Caveat: explorer.exe returns non-zero even on success and xdg-open passes that
# through (exit 4). Launches are reliable; only the status is wrong.
#
# To switch to a WSL-native browser, repoint the handler rather than editing here:
#   xdg-settings set default-web-browser google-chrome.desktop
set -gx BROWSER xdg-open

### GPG
# pinentry-curses draws its prompt on a terminal, and gpg-agent needs to be told
# which one. Without this, signing fails with "Inappropriate ioctl for device".
set -gx GPG_TTY (tty)

### ALIASES
alias ll 'ls -alF'
alias la 'ls -A'
alias l 'ls -CF'
alias pj 'npx projen'

function grep --wraps grep -d 'grep, with colour'
    command grep --color=auto $argv
end

### GIT / WORKTREES
function cpr -d 'Check out a GitHub PR into a sibling worktree and cd into it'
    set -l pr_number $argv[1]
    set -l remote origin
    test (count $argv) -ge 2; and set remote $argv[2]

    if test -z "$pr_number"
        echo "Usage: cpr <PR_NUMBER> [REMOTE]" >&2
        return 2
    end
    if not command -q gh
        echo "cpr: missing gh (GitHub CLI)." >&2
        return 127
    end

    set -l branch (gh pr view $pr_number --json headRefName -q .headRefName); or return
    # Slashes are illegal in a sibling directory name.
    set -l worktree_dir ../(string replace -a / - -- $branch)

    git fetch $remote $branch; or return
    git worktree add $worktree_dir $branch; or return
    cd $worktree_dir; or return
    printf 'Switched to new worktree for PR #%s: %s\n' $pr_number $branch
end

### GRANTED
# granted ships a native fish entrypoint next to the `assume` shim.
function assume --wraps assume -d 'granted: assume an AWS role'
    source (dirname (mise which assume))/assume.fish $argv
end

### PYTHON VENVS (mise-managed)
function mkvenv -d 'Add a mise.local.toml that auto-activates ./.venv (or a given path)'
    set -l venv_path .venv
    if test (count $argv) -gt 0
        set venv_path $argv[1]
    end

    if test -e mise.local.toml
        echo "mkvenv: mise.local.toml already exists - edit it by hand." >&2
        return 1
    end

    printf '[env]\n_.python.venv = { path = "%s", create = true }\n' $venv_path >mise.local.toml
    mise trust -q .
    echo "mkvenv: mise.local.toml -> $venv_path (cd out and back in to activate)"
end
