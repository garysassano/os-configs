---
name: client-tree-tooling
description: Scope a client's tools, env vars, and teardown notes to its own ~/git-<client>/ tree instead of the personal mise baseline. Use when work in a client tree needs a tool, version, or environment variable that should not exist globally, when a client repo's tooling has already leaked into ~/.config/mise/config.toml, or when recording what an engagement changed so it can be removed later.
---

# Client Tree Tooling

Client work arrives with tooling nobody wants permanently: an EOL language runtime, a pinned terraform, an environment variable that only makes one vendor wrapper behave. The default move — declaring it in `~/.config/mise/config.toml` — is wrong twice over. It applies the tool everywhere, and when the engagement ends nothing records which entries were ever client-specific.

Scope it to the client tree instead.

The versions are the sharpest part of this. Client tooling tends to be years behind — an EOL runtime, a terraform two minors back, a CLI kept at whatever the pipeline was built against. Globally declared, those become the machine's default: the old binary is what `PATH` resolves, what a new project inherits, and what stays behind after the engagement ends. Scoped to the tree, the same version is present exactly where the client needs it and absent everywhere else, so the baseline stays current.

## Where configuration goes

`~/git-<client>/mise.toml`, one file for the whole tree:

```toml
[tools]
ruby = "2.7.8"

[env]
SOME_VENDOR_BYPASS = "1"
```

This beats the alternatives for concrete reasons:

- **Not the global config.** A client-only pin there applies in every directory. It also silently overrides other repositories: mise does not read idiomatic version files (`.ruby-version`, `.nvmrc`) unless `idiomatic_version_file_enable_tools` is set, so a global `ruby = "2"` hands 2.x to a repository that pins 3.1.4 and nothing complains.
- **Not a per-repo `mise.local.toml`.** It sits inside a repository, so it needs a `.git/info/exclude` entry to stay out of `git status`, and it covers one repository when a client tree usually holds several.
- **Not a `MISE_ENV` profile.** It has to be activated by hand every session. A tree-level file is picked up by directory, which is the property that makes it stick.

`~/git-<client>/` is normally not itself a git repository, so this file needs no ignore rule anywhere.

Run `mise trust ~/git-<client>` after creating it.

## What not to duplicate

A repository that declares its own versions — `.tool-versions`, or its own `mise.toml` — is already scoped, and it wins over the tree file. Do not copy those pins upward. Run `mise install` in the repository so the declared versions exist, and leave the declaration where the project put it.

Add to the tree file only what the project does not declare itself: a runtime whose version lives in a file mise ignores, or an environment variable the tooling needs on this machine specifically.

## Installs are shared, declarations are not

Declaring the same version in two trees costs nothing: mise installs land in `~/.local/share/mise/installs/<tool>/<version>` and are reused. There is never a reason to keep a client pin global "so other projects can use it too" — the other project should declare it, and will get the same install.

## Verify the scoping

```
cd ~/git-<client>/<repo>  && mise current <tool>   # expected version
cd ~/git-<other>/<repo>   && mise current <tool>   # nothing, or that repo's own
cd ~                      && mise current <tool>   # nothing
```

Check the third one. It is the one that catches a pin still sitting in the baseline.

## Catching drift

Client entries reach the global config quietly, often added mid-task to unblock a build. If the machine's configuration is snapshotted in a repository, diff the live file against the snapshot — that comparison is what surfaces the drift:

```
diff ~/.config/mise/config.toml <snapshot>/.config/mise/config.toml
```

Anything in the live file that exists only for the client belongs in the tree config instead.

## Record what leaves the tree

Deleting the tree removes everything inside it. Everything else needs a list: `~/git-<client>/TEARDOWN.md`, covering tools installed, home-directory files edited, keys and credentials created, and settings changed on remote services — each with why it exists and what removing it involves.

Put an `AGENTS.md` at the tree root (symlink `CLAUDE.md` to it) telling agents to append to that one list rather than starting parallel notes. Both files are read automatically by anything working under the tree.

## Keep the client name out of publishable repositories

A `~/git-<client>/` path names who the work is for, which is disclosure regardless of whether any credential leaks. Client teardown notes stay in the client tree; they never move into a machine-configuration repository that might be published.

Watch for automatic paths into such a repository. A sync that copies `~/.gitconfig` verbatim carries every `includeIf gitdir:~/git-<client>/` entry with it, without anyone choosing to add the client. Where a pre-publication checklist exists, name that file in it.
