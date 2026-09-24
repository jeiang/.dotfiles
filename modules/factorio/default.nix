_: let
  stateDir = "/var/lib/factorio";
in {
  # Public at proxy.jeiang.dev:44197/udp through a netbird-proxy L4 service
  # (NetBird dashboard, CrowdSec enforce) targeting artemis's UDP 34197 over
  # the trusted mesh; nothing opens a port on the home network.
  nixos.modules.artemis = {
    config,
    lib,
    ...
  }: {
    persistence.directories = [stateDir];

    services.factorio = {
      enable = true;
      game-name = "cornn-flaek";
      autosave-interval = 10;
      # JSON merged into server-settings.json at start: {"game_password": "..."}.
      extraSettingsFile = config.sops.secrets."factorio/settings".path;
    };

    sops.secrets."factorio/settings" = {
      sopsFile = ./secrets.yaml;
      owner = "factorio";
      restartUnits = ["factorio.service"];
    };

    users = {
      groups.factorio = {};
      users.factorio = {
        isSystemUser = true;
        group = "factorio";
      };
    };

    # A static user, not DynamicUser: systemd refuses to hand the existing
    # impermanence bind mount to a dynamic user, and the saves would move
    # under /var/lib/private.
    systemd.services.factorio.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "factorio";
      Group = "factorio";
    };
  };
}
