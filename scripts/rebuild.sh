#!/usr/bin/env bash
# Rebuild and tag only a successful, unchanged source revision with matching closure.
# Usage: rebuild.sh [switch|boot|test] [--push|--no-push] [--no-commit] [--] [extra args]
set -euo pipefail
REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
ACTION=switch
DO_PUSH="${NIXOS_AUTO_PUSH:-1}"
DO_COMMIT="${NIXOS_AUTO_COMMIT:-1}"
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    switch|boot|test) ACTION="$1"; shift ;;
    --push) DO_PUSH=1; shift ;;
    --no-push) DO_PUSH=0; shift ;;
    --no-commit) DO_COMMIT=0; shift ;;
    --) shift; EXTRA+=("$@"); break ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done
cd "$REPO"
[[ -f flake.nix ]] || { echo 'error: missing flake.nix' >&2; exit 1; }
# New files must already be staged for Git-backed flake evaluation to include them.
if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo 'error: stage intended new source files before rebuilding (git add <paths>).' >&2
  exit 1
fi
fingerprint() {
  # Includes tracked/staged changes and modes without displaying file contents.
  { git rev-parse HEAD; git diff --binary HEAD; git ls-files --stage; } | git hash-object --stdin
}
git add -u
build_tree="$(git write-tree)"
before="$(fingerprint)"
set +e
sudo nixos-rebuild "$ACTION" --flake "$REPO#nixos" "${EXTRA[@]}"
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "error: rebuild exited $rc; no success tag, commit or push (exit 4 also requires investigation)." >&2
  exit "$rc"
fi
[[ "$(fingerprint)" == "$before" ]] || { echo 'error: source changed during rebuild; no verification tag.' >&2; exit 1; }
closure="$(nix build "$REPO#nixos" --no-link --print-out-paths)"
[[ "$closure" == /nix/store/* && "$closure" != *$'\n'* ]] || { echo 'error: expected one system closure.' >&2; exit 1; }
[[ "$(fingerprint)" == "$before" ]] || { echo 'error: source changed during closure verification.' >&2; exit 1; }
case "$ACTION" in
  switch|test) target=/run/current-system ;;
  boot) target=/nix/var/nix/profiles/system ;;
esac
actual="$(readlink -f "$target")"
[[ "$actual" == "$closure" ]] || { echo 'error: activated/boot profile differs from built closure; no verification tag.' >&2; exit 1; }
if [[ "$ACTION" == test ]]; then
  echo "test activation verified: $closure (no commit/tag/push)"
  exit 0
fi
if [[ "$DO_COMMIT" == 1 ]]; then
  # Stage tracked changes only; caller explicitly stages new files before the build.
  git add -u
  if ! git diff --cached --quiet; then
    git commit -m "nixos: verified $ACTION build" -m "closure: $closure"
  fi
elif [[ -n "$(git status --porcelain)" ]]; then
  echo 'error: --no-commit with dirty source cannot identify a verified revision.' >&2
  exit 1
fi
# Final equality protects changes during the commit; HEAD now represents the built source.
[[ -z "$(git status --porcelain)" ]] || { echo 'error: source still dirty; no verification tag.' >&2; exit 1; }
[[ "$(git rev-parse HEAD^{tree})" == "$build_tree" ]] || { echo "error: committed tree differs from built source." >&2; exit 1; }
revision="$(git rev-parse HEAD)"
tag="build-verified-$(date -u +%Y%m%dT%H%M%SZ)-${revision:0:12}"
git tag -a "$tag" -m "closure=$closure action=$ACTION host=$(hostname) revision=$revision"
git tag -f -a build-verified -m "closure=$closure action=$ACTION receipt=$tag revision=$revision"
echo "verified build tag: $tag (build/activation proof; not a completed restore drill)"
if [[ "$DO_PUSH" == 1 ]] && git remote get-url origin >/dev/null 2>&1; then
  git push -u origin HEAD
  git push origin "refs/tags/$tag"
  git push origin refs/tags/build-verified --force
fi
