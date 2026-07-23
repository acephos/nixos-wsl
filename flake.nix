{
  description = "Reproducible NixOS-WSL system — clone, rebuild, identical machine";

  inputs = {
    # Pinned exactly to the generation this repo was bootstrapped from.
    # Bump with: nix flake update nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/fd1462031fdee08f65fd0b4c6b64e22239a77870";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agent multiplexer — https://herdr.dev
    herdr.url = "github:ogulcancelik/herdr";
  };

  outputs =
    { self, nixpkgs, nixos-wsl, herdr, ... }:
    let
      system = "x86_64-linux";
      # Single source of truth for who this machine belongs to.
      # Change here (and wsl.defaultUser) if you fork for another account.
      username = "acephos";
      hostName = "nixos";
    in
    {
      nixosConfigurations.${hostName} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit herdr username hostName;
        };
        modules = [
          nixos-wsl.nixosModules.default
          ./configuration.nix
        ];
      };

      # Convenience: `nix build .#nixos` → system closure
      packages.${system}.nixos =
        self.nixosConfigurations.${hostName}.config.system.build.toplevel;

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
    };
}
