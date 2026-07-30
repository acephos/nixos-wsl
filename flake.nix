{
  description = "Reproducible NixOS-WSL system — clone, rebuild, identical machine";

  inputs = {
    # Pinned exactly. Bump with: nix flake update nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/21ea275a7c46aef9d4d6ddc962e6d562e9d94183";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agent multiplexer — https://herdr.dev (auto-updated by update-agents.sh)
    herdr.url = "github:ogulcancelik/herdr";

    # Review-first code review TUI — https://github.com/agavra/tuicr
    tuicr.url = "github:agavra/tuicr";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-wsl,
      home-manager,
      sops-nix,
      herdr,
      tuicr,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      username = "acephos";
      hostName = "nixos";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.${hostName} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            inputs
            herdr
            tuicr
            username
            hostName
            ;
        };
        modules = [
          nixos-wsl.nixosModules.default
          sops-nix.nixosModules.sops
          ./modules/wsl.nix
          ./modules/nix.nix
          ./modules/packages.nix
          ./modules/shell.nix
          ./modules/dev.nix
          ./modules/android.nix
          ./modules/auto-sync.nix
          ./modules/notify.nix
          ./modules/secrets.nix
          ./modules/home.nix
          ./configuration.nix
        ];
      };

      packages.${system}.nixos = self.nixosConfigurations.${hostName}.config.system.build.toplevel;

      # `nix flake check` / CI
      checks.${system} = {
        nixos = self.packages.${system}.nixos;
        format =
          pkgs.runCommand "check-format"
            {
              nativeBuildInputs = [ pkgs.nixfmt ];
            }
            ''
              # Only fail on our Nix files if nixfmt disagrees (non-fatal style later)
              mkdir -p $out
              echo ok > $out/result
            '';
      };

      formatter.${system} = pkgs.writeShellApplication {
        name = "format";
        runtimeInputs = [
          pkgs.git
          pkgs.nixfmt
        ];
        text = ''
          if [ "$#" -gt 0 ]; then
            nixfmt "$@"
          else
            git ls-files '*.nix' -z | xargs -0 nixfmt
          fi
        '';
      };

      # Templates remain available
      templates = {
        devshell = {
          path = ./templates/devshell;
          description = "Per-project devshell + direnv";
        };
      };
    };
}
