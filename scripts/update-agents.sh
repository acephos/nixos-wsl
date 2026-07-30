#!/usr/bin/env bash
# Keep fast-moving agent tools on latest:
#   - herdr → nix flake input (system package)
#   - hunk  → nix flake input (system package)
#   - pi    → npm global @earendil-works/pi-coding-agent (user ~/.local)
#   - omp   → bun global @oh-my-pi/pi-coding-agent (user ~/.bun)
#
# Writes agents.lock.json so the repo records what this machine last resolved.
# Does NOT bump nixpkgs / nixos-wsl / home-manager / sops-nix.
#
# Usage:
#   ./scripts/update-agents.sh
#   ./scripts/update-agents.sh --herdr-only | --hunk-only | --pi-only | --omp-only
#   ./scripts/update-agents.sh --flake-only   # herdr+hunk, skip npm/bun
set -euo pipefail

REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
DO_HERDR=1
DO_HUNK=1
DO_PI=1
DO_OMP=1
PI_PKG="${NIXOS_PI_PACKAGE:-@earendil-works/pi-coding-agent}"
OMP_PKG="${NIXOS_OMP_PACKAGE:-@oh-my-pi/pi-coding-agent}"
LOG_TAG="update-agents"

log() { echo "[$LOG_TAG] $*"; }
die() { echo "[$LOG_TAG] error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --herdr-only) DO_HUNK=0; DO_PI=0; DO_OMP=0; shift ;;
    --hunk-only) DO_HERDR=0; DO_PI=0; DO_OMP=0; shift ;;
    --pi-only) DO_HERDR=0; DO_HUNK=0; DO_OMP=0; shift ;;
    --omp-only) DO_HERDR=0; DO_HUNK=0; DO_PI=0; shift ;;
    --flake-only) DO_PI=0; DO_OMP=0; shift ;;
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
omp_ver=""

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
# pi extensions: settings.packages is desired state (install + uninstall)
# ---------------------------------------------------------------------------
# settings.json packages[]  →  what should be installed
# ~/.pi/agent/npm/package.json dependencies  →  what is on disk
# reconcile both directions so pi install/remove (or hand-edits) converge.
reconcile_pi_packages() {
  command -v pi >/dev/null 2>&1 || { log "pi not on PATH — skip packages"; return 0; }
  command -v jq >/dev/null 2>&1 || { log "jq missing — skip pi packages"; return 0; }

  local settings=""
  if [[ -f "$HOME/.pi/agent/settings.json" || -L "$HOME/.pi/agent/settings.json" ]]; then
    settings="$HOME/.pi/agent/settings.json"
  elif [[ -f "$REPO/home/pi/settings.json" ]]; then
    mkdir -p "$HOME/.pi/agent"
    settings="$REPO/home/pi/settings.json"
    if [[ ! -e "$HOME/.pi/agent/settings.json" ]]; then
      ln -sfn "$settings" "$HOME/.pi/agent/settings.json"
      log "linked $HOME/.pi/agent/settings.json → $settings"
    fi
  else
    log "no pi settings.json — skip packages"
    return 0
  fi

  # Desired sources exactly as settings lists them (npm:@scope/pkg, git:..., etc.)
  local desired_file installed_file
  desired_file="$(mktemp)"
  installed_file="$(mktemp)"

  jq -r '.packages[]? // empty' "$settings" | sed '/^$/d' | sort -u >"$desired_file"

  # On-disk npm extension roots (direct deps only — not transitive)
  local npm_pkg="$HOME/.pi/agent/npm/package.json"
  if [[ -f "$npm_pkg" ]]; then
    jq -r '(.dependencies // {}) | keys[]' "$npm_pkg" 2>/dev/null \
      | sed 's|^|npm:|' | sort -u >"$installed_file"
  else
    : >"$installed_file"
  fi

  local pkg add=0 add_fail=0 del=0 del_fail=0

  # Install: in settings, missing or stale on disk
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    if pi install "$pkg" --no-approve >/dev/null 2>&1 || pi install "$pkg" >/dev/null 2>&1; then
      add=$((add + 1))
    else
      log "warn: pi install failed: $pkg"
      add_fail=$((add_fail + 1))
    fi
  done <"$desired_file"

  # Uninstall: on disk as npm dep but not named in settings.packages
  # Match npm:name against desired entries (exact source string or npm:name).
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    if grep -Fxq "$pkg" "$desired_file"; then
      continue
    fi
    # also allow desired entry without distinguishing npm: prefix variants
    if grep -Fxq "${pkg#npm:}" "$desired_file"; then
      continue
    fi
    if pi remove "$pkg" --no-approve >/dev/null 2>&1 || pi remove "$pkg" >/dev/null 2>&1; then
      log "removed unlisted extension: $pkg"
      del=$((del + 1))
    else
      log "warn: pi remove failed: $pkg"
      del_fail=$((del_fail + 1))
    fi
  done <"$installed_file"

  log "pi extensions reconcile: desired=$(wc -l <"$desired_file") installed_ok=$add install_fail=$add_fail removed=$del remove_fail=$del_fail"
  rm -f "$desired_file" "$installed_file"

  if pi update --extensions >/dev/null 2>&1; then
    log "pi extensions updated"
  else
    log "pi update --extensions skipped/failed (non-fatal)"
  fi
}

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

  # Install + uninstall to match settings.packages (home/pi/settings.json).
  reconcile_pi_packages

  # Re-apply local pi-web-access fix (upstream try/catch scope crash on WSL).
  if [[ -x "$REPO/scripts/patch-pi-web-access.sh" ]]; then
    "$REPO/scripts/patch-pi-web-access.sh" || log "warn: patch-pi-web-access failed"
  fi
fi

# ---------------------------------------------------------------------------
# omp — always latest from bun into ~/.bun
# ---------------------------------------------------------------------------
if [[ "$DO_OMP" -eq 1 ]]; then
  command -v bun >/dev/null 2>&1 || die "bun not found (bun should be in systemPackages)"

  bun_home="${BUN_INSTALL:-$HOME/.bun}"
  mkdir -p "$bun_home/bin" "$bun_home/install/global"
  case ":$PATH:" in
    *":$bun_home/bin:"*) ;;
    *) export PATH="$bun_home/bin:$PATH" ;;
  esac

  before_omp=""
  if command -v omp >/dev/null 2>&1; then
    before_omp="$(omp --version 2>/dev/null | head -1 || true)"
  fi

  log "bun add -g ${OMP_PKG}@latest  (BUN_INSTALL=$bun_home)"
  BUN_INSTALL="$bun_home" bun add -g "${OMP_PKG}@latest"

  bun_global_pkg="$bun_home/install/global/package.json"
  if [[ -f "$bun_global_pkg" ]] && command -v jq >/dev/null; then
    omp_ver="$(jq -r --arg p "$OMP_PKG" '.dependencies[$p] // empty' "$bun_global_pkg" 2>/dev/null || true)"
    omp_ver="${omp_ver#^}"
  fi
  if [[ -z "$omp_ver" ]] && command -v omp >/dev/null 2>&1; then
    omp_ver="$(omp --version 2>/dev/null | head -1 || true)"
    omp_ver="${omp_ver#omp/}"
  fi

  after_omp="$(command -v omp >/dev/null && omp --version 2>/dev/null | head -1 || true)"
  if [[ "$before_omp" != "$after_omp" ]]; then
    log "omp updated: ${before_omp:-none} → ${after_omp:-unknown}"
    changed=1
  else
    log "omp already latest (${after_omp:-unknown})"
  fi
fi

# ---------------------------------------------------------------------------
# agents.lock.json
# ---------------------------------------------------------------------------
lock_path="$REPO/agents.lock.json"
tmp="$(mktemp)"
existing_pi=""; existing_omp=""; existing_herdr=""; existing_hunk=""
if [[ -f "$lock_path" ]] && command -v jq >/dev/null; then
  existing_pi="$(jq -r '.pi // empty' "$lock_path" 2>/dev/null || true)"
  existing_omp="$(jq -r '.omp // empty' "$lock_path" 2>/dev/null || true)"
  existing_herdr="$(jq -r '.herdr // empty' "$lock_path" 2>/dev/null || true)"
  existing_hunk="$(jq -r '.hunk // empty' "$lock_path" 2>/dev/null || true)"
fi
[[ -n "$pi_ver" ]] || pi_ver="$existing_pi"
[[ -n "$omp_ver" ]] || omp_ver="$existing_omp"
[[ -n "$herdr_rev" ]] || herdr_rev="$existing_herdr"
[[ -n "$hunk_rev" ]] || hunk_rev="$existing_hunk"

if command -v jq >/dev/null; then
  jq -n \
    --arg pi "${pi_ver}" \
    --arg omp "${omp_ver}" \
    --arg herdr "${herdr_rev}" \
    --arg hunk "${hunk_rev}" \
    --arg piPkg "$PI_PKG" \
    --arg ompPkg "$OMP_PKG" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg host "$(hostname 2>/dev/null || echo unknown)" \
    '{
      pi: $pi,
      piPackage: $piPkg,
      omp: $omp,
      ompPackage: $ompPkg,
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
  "omp": "${omp_ver}",
  "ompPackage": "${OMP_PKG}",
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

log "done changed=$changed pi=${pi_ver:-?} omp=${omp_ver:-?} herdr=${herdr_rev:-?} hunk=${hunk_rev:-?}"
echo "$changed" >"$REPO/.agents-changed"
exit 0
