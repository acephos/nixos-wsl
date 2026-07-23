# System-wide CLI starter kit
{
  pkgs,
  herdr,
  ...
}:
let
  herdrPkg = herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  environment.systemPackages = with pkgs; [
    # --- editors / terminal ---
    neovim
    vim
    tmux
    starship
    herdrPkg

    # --- VCS ---
    git
    git-lfs
    gh
    lazygit
    delta

    # --- languages / runtimes ---
    nodejs_24
    bun
    python3
    uv
    go
    rustup
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
    yazi
    unzip
    zip
    p7zip
    rsync
    file
    which
    dust
    duf

    # --- data / http / json ---
    jq
    yq-go
    xh
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
    sd
    tealdeer
    glow
    hyperfine
    tokei
    watchexec
    just
    gum
    direnv
    nix-direnv
    nixfmt
    nil

    # --- db / misc dev ---
    sqlite
    postgresql
    openssh
    age
    sops

    # --- GUI via WSLg ---
    chromium
  ];

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less";
    LESS = "-R";
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
  };
}
