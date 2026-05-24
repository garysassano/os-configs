#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $(basename "$0") <plugin_pkg> [backup_dir]" >&2
  exit 2
fi

PLUGIN_PKG="$1"
BACKUP_DIR="${2:-}"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
PLUGIN_DIR="$CACHE_DIR/opencode/node_modules/$PLUGIN_PKG"

if [ ! -d "$PLUGIN_DIR" ]; then
  echo "Plugin cache dir not found: $PLUGIN_DIR" >&2
  exit 1
fi

if [ -z "$BACKUP_DIR" ]; then
  BACKUP_DIR=$(ls -1dt "$PLUGIN_DIR"/dist.bak.* 2>/dev/null | head -n 1 || true)
fi

if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
  echo "Backup dir not found. Provide it explicitly, or ensure $PLUGIN_DIR/dist.bak.* exists." >&2
  exit 1
fi

rm -rf "$PLUGIN_DIR/dist"
cp -a "$BACKUP_DIR" "$PLUGIN_DIR/dist"

echo "[ok] restored $PLUGIN_PKG from $BACKUP_DIR" >&2
echo "[next] restart opencode" >&2
