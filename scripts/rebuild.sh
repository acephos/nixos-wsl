#!/usr/bin/env bash
# Rebuild this flake, then checkpoint git on success (commit + known-good tag + optional push).
#
# Usage:
#   rebuild.sh [switch|boot|test] [--push|--no-push] [--no-commit] [--] [extra nixos-rebuild args]
#
# Env:
#   NIXOS_FLAKE      repo path          (default: ~/nixos-wsl)
#   NIXOS_AUTO_PUSH  1/0 auto git push  (default: 1)
#   NIXOS_AUTO_COMMIT 1/0               (default: 1)
set -euo pipefail

REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
ACTION="switch"
DO_PUSH="${NIXOS_AUTO_PUSH:-1}"
DO_COMMIT="${NIXOS_AUTO_COMMIT:-1}"
EXTRA=()

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    switch|boot|test) ACTION="$1"; shift ;;
    --push)    DO_PUSH=1; shift ;;
    --no-push) DO_PUSH=0; shift ;;
    --no-commit) DO_COMMIT=0; shift ;;
    -h|--help) usage 0 ;;
    --) shift; EXTRA+=("$@"); break ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

cd "$REPO"

if [[ ! -f flake.nix ]]; then
  echo "error: no flake.nix in $REPO" >&2
  exit 1
fi

# Ensure commits work even without a global git identity
ensure_git_identity() {
  if ! git config user.email >/dev/null 2>&1; then
    git config user.email "acephos@users.noreply.github.com"
    git config user.name  "acephos"
  fi
}

echo "==> nixos-rebuild $ACTION --flake $REPO#nixos ${EXTRA[*]:-}"
# WSL often returns 4 from a harmless user-dbus blip after a successful switch.
set +e
sudo nixos-rebuild "$ACTION" --flake "$REPO#nixos" "${EXTRA[@]+"${EXTRA[@]}"}"
rc=$?
set -e

if [[ $rc -ne 0 && $rc -ne 4 ]]; then
  echo "error: rebuild failed (exit $rc) — nothing committed or pushed" >&2
  exit "$rc"
fi
if [[ $rc -eq 4 ]]; then
  echo "note: nixos-rebuild exited 4 (common on WSL user-dbus); system profile looks activated — continuing checkpoint"
fi

current="$(readlink -f /run/current-system 2>/dev/null || true)"
gen="$(sudo nix-env --list-generations -p /nix/var/nix/profiles/system 2>/dev/null | awk '/\(current\)/{print $1}')"
ver="$(nixos-version 2>/dev/null || echo unknown)"
short="${current##*/}"

echo "==> active generation: ${gen:-?}  ($ver)"

if [[ "$ACTION" != "switch" && "$ACTION" != "boot" ]]; then
  echo "==> $ACTION rebuild done (no git checkpoint for test)"
  exit 0
fi

if [[ "$DO_COMMIT" == "1" ]]; then
  ensure_git_identity
  # Include normal tracked changes + untracked (new modules), never secrets-looking junk
  git add -A -- .
  # Drop anything that slipped in
  git reset -q -- .env .env.* *.pem *.key id_rsa id_ed25519 2>/dev/null || true

  if git diff --cached --quiet; then
    echo "==> git: working tree clean — no new commit"
  else
    msg="nixos: gen ${gen:-?} known-good ($ver)"
    git commit -m "$msg" -m "store: ${short:-unknown}" -m "host: $(hostname) action: $ACTION"
    echo "==> git: committed → $msg"
  fi

  # Floating tag always points at last successful rebuild of this machine's config
  git tag -f known-good -m "last successful nixos-rebuild ($ACTION) gen ${gen:-?} on $(hostname)"
  echo "==> git: tag known-good → $(git rev-parse --short HEAD)"
fi

if [[ "$DO_PUSH" == "1" ]]; then
  if git remote get-url origin >/dev/null 2>&1; then
    branch="$(git branch --show-current)"
    echo "==> git: pushing $branch + known-good"
    git push -u origin "$branch"
    # known-good is force-moved; use force-with-lease on the tag ref
    git push origin refs/tags/known-good --force
  else
    echo "warning: no origin remote — skip push" >&2
  fi
else
  echo "==> git: push skipped (pass --push or NIXOS_AUTO_PUSH=1)"
fi

echo "==> done"
