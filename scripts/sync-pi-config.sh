#!/usr/bin/env bash
# Mirror live pi agent settings + extension inventory into this repo.
#
# Source of truth for *which* extensions are installed/uninstalled:
#   home/pi/settings.json  →  key "packages"  (e.g. "npm:@foo/bar")
#
# Local flow:
#   pi install npm:@foo/bar  → adds to packages[] + installs under ~/.pi/agent/npm
#   pi remove  npm:@foo/bar  → drops from packages[] + uninstalls from npm
#   (settings path is normally an HM symlink into this repo file)
#
# This script does NOT vendor node_modules — only the declarative list + prefs.
# Disk is reconciled to that list by scripts/update-agents.sh (install + remove).
#
# Usage:
#   ./scripts/sync-pi-config.sh              # copy only
#   ./scripts/sync-pi-config.sh --commit     # copy + commit if dirty
#   ./scripts/sync-pi-config.sh --commit --push
set -euo pipefail

REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
LIVE="${PI_SETTINGS_LIVE:-$HOME/.pi/agent/settings.json}"
DEST="$REPO/home/pi/settings.json"
DO_COMMIT=0
DO_PUSH="${NIXOS_AUTO_PUSH:-0}"
LOG_TAG="sync-pi-config"

log() { echo "[$LOG_TAG] $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit) DO_COMMIT=1; shift ;;
    --push) DO_PUSH=1; shift ;;
    --no-push) DO_PUSH=0; shift ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "[$LOG_TAG] unknown arg: $1" >&2; exit 1 ;;
  esac
done

cd "$REPO"
[[ -f flake.nix ]] || { log "error: no flake at $REPO"; exit 1; }
mkdir -p "$(dirname "$DEST")"

changed=0

if [[ -e "$LIVE" || -L "$LIVE" ]]; then
  # Resolve through HM out-of-store symlink chain when present
  live_real="$(readlink -f "$LIVE" 2>/dev/null || true)"
  [[ -n "$live_real" && -f "$live_real" ]] || live_real="$LIVE"

  dest_real="$(readlink -f "$DEST" 2>/dev/null || echo "$DEST")"

  if [[ -f "$live_real" ]]; then
    if [[ "$live_real" == "$dest_real" ]]; then
      log "live settings already repo file ($DEST)"
    elif [[ -f "$DEST" ]] && cmp -s "$live_real" "$DEST"; then
      log "live settings content matches repo"
    else
      cp -f "$live_real" "$DEST"
      log "copied $live_real → $DEST"
      changed=1
    fi
  else
    log "live path missing content: $LIVE"
  fi
elif [[ -f "$DEST" ]]; then
  log "no live settings; repo copy kept ($DEST)"
else
  log "no pi settings found (live or repo) — nothing to do"
  exit 0
fi

# Sanity: must be JSON with optional packages array
if command -v jq >/dev/null 2>&1 && [[ -f "$DEST" ]]; then
  if ! jq -e . "$DEST" >/dev/null 2>&1; then
    log "error: $DEST is not valid JSON"
    exit 1
  fi
  pkg_count="$(jq -r '(.packages // []) | length' "$DEST")"
  log "packages listed: $pkg_count"
fi

if [[ "$DO_COMMIT" != "1" ]]; then
  exit 0
fi

if ! git config user.email >/dev/null 2>&1; then
  git config user.email "acephos@users.noreply.github.com"
  git config user.name "acephos"
fi

# Only stage pi config paths (never secrets / npm trees)
git add -- "home/pi/settings.json" 2>/dev/null || true

if git diff --cached --quiet -- "home/pi/settings.json"; then
  log "git: home/pi/settings.json clean — no commit"
else
  git commit -m "pi: sync settings" -m "host: $(hostname 2>/dev/null || echo unknown)"
  log "git: committed pi settings → $(git rev-parse --short HEAD)"
  changed=1
fi

if [[ "$DO_PUSH" == "1" ]]; then
  if git remote get-url origin >/dev/null 2>&1; then
    command -v gh >/dev/null 2>&1 && gh auth setup-git >/dev/null 2>&1 || true
    branch="$(git branch --show-current)"
    # push commits only; leave known-good tag to rebuild/checkpoint
    git push -u origin "$branch"
    log "git: pushed $branch"
  else
    log "warning: no origin — skip push"
  fi
fi

exit 0
