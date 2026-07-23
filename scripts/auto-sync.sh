#!/usr/bin/env bash
# Periodic job:
#   1) update fast-moving agents (herdr flake input + pi npm) when enabled
#   2) rebuild + commit + push known-good
#
# Invoked by systemd timer nixos-wsl-auto-sync.timer
set -euo pipefail

REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
ONLY_DIRTY="${NIXOS_AUTO_SYNC_ONLY_DIRTY:-0}"
UPDATE_FLAKE="${NIXOS_AUTO_SYNC_UPDATE_FLAKE:-0}"
UPDATE_AGENTS="${NIXOS_AUTO_SYNC_UPDATE_AGENTS:-1}"
LOG_TAG="nixos-wsl-auto-sync"

log() { echo "[$LOG_TAG] $*"; }

cd "$REPO"
export NIXOS_FLAKE="$REPO"
export NIXOS_AUTO_PUSH="${NIXOS_AUTO_PUSH:-1}"
export NIXOS_AUTO_COMMIT="${NIXOS_AUTO_COMMIT:-1}"
export GIT_TERMINAL_PROMPT=0

if [[ ! -f flake.nix ]]; then
  log "error: no flake at $REPO"
  exit 1
fi

if command -v gh >/dev/null 2>&1; then
  gh auth setup-git >/dev/null 2>&1 || true
fi

dirty=0
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  dirty=1
fi

ahead=0
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
else
  ahead=1
fi

log "repo=$REPO dirty=$dirty ahead=$ahead only_dirty=$ONLY_DIRTY update_flake=$UPDATE_FLAKE update_agents=$UPDATE_AGENTS"

# Full flake update (nixpkgs etc.) — off by default
if [[ "$UPDATE_FLAKE" == "1" ]]; then
  log "nix flake update (all inputs)"
  nix flake update
  dirty=1
fi

# 1) Pull live pi settings (install/remove writes) into the repo file first.
if [[ -x "$REPO/scripts/sync-pi-config.sh" ]]; then
  log "capturing live pi settings/extensions list"
  "$REPO/scripts/sync-pi-config.sh" || log "warning: sync-pi-config (copy) failed"
fi

# 2) herdr + pi binary + reconcile extensions to settings.packages
if [[ "$UPDATE_AGENTS" == "1" ]]; then
  log "updating agents (herdr + pi + extensions)"
  "$REPO/scripts/update-agents.sh" || log "warning: update-agents.sh failed (continuing)"
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    dirty=1
  fi
fi

# 3) Commit+push settings so install/uninstall reaches origin without waiting on rebuild.
if [[ -x "$REPO/scripts/sync-pi-config.sh" ]]; then
  log "committing pi settings/extensions list"
  "$REPO/scripts/sync-pi-config.sh" --commit --push || log "warning: sync-pi-config (commit) failed (continuing)"
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    dirty=1
  fi
  if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  fi
fi

if [[ "$ONLY_DIRTY" == "1" && "$dirty" == "0" && "$ahead" == "0" ]]; then
  log "clean and synced with origin — nothing to do"
  exit 0
fi

if [[ "$ONLY_DIRTY" == "1" && "$dirty" == "0" && "$ahead" != "0" ]]; then
  log "local commits not on origin — push only"
  branch="$(git branch --show-current)"
  git push -u origin "$branch"
  git push origin refs/tags/known-good --force 2>/dev/null || true
  log "push done"
  exit 0
fi

# Settings-only dirt: already committed+pushed above. If nothing else is dirty and
# onlyWhenDirty, skip the heavy rebuild this tick.
if [[ "$ONLY_DIRTY" == "1" ]]; then
  # ignore untracked noise; look at tracked/staged changes excluding nothing critical
  non_pi_dirty="$(git status --porcelain 2>/dev/null | awk '!($2 ~ /^home\/pi\//){print}' || true)"
  if [[ -z "$non_pi_dirty" && "$ahead" == "0" ]]; then
    log "only pi settings changed (already synced) — skip rebuild"
    exit 0
  fi
fi

log "running rebuild.sh switch"
exec "$REPO/scripts/rebuild.sh" switch
