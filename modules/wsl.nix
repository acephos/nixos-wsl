# WSL + host identity
{
  pkgs,
  username,
  hostName,
  ...
}:
{
  wsl.enable = true;
  wsl.defaultUser = username;
  wsl.interop.includePath = true;

  networking.hostName = hostName;

  time.timeZone = "America/New_York";

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    shell = pkgs.zsh;
  };

  # First NixOS version this config was written against. Never change.
  system.stateVersion = "26.05";
}
