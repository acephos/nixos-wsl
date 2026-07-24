# Home Manager — user-level state (dotfiles, identity, XDG)
# System packages/services stay in modules/*.nix
{
  config,
  pkgs,
  lib,
  username,
  ...
}:
{
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";

  # User PATH extras (system zsh also prepends these)
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "$HOME/go/bin"
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    npm_config_prefix = "$HOME/.local";
  };

  # npm global prefix for pi etc.
  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.local
    cache=${config.home.homeDirectory}/.npm
  '';

  # pi agent settings + extension package list (source of truth in this repo).
  # Out-of-store symlink so `pi install`/`pi remove` can still write the file,
  # and those edits land in git for the next nrs/nsync commit.
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos-wsl/home/pi/settings.json";

  # pi-web-access config — auto-summary avoids curator browser (broken/headless on WSL).
  home.file.".pi/web-search.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos-wsl/home/pi/web-search.json";

  # Lightweight zshrc — system owns aliases/prompt in /etc/zshrc
  home.file.".zshrc".text = ''
    # nixos-wsl managed (home-manager)
    # System aliases, prompt, completion: /etc/zshrc
    # After `nrs`, reload with:   exec zsh    (or: nreload)
    # Do NOT use:  source ./zshrc
    # Optional personal overrides below this line:
  '';

  # Git identity — edit these, then nrs (not secrets, but personal)
  programs.git = {
    enable = true;
    settings = {
      user.name = "acephos";
      user.email = "acephos@users.noreply.github.com";
      # gh credential helper is set by `gh auth setup-git`
    };
  };

  # Pi harness-study corpus: ingest/derive/push every 30m while user session is up.
  # Repo: ~/harness-study (https://github.com/acephos/harness-study)
  systemd.user.services.harness-study-sync = {
    Unit.Description = "Pi harness-study session sync";
    Service = {
      Type = "oneshot";
      WorkingDirectory = "%h/harness-study";
      ExecStart = "${pkgs.python3}/bin/python3 %h/harness-study/study.py sync";
    };
  };
  systemd.user.timers.harness-study-sync = {
    Unit.Description = "Timer for Pi harness-study session sync";
    Timer = {
      OnBootSec = "5m";
      OnUnitActiveSec = "30m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  xdg.enable = true;

  # Don't manage full HM news noise
  news.display = "silent";

  # systemPackages owns the heavy CLI kit; add user-only tools here later
  home.packages = [ ];
}
