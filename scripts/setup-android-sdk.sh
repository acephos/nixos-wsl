#!/usr/bin/env bash
# Install a user-level Android SDK at ~/Android/Sdk (idempotent).
set -euo pipefail

SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
CMDTOOLS_ZIP_URL="${CMDTOOLS_ZIP_URL:-https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip}"
SEED_SDK="${SEED_SDK:-$HOME/im-ok-maa/.android-sdk}"

echo "== Android SDK setup =="
echo "Target: $SDK_ROOT"

mkdir -p "$SDK_ROOT"

# Fast path: reuse already-downloaded project SDK
if [[ ! -d "$SDK_ROOT/platforms/android-35" && -d "$SEED_SDK/platforms/android-35" ]]; then
  echo "Seeding from $SEED_SDK"
  cp -a "$SEED_SDK/." "$SDK_ROOT/"
fi

if [[ ! -x "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  echo "Installing cmdline-tools..."
  tmp="$(mktemp -d)"
  curl -fsSL "$CMDTOOLS_ZIP_URL" -o "$tmp/cmdtools.zip"
  unzip -q "$tmp/cmdtools.zip" -d "$tmp"
  mkdir -p "$SDK_ROOT/cmdline-tools/latest"
  # zip root is cmdline-tools/
  cp -a "$tmp/cmdline-tools/." "$SDK_ROOT/cmdline-tools/latest/" 2>/dev/null \
    || mv "$tmp/cmdline-tools"/* "$SDK_ROOT/cmdline-tools/latest/"
  rm -rf "$tmp"
fi

SM="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"
# Java required
if [[ -z "${JAVA_HOME:-}" ]] || [[ ! -x "${JAVA_HOME}/bin/java" ]]; then
  if command -v java >/dev/null 2>&1; then
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
    export JAVA_HOME
  else
    echo "JAVA_HOME not set and java not on PATH. Apply nixos android module first (nrs)."
    exit 1
  fi
fi

echo "JAVA_HOME=$JAVA_HOME"
yes 2>/dev/null | "$SM" --sdk_root="$SDK_ROOT" --licenses >/tmp/android-sdk-licenses.log 2>&1 || true

pkgs=(
  "platform-tools"
  "platforms;android-35"
  "build-tools;35.0.0"
  "cmdline-tools;latest"
)
# Optional emulator stack — large; skip by default on WSL (use Windows emulator / phone)
if [[ "${WITH_EMULATOR:-0}" == "1" ]]; then
  pkgs+=(
    "emulator"
    "system-images;android-35;google_apis;x86_64"
  )
fi

yes 2>/dev/null | "$SM" --sdk_root="$SDK_ROOT" "${pkgs[@]}" \
  >/tmp/android-sdk-install.log 2>&1 || true

if [[ ! -d "$SDK_ROOT/platforms/android-35" ]]; then
  echo "FAILED — see /tmp/android-sdk-install.log"
  tail -40 /tmp/android-sdk-install.log
  exit 1
fi

# Point common projects at this SDK
for proj in "$HOME/im-ok-maa"; do
  if [[ -d "$proj" ]]; then
    echo "sdk.dir=$SDK_ROOT" >"$proj/local.properties"
    echo "Wrote $proj/local.properties"
  fi
done

mkdir -p "$HOME/.android"
# avoid interactive adb key prompts weirdness
touch "$HOME/.android/repositories.cfg"

echo
echo "SDK ready: $SDK_ROOT"
echo "Add to shell (already in nixos module after nrs):"
echo "  export ANDROID_HOME=$SDK_ROOT"
"$SDK_ROOT/platform-tools/adb" version 2>/dev/null || adb version || true
echo "Done. Run: android-env"
