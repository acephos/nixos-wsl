#!/usr/bin/env bash
# Bootstrap acephos/nixos-wsl onto this machine at the latest known-good revision.
#
# One-liner (inside NixOS-WSL or any NixOS with network):
#   curl -fsSL https://raw.githubusercontent.com/acephos/nixos-wsl/main/scripts/bootstrap.sh | bash
#
# Options:
#   --ref REF          git ref to install (default: known-good, fallback: main)
#   --repo DIR         install path (default: ~/nixos-wsl)
#   --remote URL       git remote (default: https://github.com/acephos/nixos-wsl.git)
#   --push             allow git push after switch (default: off on first install)
#   --no-rebuild       clone/update only
#   --update-flake     run nix flake update before switch (not recommended)
set -euo pipefail

REMOTE="${NIXOS_BOOTSTRAP_REMOTE:-https://github.com/acephos/nixos-wsl.git}"
REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
REF="${NIXOS_BOOTSTRAP_REF:-known-good}"
DO_REBUILD=1
DO_PUSH=0
UPDATE_FLAKE=0
FLAKE_ATTR="${NIXOS_FLAKE_ATTR:-nixos}"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --remote) REMOTE="$2"; shift 2 ;;
    --push) DO_PUSH=1; shift ;;
    --no-push) DO_PUSH=0; shift ;;
    --no-rebuild) DO_REBUILD=0; shift ;;
    --update-flake) UPDATE_FLAKE=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown arg: $1" ;;
  esac
done

export NIXOS_FLAKE="$REPO"
export NIXOS_AUTO_PUSH="$DO_PUSH"
export NIXOS_AUTO_COMMIT=1
export GIT_TERMINAL_PROMPT=0

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
log "bootstrap acephos/nixos-wsl"
log "remote=$REMOTE  ref=$REF  repo=$REPO"

if [[ "$(id -u)" -eq 0 ]]; then
  die "run as the normal user (not root). sudo is used only where needed."
fi

if [[ ! -e /etc/NIXOS ]] && ! command -v nixos-rebuild >/dev/null 2>&1; then
  die "this does not look like NixOS. On Windows, run scripts/install.ps1 first."
fi

# Need nix + basic tools. Prefer system paths; fall back to nix-env on bare image.
need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_prereqs() {
  local missing=()
  need_cmd git || missing+=(git)
  need_cmd curl || missing+=(curl)
  need_cmd sudo || missing+=(sudo)

  if ((${#missing[@]})); then
    log "installing prerequisites: ${missing[*]}"
    if need_cmd nix-env; then
      # Channel-based bare NixOS-WSL image
      nix-env -iA nixos.git nixos.curl nixos.cacert 2>/dev/null \
        || nix-env -iA nixpkgs.git nixpkgs.curl nixpkgs.cacert 2>/dev/null \
        || true
    fi
  fi

  need_cmd git || die "git is required (sudo nix-env -iA nixos.git)"
  need_cmd curl || warn "curl missing — git clone still works"
  need_cmd sudo || die "sudo is required"

  # flakes + nix-command (no-op if already set via configuration)
  if need_cmd nix; then
    mkdir -p "$HOME/.config/nix"
    if [[ ! -f "$HOME/.config/nix/nix.conf" ]] || ! grep -q 'experimental-features' "$HOME/.config/nix/nix.conf" 2>/dev/null; then
      log "enabling nix flakes in ~/.config/nix/nix.conf"
      {
        echo "experimental-features = nix-command flakes"
      } >>"$HOME/.config/nix/nix.conf"
    fi
  fi
}

ensure_prereqs

# ---------------------------------------------------------------------------
# Fetch latest known-good
# ---------------------------------------------------------------------------
clone_or_update() {
  if [[ -d "$REPO/.git" ]]; then
    log "updating existing repo at $REPO"
    git -C "$REPO" remote set-url origin "$REMOTE" 2>/dev/null || git -C "$REPO" remote add origin "$REMOTE"
    git -C "$REPO" fetch --tags --force origin
  else
    log "cloning $REMOTE → $REPO"
    mkdir -p "$(dirname "$REPO")"
    # Prefer known-good; fall back to main if tag missing
    if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$REF" >/dev/null 2>&1; then
      git clone --depth 1 --branch "$REF" "$REMOTE" "$REPO" \
        || git clone "$REMOTE" "$REPO"
    else
      warn "tag/branch '$REF' not found on remote — using main"
      REF=main
      git clone --depth 1 --branch main "$REMOTE" "$REPO"
    fi
  fi

  cd "$REPO"

  # Resolve ref: tag known-good → main → HEAD
  if git rev-parse -q --verify "refs/tags/$REF" >/dev/null 2>&1; then
    log "checking out tag $REF ($(git rev-parse --short "$REF^{commit}"))"
    git checkout -f -B bootstrap "$REF"
  elif git rev-parse -q --verify "refs/remotes/origin/$REF" >/dev/null 2>&1; then
    log "checking out origin/$REF"
    git checkout -f -B bootstrap "origin/$REF"
  elif git rev-parse -q --verify "refs/remotes/origin/main" >/dev/null 2>&1; then
    warn "ref $REF missing locally — using origin/main"
    git checkout -f -B bootstrap origin/main
  else
    git fetch origin main --tags --force
    if git rev-parse -q --verify "refs/tags/known-good" >/dev/null 2>&1; then
      git checkout -f -B bootstrap known-good
    else
      git checkout -f -B bootstrap origin/main
    fi
  fi

  log "HEAD=$(git rev-parse --short HEAD)  $(git log -1 --pretty=format:'%s')"
}

clone_or_update

chmod +x "$REPO"/scripts/*.sh 2>/dev/null || true
if [[ -x "$REPO/scripts/install-hooks.sh" ]]; then
  log "installing git hooks"
  "$REPO/scripts/install-hooks.sh" || true
fi

if [[ "$DO_REBUILD" -eq 0 ]]; then
  log "skip rebuild (--no-rebuild). When ready:"
  log "  $REPO/scripts/rebuild.sh switch"
  exit 0
fi

if [[ "$UPDATE_FLAKE" -eq 1 ]]; then
  log "nix flake update (you asked for it)"
  nix flake update
fi

# ---------------------------------------------------------------------------
# Apply system
# ---------------------------------------------------------------------------
need_cmd nixos-rebuild || die "nixos-rebuild not found"

log "building + switching to flake $REPO#$FLAKE_ATTR"
log "(first run can take a while — nixpkgs download/build)"

if [[ -x "$REPO/scripts/rebuild.sh" ]]; then
  if [[ "$DO_PUSH" -eq 1 ]]; then
    "$REPO/scripts/rebuild.sh" switch --push
  else
    "$REPO/scripts/rebuild.sh" switch --no-push
  fi
else
  set +e
  sudo nixos-rebuild switch --flake "$REPO#$FLAKE_ATTR"
  rc=$?
  set -e
  if [[ $rc -ne 0 && $rc -ne 4 ]]; then
    die "nixos-rebuild failed (exit $rc)"
  fi
fi

# pi tracks npm latest (not a Nix package) — install after node is on PATH
if [[ -x "$REPO/scripts/update-agents.sh" ]]; then
  log "installing/updating agent CLIs (herdr via flake already; pi via npm)"
  # PATH may not have new system profile yet in this shell
  export PATH="/run/current-system/sw/bin:$HOME/.local/bin:$PATH"
  "$REPO/scripts/update-agents.sh" --pi-only || warn "pi install failed — run: nup-agents later"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<EOF

╔══════════════════════════════════════════════════════════════════╗
║  Bootstrap complete                                              ║
╠══════════════════════════════════════════════════════════════════╣
║  Config:   $REPO
║  Revision: $(git -C "$REPO" rev-parse --short HEAD) ($(git -C "$REPO" log -1 --pretty=format:%s))
║  System:   $(nixos-version 2>/dev/null || echo unknown)
║
║  Reload your shell:
║    exec zsh
║    # not: source ./zshrc
║
║  One-time human setup (not in the flake):
║    rustup default stable
║    git config --global user.name  "Your Name"
║    git config --global user.email "you@example.com"
║    gh auth login
║    gh auth setup-git
║    nrs                  # enable auto push after gh auth
║    # pi settings+extensions: home/pi/settings.json (via HM + nup-agents)
║
║  Timer status:
║    nsync-status
╚══════════════════════════════════════════════════════════════════╝
EOF
