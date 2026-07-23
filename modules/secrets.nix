# sops-nix — encrypted secrets in git, decrypted at activation
#
# Setup (once per human, not per machine clone if you reuse the age key):
#   1. age key:  ~/.config/sops/age/keys.txt   (already created on first machine)
#   2. public key listed in .sops.yaml
#   3. edit secrets:  sops secrets/secrets.yaml
#   4. nrs
#
# On a new machine: restore keys.txt BEFORE first switch that needs secrets,
#   or bootstrap without secrets then install the key.
#
{
  config,
  lib,
  username,
  ...
}:

let
  home = config.users.users.${username}.home or "/home/${username}";
  secretsFile = ../secrets/secrets.yaml;
  haveSecrets = builtins.pathExists secretsFile;
in
{
  config = lib.mkIf haveSecrets {
    sops = {
      defaultSopsFile = secretsFile;
      defaultSopsFormat = "yaml";
      age.keyFile = "${home}/.config/sops/age/keys.txt";

      # Placeholders — fill real values with: sops secrets/secrets.yaml
      secrets = {
        # Discord/Slack webhook for failed nsync → /run/secrets/notify-webhook
        "notify-webhook" = {
          owner = username;
          mode = "0400";
        };
        # Agent/API env → /run/secrets/agent-env (sourced by shells)
        # Contents example:
        #   export ANTHROPIC_API_KEY=...
        #   export OPENAI_API_KEY=...
        "agent-env" = {
          owner = username;
          mode = "0400";
        };
      };
    };

    # Source decrypted agent-env in interactive shells
    programs.zsh.interactiveShellInit = lib.mkAfter ''
      if [[ -r /run/secrets/agent-env ]]; then
        set -a
        # shellcheck disable=SC1091
        source /run/secrets/agent-env
        set +a
      fi
    '';

    programs.bash.interactiveShellInit = lib.mkAfter ''
      if [[ -r /run/secrets/agent-env ]]; then
        set -a
        # shellcheck disable=SC1091
        source /run/secrets/agent-env
        set +a
      fi
    '';
  };
}
