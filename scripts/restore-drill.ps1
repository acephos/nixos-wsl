#Requires -Version 5.1
<# Fresh-distro restore evidence. Never unregisters or changes the default distro. #>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Archive,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ArchiveSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{40}$')][string]$Revision,
  [ValidatePattern('^NixOS-drill-[a-zA-Z0-9-]+$')][string]$DistroName = "NixOS-drill-$([guid]::NewGuid().ToString('N'))",
  [string]$InstallDir,
  [string]$EvidencePath = "restore-evidence.json"
)
$ErrorActionPreference = 'Stop'
if (Test-Path $EvidencePath) { throw 'Evidence destination already exists' }
if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) { throw 'Image archive is missing' }
if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLower() -ne $ArchiveSha256.ToLower()) { throw 'Image hash mismatch' }
$existing = @(& wsl.exe --list --quiet | ForEach-Object { ($_ -replace "`0", '').Trim() })
if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate WSL distributions' }
if ($existing -contains $DistroName) { throw 'Refusing to modify an existing distribution' }
if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA $DistroName }
if (Test-Path -LiteralPath $InstallDir) { throw 'Installation path already exists' }
$started = [DateTime]::UtcNow
$record = @{ started_at=$started.ToString('o'); revision=$Revision; image_sha256=$ArchiveSha256.ToLower(); distro=$DistroName; status='failed'; elapsed_seconds=$null; limitation='No secrets, OAuth state, SSH keys or project data are restored by this drill.' }
try {
  & wsl.exe --import $DistroName $InstallDir $Archive --version 2
  if ($LASTEXITCODE -ne 0) { throw 'Fresh WSL import failed' }
  # Explicit immutable revision; bootstrap uses locked agent versions.
  $command = "set -euo pipefail; nix-shell -p git curl --run 'git clone https://github.com/acephos/nixos-wsl.git /tmp/nixos-drill-source && cd /tmp/nixos-drill-source && git checkout --detach $Revision && bash scripts/bootstrap.sh --ref $Revision --no-push'"
  & wsl.exe -d $DistroName -- bash -lc $command
  if ($LASTEXITCODE -ne 0) { throw 'Bootstrap failed; inspect the retained test distribution' }
  $closure = & wsl.exe -d $DistroName -- readlink -f /run/current-system
  if ($LASTEXITCODE -ne 0 -or ($closure -join '') -notmatch '^/nix/store/') { throw 'Active closure could not be recorded' }
  $record.closure = ($closure -join '').Trim()
  $record.status = 'core-restored'
} finally {
  $record.finished_at = [DateTime]::UtcNow.ToString('o')
  $record.elapsed_seconds = [math]::Round(([DateTime]::UtcNow - $started).TotalSeconds, 3)
  $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
  Write-Host "Evidence written to $EvidencePath; '$DistroName' remains available for inspection."
}
