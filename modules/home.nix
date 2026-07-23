# Wire home-manager as a NixOS module
{
  inputs,
  username,
  ...
}:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {
      inherit username;
    };
    users.${username} = import ../home/default.nix;
  };
}
