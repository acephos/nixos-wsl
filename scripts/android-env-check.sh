#!/usr/bin/env bash
# Print Android/Java readiness. Exit 1 if build-critical pieces missing.
set -euo pipefail
ok=1
check() {
  local label="$1"; shift
  if "$@"; then
    printf '  OK  %s\n' "$label"
  else
    printf '  BAD %s\n' "$label"
    ok=0
  fi
}

echo "╔══════════════════════════════════╗"
echo "║  Android dev environment check   ║"
echo "╚══════════════════════════════════╝"
echo
echo "JAVA_HOME=${JAVA_HOME:-<unset>}"
echo "ANDROID_HOME=${ANDROID_HOME:-<unset>}"
echo "ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-<unset>}"
echo
check "java on PATH" bash -lc 'command -v java >/dev/null'
check "java 17+" bash -lc 'java -version 2>&1 | head -1 | grep -Eq "version \"(17|1[89]|2[0-9])"'
check "adb on PATH" bash -lc 'command -v adb >/dev/null'
check "ANDROID_HOME dir" bash -lc '[[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME" ]]'
check "platform android-35" bash -lc '[[ -d "${ANDROID_HOME:-}/platforms/android-35" ]]'
check "build-tools" bash -lc 'ls -d "${ANDROID_HOME:-}/build-tools"/* >/dev/null 2>&1'
check "sdkmanager" bash -lc '[[ -x "${ANDROID_HOME:-}/cmdline-tools/latest/bin/sdkmanager" ]] || command -v sdkmanager >/dev/null'
check "gradle or gradlew" bash -lc 'command -v gradle >/dev/null || [[ -f "$HOME/im-ok-maa/gradlew" ]]'

echo
if command -v adb >/dev/null; then
  echo "--- adb devices ---"
  adb devices -l || true
fi
echo
if [[ "$ok" -eq 1 ]]; then
  echo "ENV OK — build with: cd ~/im-ok-maa && ./gradlew :app:assembleDebug"
  exit 0
fi
echo "ENV INCOMPLETE"
echo "  1) nrs                          # apply nixos android module"
echo "  2) ~/nixos-wsl/scripts/setup-android-sdk.sh"
echo "  3) exec zsh && android-env"
exit 1
