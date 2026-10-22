#!/bin/sh
# Install Harness Studio on Omarchy (or any Arch system): builds the package from this folder and installs it.
set -eu
cd "$(dirname "$0")"
command -v pacman >/dev/null || { echo "install.sh: needs pacman (Arch or Omarchy)" >&2; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "install.sh: only x86_64 is packaged" >&2; exit 1; }
makepkg -si --needed "$@"
echo "Installed. Launch 'Harness Studio' from the app launcher (Super+Space), or run: harness-studio"
