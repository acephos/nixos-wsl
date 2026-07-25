# Shared shell aliases (bash + zsh). Imported by modules/shell.nix.
{
  ll = "eza -la --icons --git --group-directories-first";
  la = "eza -a --icons";
  lt = "eza -la --icons --git --tree --level=2";
  ls = "eza --icons --group-directories-first";
  cat = "bat --paging=never";
  g = "git";
  lg = "lazygit";
  h = "herdr";
  hk = "hunk";
  hdiff = "git hdiff";
  hshow = "git hshow";
  v = "nvim";
  vi = "nvim";
  vim = "nvim";
  t = "tmux";
  y = "yazi";
  ".." = "cd ..";
  "..." = "cd ../..";
  dc = "docker compose";
  dps = "docker ps";
  # NixOS flake helpers (repo: ~/nixos-wsl)
  rebuild = "~/nixos-wsl/scripts/rebuild.sh switch";
  nrs = "~/nixos-wsl/scripts/rebuild.sh switch";
  nrb = "~/nixos-wsl/scripts/rebuild.sh boot";
  nrt = "~/nixos-wsl/scripts/rebuild.sh test --no-commit --no-push";
  nrf = "~/nixos-wsl/scripts/rebuild.sh switch -- --refresh";
  nfu = "cd ~/nixos-wsl && nix flake update && ~/nixos-wsl/scripts/rebuild.sh switch";
  ngood = "~/nixos-wsl/scripts/checkpoint.sh";
  nlist = "sudo nix-env --list-generations -p /nix/var/nix/profiles/system";
  nroll = "sudo nixos-rebuild switch --rollback";
  nreload = "exec zsh";
  nsync = "sudo systemctl start nixos-wsl-auto-sync.service && journalctl -u nixos-wsl-auto-sync.service -n 40 --no-pager";
  nsync-status = "systemctl status nixos-wsl-auto-sync.timer nixos-wsl-auto-sync.service --no-pager";
  nup = "~/nixos-wsl/scripts/update-agents.sh && ~/nixos-wsl/scripts/rebuild.sh switch";
  nup-agents = "~/nixos-wsl/scripts/update-agents.sh";
  npi-sync = "~/nixos-wsl/scripts/sync-pi-config.sh --commit --push";
  ndrill = "~/nixos-wsl/scripts/restore-drill.sh";
  nix-search = "nix search nixpkgs";
  # Android
  apkde = "cd ~/im-ok-maa";
  adb-devices = "adb devices -l";
  android-env = "~/nixos-wsl/scripts/android-env-check.sh";
}
