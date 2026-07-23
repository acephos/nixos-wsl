#!/usr/bin/env bash
# Keep fast-moving agent tools on latest:
#   - herdr  → nix flake input (system package)
#   - pi     → npm global @earendil-works/pi-coding-agent (user ~/.local)
#
# Writes agents.lock.json so the repo records what this machine last resolved.
# Does NOT bump nixpkgs / nixos-wsl.
#
# Usage:
#   ./scripts/update-agents.sh
#   ./scripts/update-agents.sh --herdr-only | --pi-only
set -euo pipefail

REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
DO_HERDR=1
DO_PI=1
PI_PKG="${NIXOS_PI_PACKAGE:-@earendil-works/pi-coding-agent}"
LOG_TAG="update-agents"

log() { echo "[$LOG_TAG] $*"; }
die() { echo "[$LOG_TAG] error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --herdr-only) DO_PI=0; shift ;;
    --pi-only) DO_HERDR=0; shift ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

cd "$REPO"
[[ -f flake.nix ]] || die "no flake at $REPO"

changed=0
herdr_rev=""
pi_ver=""

# ---------------------------------------------------------------------------
# herdr — flake input only (leave nixpkgs pinned)
# ---------------------------------------------------------------------------
if [[ "$DO_HERDR" -eq 1 ]]; then
  before="$(git -C "$REPO" hash-object flake.lock 2>/dev/null || echo none)"
  log "nix flake update herdr"
  nix flake update herdr
  after="$(git -C "$REPO" hash-object flake.lock 2>/dev/null || echo none)"
  if [[ "$before" != "$after" ]]; then
    log "herdr lock changed"
    changed=1
  else
    log "herdr already latest in lock"
  fi
  # Best-effort rev from lock
  herdr_rev="$(
    nix flake metadata "$REPO" --json 2>/dev/null \
      | jq -r '.locks.nodes.herdr.locked.rev // empty' 2>/dev/null \
      || true
  )"
  if [[ -z "$herdr_rev" ]] && command -v jq >/dev/null; then
    herdr_rev="$(jq -r '.nodes.herdr.locked.rev // empty' flake.lock 2>/dev/null || true)"
  fi
fi

# ---------------------------------------------------------------------------
# pi — always latest from npm into ~/.local (matches upstream's install path)
# ---------------------------------------------------------------------------
if [[ "$DO_PI" -eq 1 ]]; then
  command -v npm >/dev/null 2>&1 || die "npm not found (nodejs should be in systemPackages)"
  export npm_config_prefix="${npm_config_prefix:-$HOME/.local}"
  mkdir -p "$npm_config_prefix/bin" "$npm_config_prefix/lib"

  # Ensure ~/.npmrc prefix (idempotent)
  npmrc="$HOME/.npmrc"
  if [[ ! -f "$npmrc" ]] || ! grep -q '^prefix=' "$npmrc" 2>/dev/null; then
    echo "prefix=$npm_config_prefix" >>"$npmrc"
  fi

  before_pi=""
  if command -v pi >/dev/null 2>&1; then
    before_pi="$(pi --version 2>/dev/null | head -1 || true)"
  fi

  log "npm install -g ${PI_PKG}@latest  (prefix=$npm_config_prefix)"
  npm install -g "${PI_PKG}@latest" --no-fund --no-audit

  pi_ver="$(npm list -g --depth=0 --prefix "$npm_config_prefix" --json 2>/dev/null \
    | jq -r --arg p "$PI_PKG" '.dependencies[$p].version // empty' 2>/dev/null || true)"
  if [[ -z "$pi_ver" ]] && command -v pi >/dev/null 2>&1; then
    pi_ver="$(pi --version 2>/dev/null | head -1 || true)"
  fi

  after_pi="$(command -v pi >/dev/null && pi --version 2>/dev/null | head -1 || true)"
  if [[ "$before_pi" != "$after_pi" ]]; then
    log "pi updated: ${before_pi:-none} → ${after_pi:-unknown}"
    changed=1
  else
    log "pi already latest (${after_pi:-unknown})"
  fi

  # PATH hint for non-login contexts
  case ":$PATH:" in
    *":$npm_config_prefix/bin:"*) ;;
    *) export PATH="$npm_config_prefix/bin:$PATH" ;;
  esac
fi

# ---------------------------------------------------------------------------
# agents.lock.json — record resolved versions (committed by rebuild/auto-sync)
# ---------------------------------------------------------------------------
lock_path="$REPO/agents.lock.json"
tmp="$(mktemp)"
# merge with existing if partial update
existing_pi=""; existing_herdr=""
if [[ -f "$lock_path" ]] && command -v jq >/dev/null; then
  existing_pi="$(jq -r '.pi // empty' "$lock_path" 2>/dev/null || true)"
  existing_herdr="$(jq -r '.herdr // empty' "$lock_path" 2>/dev/null || true)"
fi
[[ -n "$pi_ver" ]] || pi_ver="$existing_pi"
[[ -n "$herdr_rev" ]] || herdr_rev="$existing_herdr"

if command -v jq >/dev/null; then
  jq -n \
    --arg pi "${pi_ver}" \
    --arg herdr "${herdr_rev}" \
    --arg piPkg "$PI_PKG" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg host "$(hostname 2>/dev/null || echo unknown)" \
    '{
      pi: $pi,
      piPackage: $piPkg,
      herdr: $herdr,
      herdrInput: "github:ogulcancelik/herdr",
      updatedAt: $updated,
      updatedOn: $host
    }' >"$tmp"
else
  cat >"$tmp" <<EOF
{
  "pi": "${pi_ver}",
  "piPackage": "${PI_PKG}",
  "herdr": "${herdr_rev}",
  "herdrInput": "github:ogulcancelik/herdr",
  "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "updatedOn": "$(hostname 2>/dev/null || echo unknown)"
}
EOF
fi

if [[ ! -f "$lock_path" ]] || ! cmp -s "$tmp" "$lock_path"; then
  mv "$tmp" "$lock_path"
  log "wrote $lock_path"
  changed=1
else
  rm -f "$tmp"
fi

log "done changed=$changed pi=${pi_ver:-?} herdr=${herdr_rev:-?}"
# exit 0 always; print changed on fd3 style via file for callers
echo "$changed" >"$REPO/.agents-changed"
exit 0
