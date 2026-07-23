# Drop this in a project root, then:  echo "use flake" > .envrc && direnv allow
{
  description = "Per-project dev shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            # pick what the project needs
            nodejs_24
            bun
            python3
            uv
            go
            # rust via rustup on the system, or:
            # rustc cargo rust-analyzer
            git
            jq
            just
          ];

          shellHook = ''
            echo "📦 dev shell ready ($(basename "$PWD"))"
          '';
        };
      });
    };
}
