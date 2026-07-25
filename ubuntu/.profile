# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# mise shims, for non-interactive shells.
#
# Interactive shells are fish and get the real `mise activate`. This exists for
# `bash -lc`, which agent harnesses and scripts use: ~/.bashrc returns early on
# the non-interactive guard, so without this a spawned bash resolves `rg` to
# /usr/bin/rg instead of the mise-managed build. Shims work without activation.
#
# Placed before the two blocks below because each one prepends: whichever runs
# last ends up first on PATH. ~/.local/bin must outrank the shims so the `gh`
# wrapper there keeps winning over mise's `gh`, matching fish's ordering.
if [ -d "$HOME/.local/share/mise/shims" ]; then
    PATH="$HOME/.local/share/mise/shims:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ]; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi
