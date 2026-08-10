# mise shims for POSIX-compatible login shells and explicit `bash -lc`
# subprocesses. Interactive shells use fish and activate mise in config.fish.
if [ -d "$HOME/.local/share/mise/shims" ]; then
    PATH="$HOME/.local/share/mise/shims:$PATH"
fi

if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi

export PATH
