#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $(basename "$0") <plugin_pkg> <repo_dir> [--no-build]" >&2
  exit 2
fi

PLUGIN_PKG="$1"
REPO_DIR="$2"
NO_BUILD="${3:-}"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
PLUGIN_DIR="$CACHE_DIR/opencode/node_modules/$PLUGIN_PKG"

if [ ! -d "$PLUGIN_DIR" ]; then
  echo "Plugin cache dir not found: $PLUGIN_DIR" >&2
  echo "Tip: run OpenCode once so it installs/caches the plugin." >&2
  exit 1
fi

if [ ! -d "$REPO_DIR" ]; then
  echo "Repo dir not found: $REPO_DIR" >&2
  exit 1
fi

if [ "$NO_BUILD" != "--no-build" ]; then
  echo "[build] building plugin in $REPO_DIR" >&2
  if command -v bun >/dev/null 2>&1 && [ -f "$REPO_DIR/bun.lock" ]; then
    (cd "$REPO_DIR" && bun run build)
  else
    (cd "$REPO_DIR" && npm run -s build)
  fi
fi

if [ ! -d "$REPO_DIR/dist" ]; then
  echo "Built dist/ not found at: $REPO_DIR/dist" >&2
  exit 1
fi

TS=$(date +%Y%m%d-%H%M%S)
BACKUP="$PLUGIN_DIR/dist.bak.$TS"

if [ -d "$PLUGIN_DIR/dist" ]; then
  cp -a "$PLUGIN_DIR/dist" "$BACKUP"
else
  mkdir -p "$BACKUP"
fi

rm -rf "$PLUGIN_DIR/dist"
cp -a "$REPO_DIR/dist" "$PLUGIN_DIR/dist"

echo "[ok] hot-swapped $PLUGIN_PKG" >&2
echo "[ok] backup: $BACKUP" >&2
echo "[next] restart opencode" >&2
