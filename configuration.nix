# Thin entrypoint — real config lives in modules/*.nix and home/*.nix
#
# Apply:  nrs
# Layout:
#   modules/wsl.nix        WSL, user, hostname, stateVersion
#   modules/nix.nix        nix settings, nix-ld, docs
#   modules/packages.nix   systemPackages + env vars
#   modules/shell.nix      zsh/bash/starship/tmux
#   modules/dev.nix        git/direnv/docker
#   modules/android.nix    JDK17 + adb + ANDROID_HOME
#   modules/auto-sync.nix  backup timer options + unit
#   modules/notify.nix     OnFailure webhook/log
#   modules/secrets.nix    sops-nix wiring
#   modules/home.nix       home-manager import
#   home/default.nix       user dotfiles
#   secrets/secrets.yaml   encrypted (sops)
#
{ ... }:
{
  ##########################################################################
  # Machine knobs — edit here, leave modules generic
  ##########################################################################
  nixosWsl.autoSync = {
    enable = true;
    interval = "4h";
    onBoot = "30min";
    onlyWhenDirty = false;
    updateFlake = false; # keep nixpkgs pinned
    updateAgents = true; # herdr + pi @latest each tick
    push = true;
  };

  nixosWsl.notify = {
    enable = true;
    # Prefer: sops secrets/secrets.yaml → notify-webhook
    # Or local file: ~/.config/nixos-wsl/notify-webhook
    webhookUrl = "";
    useSopsSecret = true;
  };
}
