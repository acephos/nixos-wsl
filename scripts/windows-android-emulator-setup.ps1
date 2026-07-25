# Setup Android SDK + emulator on Windows (run under Windows PowerShell).
# Usage (from WSL):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\wsl$\NixOS\home\acephos\nixos-wsl\scripts\windows-android-emulator-setup.ps1
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$SdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$JdkRoot = Join-Path $env:LOCALAPPDATA "Android\jdk-17"
$CmdToolsZip = Join-Path $env:TEMP "android-cmdline-tools.zip"
$CmdToolsUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
$AvdName = "ImOkMaa_API35"
$SysImage = "system-images;android-35;google_apis;x86_64"

function Ensure-Dir($p) {
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

Write-Host "== Windows Android emulator setup =="
Write-Host "SDK: $SdkRoot"

# --- JDK 17 (portable Temurin) ---
$java = Get-Command java -EA SilentlyContinue
if (-not $java) {
  $jdkOk = Test-Path (Join-Path $JdkRoot "bin\java.exe")
  if (-not $jdkOk) {
    Write-Host "Installing portable Temurin 17..."
    $jdkZip = Join-Path $env:TEMP "temurin17.zip"
    # Adoptium API latest GA 17 windows x64 jdk
    $api = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
    Invoke-WebRequest -Uri $api -OutFile $jdkZip
    $extract = Join-Path $env:TEMP "temurin17-extract"
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -Path $jdkZip -DestinationPath $extract -Force
    $inner = Get-ChildItem $extract | Select-Object -First 1
    if (Test-Path $JdkRoot) { Remove-Item $JdkRoot -Recurse -Force }
    Move-Item $inner.FullName $JdkRoot
  }
  $env:JAVA_HOME = $JdkRoot
  $env:Path = "$JdkRoot\bin;" + $env:Path
} else {
  Write-Host "Using existing java: $($java.Source)"
}

& java -version 2>&1 | Write-Host

# --- cmdline-tools ---
Ensure-Dir $SdkRoot
$sdkmanager = Join-Path $SdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkmanager)) {
  Write-Host "Downloading Android cmdline-tools..."
  Invoke-WebRequest -Uri $CmdToolsUrl -OutFile $CmdToolsZip
  $tmp = Join-Path $env:TEMP "android-cmdline-extract"
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Expand-Archive -Path $CmdToolsZip -DestinationPath $tmp -Force
  Ensure-Dir (Join-Path $SdkRoot "cmdline-tools\latest")
  Copy-Item -Path (Join-Path $tmp "cmdline-tools\*") -Destination (Join-Path $SdkRoot "cmdline-tools\latest") -Recurse -Force
}

$env:ANDROID_HOME = $SdkRoot
$env:ANDROID_SDK_ROOT = $SdkRoot
$env:Path = "$SdkRoot\cmdline-tools\latest\bin;$SdkRoot\platform-tools;$SdkRoot\emulator;" + $env:Path

Write-Host "Accepting licenses + installing packages (this is large)..."
$packages = @(
  "platform-tools",
  "platforms;android-35",
  "build-tools;35.0.0",
  "emulator",
  $SysImage
)

# yes | sdkmanager
$yes = "y`n" * 200
$packages | ForEach-Object { Write-Host "  -> $_" }
$argList = @("--sdk_root=$SdkRoot") + $packages
$p = Start-Process -FilePath $sdkmanager -ArgumentList $argList -NoNewWindow -PassThru -RedirectStandardInput "CONIN$" -Wait
# Fallback pipe method
cmd /c "echo y| `"$sdkmanager`" --sdk_root=$SdkRoot --licenses" | Out-Null
cmd /c "echo y| `"$sdkmanager`" --sdk_root=$SdkRoot $($packages -join ' ')"

$emulator = Join-Path $SdkRoot "emulator\emulator.exe"
$avdmanager = Join-Path $SdkRoot "cmdline-tools\latest\bin\avdmanager.bat"
if (-not (Test-Path $emulator)) { throw "emulator.exe missing — sdkmanager install failed" }

# Create AVD if missing
$avdDir = Join-Path $env:USERPROFILE ".android\avd\$AvdName.avd"
if (-not (Test-Path $avdDir)) {
  Write-Host "Creating AVD $AvdName..."
  # echo no = don't create custom hardware profile
  cmd /c "echo no| `"$avdmanager`" create avd -n $AvdName -k `"$SysImage`" -d pixel_6 --force"
}

# Persist env for user (session + machine-user env)
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $SdkRoot, "User")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $SdkRoot, "User")
[Environment]::SetEnvironmentVariable("JAVA_HOME", $env:JAVA_HOME, "User")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$add = @(
  "$SdkRoot\platform-tools",
  "$SdkRoot\emulator",
  "$SdkRoot\cmdline-tools\latest\bin"
)
foreach ($a in $add) {
  if ($userPath -notlike "*$a*") { $userPath = "$a;$userPath" }
}
[Environment]::SetEnvironmentVariable("Path", $userPath, "User")

Write-Host ""
Write-Host "SDK ready."
Write-Host "Start emulator:  $emulator -avd $AvdName -netdelay none -netspeed full"
Write-Host "AVD name:        $AvdName"
