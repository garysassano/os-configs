# ~/.config/fish/config.fish
# Personal interactive shell configuration for macOS.

set -g fish_greeting

### MISE (MUST LOAD FIRST)
set -l mise_bin $HOME/.local/bin/mise
if test -x $mise_bin
    if status is-interactive
        $mise_bin activate fish | source
    else
        $mise_bin activate fish --shims | source
    end
end

# `mise activate` defines its own `mise` function. Copy and wrap it so a bare
# `mise upgrade` skips kiro-cli, whose Aqua registry metadata is incomplete.
if functions -q mise; and not functions -q __mise_activate
    functions --copy mise __mise_activate
    function mise --wraps mise -d 'mise, with kiro-cli excluded from `mise upgrade`'
        if test (count $argv) -ge 1; and test "$argv[1]" = upgrade
            and not string match -q '*kiro-cli*' -- $argv[2..]
            command mise upgrade --exclude kiro-cli $argv[2..]
            return $status
        end
        __mise_activate $argv
    end
end

### PATH
set -gx BUN_INSTALL $HOME/.bun
fish_add_path -g $BUN_INSTALL/bin
fish_add_path -g $HOME/.cargo/bin
fish_add_path -g $HOME/.antigravity/antigravity/bin
fish_add_path -g $HOME/bin
fish_add_path -g $HOME/.local/bin

if test -f $HOME/.orbstack/shell/init2.fish
    source $HOME/.orbstack/shell/init2.fish
end

### OH MY POSH
if status is-interactive
    oh-my-posh init fish --strict \
        --config $HOME/.config/oh-my-posh/themes/multiverse-neon.omp.json | source
end

### BROWSER
set -gx BROWSER open

### KEY BINDINGS
function fish_user_key_bindings
    fish_default_key_bindings

    bind \e\[1\;3D backward-word
    bind \e\[1\;3C forward-word
    bind \eb backward-word
    bind \ef forward-word
    bind \e\x7f backward-kill-word
    bind \ed kill-word
    bind \eOD backward-word
    bind \eOC forward-word
    bind \e\[H beginning-of-line
    bind \e\[F end-of-line
end

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
    set -l worktree_dir ../(string replace -a / - -- $branch)

    git fetch $remote $branch; or return
    git worktree add $worktree_dir $branch; or return
    cd $worktree_dir; or return
    printf 'Switched to new worktree for PR #%s: %s\n' $pr_number $branch
end

### GRANTED
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
