#!/usr/bin/env bash
# Impermanence mindset: prove you can wipe and return.
# Does NOT wipe anything — audits non-declarative state + prints a drill plan.
#
# Usage:  ndrill   or   ./scripts/restore-drill.sh
set -euo pipefail

REPO="${NIXOS_FLAKE:-$HOME/nixos-wsl}"
ok=0
warn=0
fail=0

pass() { printf '  [OK]   %s\n' "$*"; ok=$((ok + 1)); }
soft() { printf '  [WARN] %s\n' "$*"; warn=$((warn + 1)); }
bad()  { printf '  [FAIL] %s\n' "$*"; fail=$((fail + 1)); }

echo "════════════════════════════════════════════════════"
echo " restore drill (read-only audit)"
echo "════════════════════════════════════════════════════"
echo

echo "1) Declarative core"
[[ -f "$REPO/flake.nix" ]] && pass "flake at $REPO" || bad "missing flake"
[[ -f "$REPO/flake.lock" ]] && pass "flake.lock present" || bad "missing flake.lock"
git -C "$REPO" rev-parse build-verified >/dev/null 2>&1 && pass "build-verified tag exists (not proof of restore)" || soft "no verified build tag"
git -C "$REPO" status --porcelain | grep -q . && soft "git tree dirty — commit before a real drill" || pass "git tree clean"
command -v nixos-rebuild >/dev/null && pass "nixos-rebuild available" || bad "no nixos-rebuild"

echo
echo "2) Secrets (sops / age) — NOT in git"
if [[ -r "$HOME/.config/sops/age/keys.txt" ]]; then
  pass "age key at ~/.config/sops/age/keys.txt"
  if command -v sops >/dev/null && [[ -f "$REPO/secrets/secrets.yaml" ]]; then
    if sops -d "$REPO/secrets/secrets.yaml" >/dev/null 2>&1; then
      pass "can decrypt secrets/secrets.yaml"
    else
      bad "cannot decrypt secrets.yaml with this age key"
    fi
  fi
else
  bad "missing age key — new machine cannot decrypt secrets"
  echo "         restore from password manager → ~/.config/sops/age/keys.txt"
fi

echo
echo "3) Human / mutable state (must re-do after wipe)"
command -v gh >/dev/null && gh auth status >/dev/null 2>&1 && pass "gh authenticated" || soft "gh not authed (gh auth login)"
git config --global user.name >/dev/null 2>&1 && pass "git user.name set" || soft "git user.name missing"
git config --global user.email >/dev/null 2>&1 && pass "git user.email set" || soft "git user.email missing"
command -v rustup >/dev/null && rustup show active-toolchain >/dev/null 2>&1 && pass "rustup toolchain active" || soft "rustup default stable not set"
command -v pi >/dev/null && pass "pi on PATH ($(pi --version 2>/dev/null | head -1))" || soft "pi missing (nup-agents)"
command -v herdr >/dev/null && pass "herdr on PATH" || soft "herdr missing (nrs after agents update)"
[[ -r /run/secrets/agent-env ]] && pass "agent-env present (/run/secrets)" || soft "no agent-env yet (edit: sops secrets/secrets.yaml)"
[[ -d "$HOME/.ssh" ]] && pass "~/.ssh exists" || soft "no ~/.ssh"
systemctl is-active nixos-wsl-auto-sync.timer >/dev/null 2>&1 && pass "auto-sync timer active" || soft "auto-sync timer inactive"

echo
echo "4) Backup path"
if systemctl cat nixos-wsl-notify-failure.service >/dev/null 2>&1; then
  pass "failure notify unit installed"
else
  soft "notify unit not installed (nrs?)"
fi
if [[ -f "$HOME/.local/state/nixos-wsl/last-sync-failure" ]]; then
  soft "last failure stamp: $(cat "$HOME/.local/state/nixos-wsl/last-sync-failure")"
else
  pass "no recorded sync failure stamp"
fi

echo
echo "════════════════════════════════════════════════════"
echo " Score: ok=$ok  warn=$warn  fail=$fail"
echo "════════════════════════════════════════════════════"
echo
cat <<'PLAN'
This command is a read-only readiness audit, not a completed restore drill.
For a real fresh-distro test, use scripts/restore-drill.ps1 with a recorded
NixOS-WSL image hash and an explicit Git revision. It refuses an existing distro,
never unregisters one, and leaves the new test distro for inspection.
See docs/RESTORE_EVIDENCE.md for procedure and required evidence.
PLAN

exit "$fail"
