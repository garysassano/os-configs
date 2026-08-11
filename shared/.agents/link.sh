#!/usr/bin/env bash

# Fan out the canonical agent configuration in ~/.agents to every installed
# harness. Idempotent: safe to re-run after `npx skills`, after installing a new
# harness, or after adding a skill.
#
#   link.sh              apply
#   link.sh --dry-run    print the plan without touching the filesystem
#
# Canonical sources:
#   ~/.agents/AGENTS.md   global instructions
#   ~/.agents/skills/     shared skills
#
# Harnesses own their config directories; this script only creates symlinks that
# point back into ~/.agents, and only prunes symlinks it could have created.
# Real directories and files in harness config directories are never touched.

set -euo pipefail

agents_dir="${HOME}/.agents"
instructions="${agents_dir}/AGENTS.md"
skills_src="${agents_dir}/skills"

dry_run=false
[[ "${1:-}" == "--dry-run" ]] && dry_run=true

# Global instruction file targets. Each harness insists on its own filename;
# there is no cross-harness standard, which is the entire reason this exists.
#
# Verified:
#   .claude       reads CLAUDE.md only; it does not read AGENTS.md
#   .codex        $CODEX_HOME/AGENTS.md
#   .codex-kiro   $CODEX_HOME/AGENTS.md (codex-home/src/instructions/mod.rs)
#   opencode      ~/.config/opencode/AGENTS.md
#
# Deliberately absent: ~/.gemini/GEMINI.md. Gemini CLI is deprecated and was
# never used. ~/.gemini exists only because Antigravity nests its state under
# it, and that state is protobuf and IDE globalStorage with no plain-file
# instructions path to target.
instruction_targets=(
	"${HOME}/.claude/CLAUDE.md"
	"${HOME}/.codex/AGENTS.md"
	"${HOME}/.codex-kiro/AGENTS.md"
	"${HOME}/.config/opencode/AGENTS.md"
)

# Skill directory targets. Each entry receives one symlink per skill.
#
# ~/.claude/skills also serves opencode, which reads Claude Code skills unless
# OPENCODE_DISABLE_CLAUDE_CODE_SKILLS is set.
skill_targets=(
	"${HOME}/.claude/skills"
	"${HOME}/.codex/skills"
	"${HOME}/.codex-kiro/skills"
	"${HOME}/.kiro/skills"
)

changed=0

log() {
	printf '%s\n' "$*"
}

run() {
	if [[ "$dry_run" == true ]]; then
		return 0
	fi
	"$@"
}

# Only provision a harness that is actually installed. Creating ~/.gemini on a
# machine without Gemini CLI would leave misleading state behind.
harness_installed() {
	[[ -d "$1" ]]
}

link_to() {
	local src="$1" dest="$2"

	if [[ -L "$dest" ]] && [[ "$(readlink -f -- "$dest")" == "$(readlink -f -- "$src")" ]]; then
		return 0
	fi

	# Back up anything real before replacing it; an empty file is placeholder
	# state that a harness created on first run and is safe to discard.
	if [[ -e "$dest" ]] && [[ ! -L "$dest" ]] && [[ -s "$dest" ]]; then
		log "  backup  ${dest} -> ${dest}.bak"
		run mv -- "$dest" "${dest}.bak"
	fi

	log "  link    ${dest}"
	run ln -sfn -- "$src" "$dest"
	changed=$((changed + 1))
}

# Remove symlinks pointing into ~/.agents/skills whose target no longer exists,
# which is what a deleted or renamed skill leaves behind.
prune_dangling() {
	local dir="$1" entry target
	for entry in "$dir"/*; do
		[[ -L "$entry" ]] || continue
		[[ -e "$entry" ]] && continue
		target="$(readlink -- "$entry")"
		case "$(cd -- "$dir" && readlink -m -- "$target")" in
		"$skills_src"/*) ;;
		*) continue ;;
		esac
		log "  prune   ${entry} (dangling)"
		run rm -- "$entry"
		changed=$((changed + 1))
	done
}

[[ -f "$instructions" ]] || {
	printf 'Missing canonical instructions: %s\n' "$instructions" >&2
	exit 1
}
[[ -d "$skills_src" ]] || {
	printf 'Missing canonical skills directory: %s\n' "$skills_src" >&2
	exit 1
}

[[ "$dry_run" == true ]] && log '(dry run)'

log 'AGENTS.md'
for dest in "${instruction_targets[@]}"; do
	harness_installed "$(dirname -- "$dest")" || {
		log "  skip    ${dest} (harness not installed)"
		continue
	}
	link_to "$instructions" "$dest"
done

log 'skills'
for dir in "${skill_targets[@]}"; do
	# A harness owns its config root; the skills subdirectory is ours to create.
	harness_installed "$(dirname -- "$dir")" || {
		log "  skip    ${dir} (harness not installed)"
		continue
	}
	[[ -d "$dir" ]] || {
		log "  mkdir   ${dir}"
		run mkdir -p -- "$dir"
	}
	[[ -d "$dir" ]] && prune_dangling "$dir"
	for skill in "$skills_src"/*; do
		[[ -d "$skill" ]] || continue
		link_to "$skill" "${dir}/$(basename -- "$skill")"
	done
done

if [[ "$dry_run" == true ]]; then
	log "${changed} change(s) pending."
else
	log "${changed} change(s) applied."
fi
