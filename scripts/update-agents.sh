#!/usr/bin/env bash
# Keep fast-moving agent tools on latest:
#   - herdr  → nix flake input (system package)
#   - hunk   → nix flake input (system package)
#   - pi     → npm global @earendil-works/pi-coding-agent (user ~/.local)
#
# Writes agents.lock.json so the repo records what this machine last resolved.
# Does NOT bump nixpkgs / nixos-wsl / home-manager / sops-nix.
#
# Usage:
#   ./scripts/update-agents.sh
#   ./scripts/update-agents.sh --herdr-only | --hunk-only | --pi-only
#   ./scripts/update-agents.sh --flake-only   # herdr+hunk, skip npm
set -euo pipefail

REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
DO_HERDR=1
DO_HUNK=1
DO_PI=1
PI_PKG="${NIXOS_PI_PACKAGE:-@earendil-works/pi-coding-agent}"
LOG_TAG="update-agents"

log() { echo "[$LOG_TAG] $*"; }
die() { echo "[$LOG_TAG] error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --herdr-only) DO_HUNK=0; DO_PI=0; shift ;;
    --hunk-only) DO_HERDR=0; DO_PI=0; shift ;;
    --pi-only) DO_HERDR=0; DO_HUNK=0; shift ;;
    --flake-only) DO_PI=0; shift ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

cd "$REPO"
[[ -f flake.nix ]] || die "no flake at $REPO"

changed=0
herdr_rev=""
hunk_rev=""
pi_ver=""

lock_rev() {
  local input="$1"
  if command -v jq >/dev/null; then
    jq -r --arg i "$input" '.nodes[$i].locked.rev // empty' flake.lock 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Flake inputs: herdr + hunk (leave nixpkgs pinned)
# ---------------------------------------------------------------------------
update_flake_input() {
  local name="$1"
  local before after
  before="$(git -C "$REPO" hash-object flake.lock 2>/dev/null || echo none)"
  log "nix flake update $name"
  nix flake update "$name"
  after="$(git -C "$REPO" hash-object flake.lock 2>/dev/null || echo none)"
  if [[ "$before" != "$after" ]]; then
    log "$name lock changed"
    changed=1
  else
    log "$name already latest in lock"
  fi
}

if [[ "$DO_HERDR" -eq 1 ]]; then
  update_flake_input herdr
  herdr_rev="$(lock_rev herdr)"
fi

if [[ "$DO_HUNK" -eq 1 ]]; then
  update_flake_input hunk
  hunk_rev="$(lock_rev hunk)"
fi

# ---------------------------------------------------------------------------
# pi — always latest from npm into ~/.local
# ---------------------------------------------------------------------------
if [[ "$DO_PI" -eq 1 ]]; then
  command -v npm >/dev/null 2>&1 || die "npm not found (nodejs should be in systemPackages)"
  export npm_config_prefix="${npm_config_prefix:-$HOME/.local}"
  mkdir -p "$npm_config_prefix/bin" "$npm_config_prefix/lib"

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

  case ":$PATH:" in
    *":$npm_config_prefix/bin:"*) ;;
    *) export PATH="$npm_config_prefix/bin:$PATH" ;;
  esac
fi

# ---------------------------------------------------------------------------
# agents.lock.json
# ---------------------------------------------------------------------------
lock_path="$REPO/agents.lock.json"
tmp="$(mktemp)"
existing_pi=""; existing_herdr=""; existing_hunk=""
if [[ -f "$lock_path" ]] && command -v jq >/dev/null; then
  existing_pi="$(jq -r '.pi // empty' "$lock_path" 2>/dev/null || true)"
  existing_herdr="$(jq -r '.herdr // empty' "$lock_path" 2>/dev/null || true)"
  existing_hunk="$(jq -r '.hunk // empty' "$lock_path" 2>/dev/null || true)"
fi
[[ -n "$pi_ver" ]] || pi_ver="$existing_pi"
[[ -n "$herdr_rev" ]] || herdr_rev="$existing_herdr"
[[ -n "$hunk_rev" ]] || hunk_rev="$existing_hunk"

if command -v jq >/dev/null; then
  jq -n \
    --arg pi "${pi_ver}" \
    --arg herdr "${herdr_rev}" \
    --arg hunk "${hunk_rev}" \
    --arg piPkg "$PI_PKG" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg host "$(hostname 2>/dev/null || echo unknown)" \
    '{
      pi: $pi,
      piPackage: $piPkg,
      herdr: $herdr,
      herdrInput: "github:ogulcancelik/herdr",
      hunk: $hunk,
      hunkInput: "github:modem-dev/hunk",
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
  "hunk": "${hunk_rev}",
  "hunkInput": "github:modem-dev/hunk",
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

log "done changed=$changed pi=${pi_ver:-?} herdr=${herdr_rev:-?} hunk=${hunk_rev:-?}"
echo "$changed" >"$REPO/.agents-changed"
exit 0
