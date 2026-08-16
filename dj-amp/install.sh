#!/bin/bash

# Install DJ Amp into the running Omarchy shell.
#
# `omarchy plugin add <git-url>` is the normal path and wants a repository with
# manifest.json at its root. This script is the hand-install equivalent for a
# checkout that lives in a subdirectory: it copies the plugin folder into
# ~/.config/omarchy/plugins/, links the two commands onto PATH, and asks the
# shell to pick it up.

set -euo pipefail

PLUGIN_ID="matrixjockey.dj-amp"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
BIN_DIR="$HOME/.local/bin"

if [[ ! -f "$SOURCE_DIR/manifest.json" ]]; then
  echo "install.sh: no manifest.json next to this script" >&2
  exit 1
fi

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$SOURCE_DIR"
  echo "Manifest validated."
fi

echo "Installing $PLUGIN_ID to $TARGET_DIR"
mkdir -p "$(dirname "$TARGET_DIR")"
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

# Copy the plugin itself. install.sh and the git metadata are not part of it.
for entry in "$SOURCE_DIR"/*; do
  name="$(basename "$entry")"
  [[ $name == "install.sh" ]] && continue
  cp -r "$entry" "$TARGET_DIR/"
done

chmod +x "$TARGET_DIR/bin/dj-amp" "$TARGET_DIR/bin/dj-amp-brain"

# The plugin runs bin/dj-amp-brain by its own path, so the link is only for
# your convenience at a prompt or in a keybind.
mkdir -p "$BIN_DIR"
ln -sf "$TARGET_DIR/bin/dj-amp" "$BIN_DIR/dj-amp"
echo "Linked $BIN_DIR/dj-amp"

missing=()
command -v cliamp >/dev/null 2>&1 || missing+=("cliamp")
command -v jq >/dev/null 2>&1 || missing+=("jq")
if ((${#missing[@]} > 0)); then
  echo
  echo "Still needed: ${missing[*]}"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  echo "Asked the shell to rescan."
fi

cat <<NEXT

Installed. To put it in the bar:

  omarchy plugin enable $PLUGIN_ID

It lands on the right-hand side; move it with \`omarchy bar move\`. The widget
stays hidden until cliamp is actually running.
NEXT
