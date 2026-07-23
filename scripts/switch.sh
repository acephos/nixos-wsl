#!/usr/bin/env bash
# Rebuild and switch to this flake. Run from anywhere.
set -euo pipefail
REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
exec sudo nixos-rebuild switch --flake "$REPO#nixos" "$@"
