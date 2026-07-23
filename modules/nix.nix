# Nix daemon, registry, GC
{
  pkgs,
  username,
  ...
}:
{
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

  # Run "normal" Linux binaries (AppImages, some npm native mods, etc.)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    zlib
    openssl
    curl
    icu
  ];

  documentation.dev.enable = true;
  documentation.man.cache.enable = true;
}
