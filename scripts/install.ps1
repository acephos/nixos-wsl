#Requires -Version 5.1
<#
.SYNOPSIS
  Install WSL2 + NixOS-WSL, then bootstrap acephos/nixos-wsl at tag known-good.

.DESCRIPTION
  Run from elevated PowerShell on a fresh Windows machine:

    # download + run:
    irm https://raw.githubusercontent.com/acephos/nixos-wsl/main/scripts/install.ps1 | iex

    # or locally:
    .\scripts\install.ps1

.PARAMETER DistroName
  WSL distro name (default: NixOS)

.PARAMETER RepoUrl
  Git remote for the flake (default: acephos/nixos-wsl)

.PARAMETER Ref
  Git ref to install (default: known-good)

.PARAMETER SkipWslInstall
  Assume WSL is already installed

.PARAMETER SkipNixOS
  Assume NixOS-WSL distro already exists; only run bootstrap inside it
#>
[CmdletBinding()]
param(
  [string]$DistroName = "NixOS",
  [string]$RepoUrl = "https://github.com/acephos/nixos-wsl.git",
  [string]$Ref = "known-good",
  [string]$InstallDir = "$env:USERPROFILE\NixOS",
  [switch]$SkipWslInstall,
  [switch]$SkipNixOS
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "warning: $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "error: $msg" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Admin check
# ---------------------------------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Err "Re-run this script in an elevated (Administrator) PowerShell."
  exit 1
}

# ---------------------------------------------------------------------------
# WSL2
# ---------------------------------------------------------------------------
if (-not $SkipWslInstall) {
  Write-Step "Ensuring WSL2 is available"
  try {
    wsl --status 2>$null | Out-Null
  } catch { }

  # Best-effort feature enable (idempotent)
  & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
  & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null

  try {
    wsl --install --no-distribution --web-download
  } catch {
    Write-Warn "wsl --install returned an error (may already be installed): $_"
  }

  try { wsl --set-default-version 2 } catch { Write-Warn "could not set default WSL version to 2" }

  $wslOk = $false
  try {
    wsl --status 2>$null | Out-Null
    $wslOk = $true
  } catch { $wslOk = $false }

  if (-not $wslOk) {
    Write-Warn "WSL may need a reboot before continuing."
    Write-Host ""
    Write-Host "1. Reboot Windows" -ForegroundColor Yellow
    Write-Host "2. Re-run this script:  irm https://raw.githubusercontent.com/acephos/nixos-wsl/main/scripts/install.ps1 | iex" -ForegroundColor Yellow
    exit 2
  }
}

# ---------------------------------------------------------------------------
# NixOS-WSL base image
# ---------------------------------------------------------------------------
$distroExists = $false
try {
  $list = wsl -l -q 2>$null
  if ($list -match [regex]::Escape($DistroName)) { $distroExists = $true }
} catch { }

if (-not $SkipNixOS -and -not $distroExists) {
  Write-Step "Downloading latest NixOS-WSL release"
  $api = "https://api.github.com/repos/nix-community/NixOS-WSL/releases/latest"
  $headers = @{ "User-Agent" = "acephos-nixos-wsl-install" }
  $release = Invoke-RestMethod -Uri $api -Headers $headers

  $asset = $release.assets |
    Where-Object { $_.name -match '\.wsl$' -or $_.name -match 'nixos.*\.tar\.gz$' } |
    Select-Object -First 1

  if (-not $asset) {
    Write-Err "No .wsl / .tar.gz asset found on nix-community/NixOS-WSL latest release."
    Write-Host "Download manually from https://github.com/nix-community/NixOS-WSL/releases"
    exit 1
  }

  $tmp = Join-Path $env:TEMP $asset.name
  Write-Step "Fetching $($asset.name) ($([math]::Round($asset.size/1MB,1)) MB)"
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

  if ($asset.name -match '\.wsl$') {
    Write-Step "Installing NixOS-WSL from .wsl"
    # Newer WSL: --install --from-file
    try {
      wsl --install --from-file $tmp --name $DistroName --location $InstallDir
    } catch {
      Write-Warn "--install --from-file failed, trying wsl --import"
      wsl --import $DistroName $InstallDir $tmp --version 2
    }
  } else {
    Write-Step "Importing NixOS-WSL tarball as '$DistroName'"
    wsl --import $DistroName $InstallDir $tmp --version 2
  }

  Write-Step "Base image installed. First boot may prompt for a default user."
  Write-Host "If prompted inside WSL, create user 'acephos' (matches the flake) or edit flake.nix later." -ForegroundColor Yellow
} else {
  Write-Step "NixOS distro '$DistroName' already present — skipping image download"
}

try { wsl --set-default $DistroName } catch { }

# ---------------------------------------------------------------------------
# Bootstrap flake inside the distro (latest known-good)
# ---------------------------------------------------------------------------
Write-Step "Bootstrapping flake ($Ref) inside $DistroName"

$remoteBash = @"
set -euo pipefail
export NIXOS_BOOTSTRAP_REF='$Ref'
export NIXOS_BOOTSTRAP_REMOTE='$RepoUrl'
# bare images may lack curl; use nix-shell/git as needed
if command -v curl >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/acephos/nixos-wsl/main/scripts/bootstrap.sh | bash -s -- --ref '$Ref' --remote '$RepoUrl' --no-push
else
  # minimal fallback: get git, clone, run local bootstrap
  if ! command -v git >/dev/null 2>&1; then
    nix-env -iA nixos.git nixos.curl nixos.cacert 2>/dev/null || nix-env -iA nixpkgs.git nixpkgs.curl 2>/dev/null || true
  fi
  if [[ ! -d "\$HOME/nixos-wsl/.git" ]]; then
    git clone --depth 1 '$RepoUrl' "\$HOME/nixos-wsl" || git clone '$RepoUrl' "\$HOME/nixos-wsl"
  fi
  cd "\$HOME/nixos-wsl"
  git fetch --tags --force origin || true
  git checkout -f '$Ref' 2>/dev/null || git checkout -f known-good 2>/dev/null || git checkout -f main
  chmod +x scripts/*.sh
  ./scripts/bootstrap.sh --ref '$Ref' --remote '$RepoUrl' --no-push
fi
"@

# Write script into the distro and execute (avoids quoting hell)
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteBash))

wsl -d $DistroName --user root -- bash -lc "echo $b64 | base64 -d > /tmp/acephos-bootstrap.sh && chmod +x /tmp/acephos-bootstrap.sh"

# Prefer default non-root user; fall back to root then warn
$bootstrapExit = 0
try {
  wsl -d $DistroName -- bash /tmp/acephos-bootstrap.sh
  $bootstrapExit = $LASTEXITCODE
} catch {
  Write-Warn "bootstrap as default user failed, retrying..."
  wsl -d $DistroName --user root -- bash -lc "sudo -u \$(getent passwd | awk -F: '\$3>=1000 && \$3<65534 {print \$1; exit}') bash /tmp/acephos-bootstrap.sh"
  $bootstrapExit = $LASTEXITCODE
}

if ($bootstrapExit -ne 0) {
  Write-Err "Bootstrap inside WSL exited with code $bootstrapExit"
  Write-Host "Enter the distro and run manually:"
  Write-Host "  wsl -d $DistroName"
  Write-Host "  curl -fsSL https://raw.githubusercontent.com/acephos/nixos-wsl/main/scripts/bootstrap.sh | bash"
  exit $bootstrapExit
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Install finished" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Open:   wsl -d $DistroName"
Write-Host "Shell:  exec zsh"
Write-Host "Then:   gh auth login && rustup default stable && nrs"
Write-Host ""
