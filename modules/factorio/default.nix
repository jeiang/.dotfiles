_: let
  port = 34197;
  stateDir = "/var/lib/factorio";
in {
  flake.lib.factorioPort = port;

  nixos.modules.artemis = {
    config,
    lib,
    ...
  }: {
    persistence.directories = [
      {
        directory = stateDir;
        user = "factorio";
        group = "factorio";
        mode = "0750";
      }
    ];

    services.factorio = {
      enable = true;
      inherit port;
      openFirewall = false;
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

    # A static user keeps the saves at /var/lib/factorio; DynamicUser would
    # move them into /var/lib/private, which restic would then back up as a
    # symlink.
    systemd.services.factorio.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "factorio";
      Group = "factorio";
      StateDirectoryMode = "0750";
    };
  };
}
