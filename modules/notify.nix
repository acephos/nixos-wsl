# Failure notifications for auto-sync (webhook / optional script)
#
#   nixosWsl.notify.enable = true;
#   nixosWsl.notify.webhookUrl = "https://...";  # or leave empty + use sops
#
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.nixosWsl.notify;
  home = config.users.users.${username}.home or "/home/${username}";
  notifyScript = pkgs.writeShellScript "nixos-wsl-notify-failure" ''
    set -euo pipefail
    UNIT="''${1:-nixos-wsl-auto-sync.service}"
    HOST="$(hostname 2>/dev/null || echo unknown)"
    WHEN="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    LOG="$(journalctl -u "$UNIT" -n 40 --no-pager 2>/dev/null || true)"
    MSG="nixos-wsl auto-sync FAILED on $HOST at $WHEN (unit=$UNIT)"

    # Prefer sops-deployed secret path, then config webhook, then local file
    URL=""
    if [[ -n "''${NIXOS_NOTIFY_WEBHOOK_FILE:-}" && -r "''${NIXOS_NOTIFY_WEBHOOK_FILE}" ]]; then
      URL="$(tr -d '[:space:]' < "''${NIXOS_NOTIFY_WEBHOOK_FILE}")"
    fi
    if [[ -z "$URL" && -n "''${NIXOS_NOTIFY_WEBHOOK:-}" ]]; then
      URL="$NIXOS_NOTIFY_WEBHOOK"
    fi
    if [[ -z "$URL" && -r "${home}/.config/nixos-wsl/notify-webhook" ]]; then
      URL="$(tr -d '[:space:]' < "${home}/.config/nixos-wsl/notify-webhook")"
    fi

    echo "$MSG" >&2

    if [[ -n "$URL" ]]; then
      # Slack/Discord-compatible JSON; plain POST body also works for many hooks
      ${pkgs.curl}/bin/curl -sS -m 15 -X POST "$URL" \
        -H 'Content-Type: application/json' \
        --data-binary @- <<EOF || true
    {"text":$(${pkgs.jq}/bin/jq -Rn --arg t "$MSG" '$t'),"content":$(${pkgs.jq}/bin/jq -Rn --arg t "$MSG\n```\n$LOG\n```" '$t')}
    EOF
    else
      # Always leave a breadcrumb in the journal + a stamp file
      mkdir -p "${home}/.local/state/nixos-wsl"
      {
        echo "$MSG"
        echo "----"
        echo "$LOG"
      } >>"${home}/.local/state/nixos-wsl/last-sync-failure.log"
      echo "$WHEN" >"${home}/.local/state/nixos-wsl/last-sync-failure"
      echo "no webhook configured — wrote ${home}/.local/state/nixos-wsl/last-sync-failure.log" >&2
    fi
  '';
in
{
  options.nixosWsl.notify = {
    enable = lib.mkEnableOption "notify on auto-sync failure";

    webhookUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Public webhook URL (Slack/Discord/etc). Prefer sops secret
        `notify-webhook` instead of putting this in git.
      '';
    };

    # When sops secret exists, use it (path injected below)
    useSopsSecret = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "If true and sops secret notify-webhook exists, use it.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nixos-wsl-auto-sync = {
      unitConfig.OnFailure = [ "nixos-wsl-notify-failure.service" ];
    };

    systemd.services.nixos-wsl-notify-failure = {
      description = "Notify that nixos-wsl auto-sync failed";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
        pkgs.systemd
      ];
      environment = {
        HOME = home;
        NIXOS_NOTIFY_WEBHOOK = cfg.webhookUrl;
        NIXOS_NOTIFY_WEBHOOK_FILE =
          if (cfg.useSopsSecret && (config.sops.secrets ? "notify-webhook")) then
            config.sops.secrets."notify-webhook".path
          else
            "";
      };
      serviceConfig = {
        Type = "oneshot";
        User = username;
        Group = "users";
        ExecStart = "${notifyScript} nixos-wsl-auto-sync.service";
      };
    };
  };
}
