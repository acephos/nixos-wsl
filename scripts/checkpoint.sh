#!/usr/bin/env bash
# Snapshot the current config as known-good *without* rebuilding.
# Use before risky experiments:  ngood "before enabling foo"
set -euo pipefail

REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
MSG="${*:-checkpoint before experiment}"
DO_PUSH="${NIXOS_AUTO_PUSH:-1}"

cd "$REPO"

if ! git config user.email >/dev/null 2>&1; then
  git config user.email "acephos@users.noreply.github.com"
  git config user.name  "acephos"
fi

git add -A -- .
git reset -q -- .env .env.* *.pem *.key id_rsa id_ed25519 2>/dev/null || true

if git diff --cached --quiet && [[ -z "$(git status --porcelain)" ]]; then
  # still move the tag to HEAD even if clean
  git tag -f known-good -m "checkpoint: $MSG"
  echo "working tree clean — moved tag known-good → $(git rev-parse --short HEAD)"
else
  gen="$(sudo nix-env --list-generations -p /nix/var/nix/profiles/system 2>/dev/null | awk '/\(current\)/{print $1}')"
  ver="$(nixos-version 2>/dev/null || echo unknown)"
  git commit -m "known-good: $MSG" -m "gen ${gen:-?} ($ver) — checkpoint only, no rebuild"
  git tag -f known-good -m "checkpoint: $MSG"
  echo "committed + tagged known-good → $(git rev-parse --short HEAD)"
fi

if [[ "$DO_PUSH" == "1" ]] && git remote get-url origin >/dev/null 2>&1; then
  command -v gh >/dev/null 2>&1 && gh auth setup-git >/dev/null 2>&1 || true
  git push -u origin HEAD
  git push origin refs/tags/known-good --force
  echo "pushed"
fi
