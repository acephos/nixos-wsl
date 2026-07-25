# Android CLI toolchain for WSL.
# SDK lives in $HOME/Android/Sdk (not the nix store) — run scripts/setup-android-sdk.sh once.
{
  pkgs,
  username,
  ...
}:
let
  home = "/home/${username}";
  sdk = "${home}/Android/Sdk";
  jdk = pkgs.temurin-bin-17;
in
{
  environment.systemPackages = with pkgs; [
    jdk
    android-tools # adb / fastboot (Nix-built, reliable on NixOS)
    gradle # bootstrap wrappers; projects pin their own via gradlew
    # handy for APK peek / signing checks
    apktool
  ];

  # Extra libs Google's sdkmanager / build-tools often need via nix-ld
  programs.nix-ld.libraries = with pkgs; [
    zlib
    ncurses
    libglvnd
    freetype
    fontconfig
    expat
  ];

  environment.variables = {
    JAVA_HOME = "${jdk}";
    ANDROID_HOME = sdk;
    ANDROID_SDK_ROOT = sdk;
  };

  environment.shellInit = ''
    # Android SDK user install (created by scripts/setup-android-sdk.sh)
    if [ -d "$HOME/Android/Sdk" ]; then
      export ANDROID_HOME="$HOME/Android/Sdk"
      export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
      export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
    fi
    export JAVA_HOME="${jdk}"
    export PATH="$JAVA_HOME/bin:$PATH"
  '';
}
