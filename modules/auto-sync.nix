# Periodic rebuild + git backup of ~/nixos-wsl
#
# Configure in configuration.nix:
#   nixosWsl.autoSync.enable = true;
#   nixosWsl.autoSync.interval = "4h";   # systemd calendar / span
#
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.nixosWsl.autoSync;
  home = config.users.users.${username}.home or "/home/${username}";
in
{
  options.nixosWsl.autoSync = {
    enable = lib.mkEnableOption "periodic flake rebuild + git push backup";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "4h";
      example = "6h";
      description = ''
        How often to run after the previous run finishes.
        Passed to systemd timer OnUnitActiveSec (e.g. "4h", "30min", "1d").
      '';
    };

    onBoot = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = "Delay after boot before the first run (OnBootSec).";
    };

    flakePath = lib.mkOption {
      type = lib.types.str;
      default = "${home}/nixos-wsl";
      description = "Path to the nixos-wsl git/flake repo.";
    };

    # Safer default for unattended runs: only act when there is something to backup.
    # Set false if you want a full rebuild heartbeat every interval regardless.
    onlyWhenDirty = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        If true, skip when the git tree is clean and already pushed.
        If false (default), rebuild + retag known-good every interval.
      '';
    };

    updateFlake = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        If true, run `nix flake update` before rebuild (bumps nixpkgs etc.).
        Off by default — auto-updating nixpkgs can surprise you.
      '';
    };

    updateAgents = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        If true, before each sync run `scripts/update-agents.sh`:
          - herdr: `nix flake update herdr` (system package)
          - pi:    `npm i -g @earendil-works/pi-coding-agent@latest` (~/.local)
        nixpkgs / nixos-wsl stay pinned. Records versions in agents.lock.json.
      '';
    };

    push = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "git push after a successful rebuild/checkpoint.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nixos-wsl-auto-sync = {
      description = "NixOS-WSL flake rebuild + git backup";
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "nix-daemon.service"
      ];
      # `path` entries are treated as prefixes; NixOS appends /bin automatically.
      # So use /run/wrappers (→ …/bin/sudo), not /run/wrappers/bin.
      path = [
        "/run/wrappers"
        "/run/current-system/sw"
        pkgs.bash
        pkgs.coreutils
        pkgs.git
        pkgs.gh
        pkgs.nix
        pkgs.gnugrep
        pkgs.gawk
        pkgs.util-linux # flock
        pkgs.jq
        pkgs.nodejs # npm for pi
      ];
      environment = {
        HOME = home;
        USER = username;
        NIXOS_FLAKE = cfg.flakePath;
        NIXOS_AUTO_PUSH = if cfg.push then "1" else "0";
        NIXOS_AUTO_COMMIT = "1";
        NIXOS_AUTO_SYNC_ONLY_DIRTY = if cfg.onlyWhenDirty then "1" else "0";
        NIXOS_AUTO_SYNC_UPDATE_FLAKE = if cfg.updateFlake then "1" else "0";
        NIXOS_AUTO_SYNC_UPDATE_AGENTS = if cfg.updateAgents then "1" else "0";
        npm_config_prefix = "${home}/.local";
        # gh / git / npm
        XDG_CONFIG_HOME = "${home}/.config";
        XDG_DATA_HOME = "${home}/.local/share";
        GIT_TERMINAL_PROMPT = "0";
      };
      serviceConfig = {
        Type = "oneshot";
        User = username;
        Group = "users";
        WorkingDirectory = cfg.flakePath;
        # flock: skip if a manual nrs / another tick is already running
        ExecStart = "${pkgs.util-linux}/bin/flock -n ${cfg.flakePath}/.auto-sync.lock ${cfg.flakePath}/scripts/auto-sync.sh";
        TimeoutStartSec = "2h";
        Nice = 10;
      };
    };

    systemd.timers.nixos-wsl-auto-sync = {
      description = "Timer: NixOS-WSL auto-sync (${cfg.interval})";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.onBoot;
        OnUnitActiveSec = cfg.interval;
        Persistent = true; # catch up after sleep/WSL shutdown
        RandomizedDelaySec = "10min";
        Unit = "nixos-wsl-auto-sync.service";
      };
    };
  };
}
