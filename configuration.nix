# NixOS-WSL system configuration
# Docs: https://github.com/nix-community/NixOS-WSL
# Search: https://search.nixos.org
#
# Apply (from this repo):
#   sudo nixos-rebuild switch --flake .#nixos
# Update inputs + rebuild:
#   nix flake update && sudo nixos-rebuild switch --flake .#nixos

{
  config,
  lib,
  pkgs,
  herdr,
  username,
  hostName,
  ...
}:

let
  herdrPkg = herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Shared by bash + zsh so they never drift
  shellAliases = {
    ll = "eza -la --icons --git --group-directories-first";
    la = "eza -a --icons";
    lt = "eza -la --icons --git --tree --level=2";
    ls = "eza --icons --group-directories-first";
    cat = "bat --paging=never";
    g = "git";
    lg = "lazygit";
    h = "herdr";
    v = "nvim";
    vi = "nvim";
    vim = "nvim";
    t = "tmux";
    y = "yazi";
    ".." = "cd ..";
    "..." = "cd ../..";
    dc = "docker compose";
    dps = "docker ps";
    # NixOS (flake-aware — repo lives at ~/nixos-wsl)
    # nrs/rebuild: switch + on success auto-commit, tag known-good, push
    rebuild = "~/nixos-wsl/scripts/rebuild.sh switch";
    nrs = "~/nixos-wsl/scripts/rebuild.sh switch";
    nrb = "~/nixos-wsl/scripts/rebuild.sh boot";
    nrt = "~/nixos-wsl/scripts/rebuild.sh test --no-commit --no-push";
    nrf = "~/nixos-wsl/scripts/rebuild.sh switch -- --refresh";
    nfu = "cd ~/nixos-wsl && nix flake update && ~/nixos-wsl/scripts/rebuild.sh switch";
    # Checkpoint current files as known-good without rebuilding (before experiments)
    ngood = "~/nixos-wsl/scripts/checkpoint.sh";
    nlist = "sudo nix-env --list-generations -p /nix/var/nix/profiles/system";
    nroll = "sudo nixos-rebuild switch --rollback";
    # Reload shell config after nrs (aliases live in /etc/zshrc, NOT ./zshrc)
    nreload = "exec zsh";
    # Manually kick the backup timer's service once
    nsync = "sudo systemctl start nixos-wsl-auto-sync.service && journalctl -u nixos-wsl-auto-sync.service -n 40 --no-pager";
    nsync-status = "systemctl status nixos-wsl-auto-sync.timer nixos-wsl-auto-sync.service --no-pager";
    # Bump herdr + pi to latest, rebuild if flake.lock changed, push
    nup = "~/nixos-wsl/scripts/update-agents.sh && ~/nixos-wsl/scripts/rebuild.sh switch";
    nup-agents = "~/nixos-wsl/scripts/update-agents.sh";
    nix-search = "nix search nixpkgs";
  };
in
{
  wsl.enable = true;
  wsl.defaultUser = username;
  wsl.interop.includePath = true;

  networking.hostName = hostName;

  ##########################################################################
  # Auto backup: rebuild + commit + push on a timer
  # Change interval anytime, then nrs. Examples: "4h", "30min", "1d"
  ##########################################################################
  nixosWsl.autoSync = {
    enable = true;
    interval = "4h";
    onBoot = "30min";
    # false = full rebuild heartbeat every interval
    # true  = only when git is dirty / unpushed (lighter)
    onlyWhenDirty = false;
    # Do NOT auto-bump nixpkgs/nixos-wsl — keep the base OS pinned
    updateFlake = false;
    # DO auto-bump fast-moving agents every tick: herdr (flake) + pi (npm latest)
    updateAgents = true;
    push = true;
  };

  # Helpful ~/.zshrc — system aliases still come from /etc/zshrc
  system.activationScripts.acephosDotZshrc.text = ''
    zshrc=/home/${username}/.zshrc
    marker='# nixos-wsl managed'
    if [ ! -f "$zshrc" ] || grep -q 'Created by newuser' "$zshrc" 2>/dev/null || grep -q "$marker" "$zshrc" 2>/dev/null; then
      cat > "$zshrc" << 'EOF'
# nixos-wsl managed
# System aliases, prompt, completion: /etc/zshrc (from configuration.nix)
# After `nrs`, reload with:   exec zsh    (or: nreload)
# Do NOT use:  source ./zshrc   ← that path does not exist
# Optional personal overrides below this line:
EOF
      chown ${username}:users "$zshrc"
      chmod 644 "$zshrc"
    fi
  '';

  nixpkgs.config.allowUnfree = true;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        username
      ];
      auto-optimise-store = true;
      max-jobs = "auto";
      cores = 0;
    };
    # Make legacy `<nixpkgs>` and `nix run nixpkgs#...` hit this flake's pin
    nixPath = [ "nixpkgs=${pkgs.path}" ];
    registry.nixpkgs.to = {
      type = "path";
      path = pkgs.path;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  time.timeZone = "America/New_York";

  # Run "normal" Linux binaries (AppImages, some npm native mods, etc.)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    zlib
    openssl
    curl
    icu
  ];

  # Man pages for C libs / dev docs
  documentation.dev.enable = true;
  documentation.man.cache.enable = true;

  ##########################################################################
  # Packages — system-wide CLI starter kit
  ##########################################################################
  environment.systemPackages = with pkgs; [
    # --- editors / terminal ---
    neovim
    vim
    tmux
    starship
    herdrPkg # agent multiplexer (github:ogulcancelik/herdr)

    # --- VCS ---
    git
    git-lfs
    gh
    lazygit
    delta

    # --- languages / runtimes (system defaults; pin per-project via flakes/direnv) ---
    nodejs_24
    bun
    python3
    uv # modern Python package/manager runner
    go
    rustup # rustup default toolchain via: rustup default stable
    gcc
    gnumake
    cmake
    pkg-config
    openssl

    # --- containers ---
    docker-compose

    # --- search / nav / files ---
    ripgrep
    fd
    fzf
    zoxide
    tree
    yazi # TUI file manager
    unzip
    zip
    p7zip
    rsync
    file
    which
    dust # du with a brain
    duf # df prettier

    # --- data / http / json ---
    jq
    yq-go
    xh # friendly curl
    curl
    wget

    # --- process / system ---
    btop
    htop
    procps
    lsof
    pciutils

    # --- nicer CLI utilities ---
    bat
    eza
    sd # simpler sed
    tealdeer # tldr pages (fast)
    glow # markdown in terminal
    hyperfine # benchmarking
    tokei # count lines of code
    watchexec # rerun on file change
    just # command runner (Justfile)
    gum # pretty shell script UI
    direnv
    nix-direnv
    nixfmt
    nil # Nix LSP

    # --- db / misc dev ---
    sqlite
    postgresql # client tools (psql)
    openssh
    age # simple encryption
    sops # secrets (optional but handy)

    # --- GUI via WSLg ---
    chromium
  ];

  ##########################################################################
  # Programs
  ##########################################################################
  programs.git = {
    enable = true;
    lfs.enable = true;
    config = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      core.editor = "nvim";
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        line-numbers = true;
        side-by-side = false;
      };
      merge.conflictstyle = "zdiff3";
      rerere.enabled = true;
      # Set identity once (not committed as secrets-adjacent personal data if public):
      # user.name = "Your Name";
      # user.email = "you@example.com";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      command_timeout = 1000;
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };
      directory = {
        truncation_length = 3;
        fish_style_pwd_dir_length = 1;
      };
      git_branch.symbol = " ";
      nix_shell = {
        symbol = " ";
        format = "via [$symbol$state( \\($name\\))]($style) ";
      };
      nodejs.symbol = " ";
      python.symbol = " ";
      rust.symbol = " ";
      golang.symbol = " ";
      package.disabled = true;
    };
  };

  # Docker inside WSL (alternative: use Docker Desktop + WSL integration)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less";
    LESS = "-R";
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
  };

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    shell = pkgs.zsh;
  };

  ##########################################################################
  # Shell
  ##########################################################################
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = shellAliases;

    histSize = 50000;

    ohMyZsh = {
      enable = true;
      # starship owns the prompt — keep theme minimal
      theme = "robbyrussell";
      plugins = [
        "git"
        "sudo"
        "direnv"
        "docker"
        "docker-compose"
        "npm"
        "node"
        "rust"
        "golang"
        "tmux"
      ];
    };

    interactiveShellInit = ''
      # User bins — keep /run/wrappers/bin first (setuid sudo)
      export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"

      # Starship prompt
      eval "$(starship init zsh)"

      # zoxide (smarter cd) — use: z <dir>, zi to interactive
      command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

      # fzf keybindings (Ctrl-R history, Ctrl-T files, Alt-C cd)
      if command -v fzf >/dev/null; then
        source <(fzf --zsh)
      fi

      # Handy: mkcd
      mkcd() { mkdir -p "$1" && cd "$1"; }

      # Quick nix shell for a package: ns ripgrep
      ns() { nix shell "nixpkgs#$1" "''${@:2}"; }

      # Dev shell from flake in cwd
      alias nd='nix develop'
    '';
  };

  programs.bash = {
    completion.enable = true;
    shellAliases = shellAliases;
  };

  # tmux sensible defaults
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    keyMode = "vi";
    clock24 = true;
    historyLimit = 50000;
    extraConfig = ''
      set -g mouse on
      set -g base-index 1
      setw -g pane-base-index 1
      set -g renumber-windows on
      set -sg escape-time 10
      set -g focus-events on
      # prefix r reloads config
      bind r source-file /etc/tmux.conf \; display "reloaded"
      # split with | and -
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"
    '';
  };

  # First NixOS version this config was written against. Never change.
  system.stateVersion = "26.05";
}
