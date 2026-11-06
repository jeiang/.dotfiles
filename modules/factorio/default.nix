_: let
  port = 34197;
  user = "factorio";
  unit = "factorio.service";
  stateMode = "0750";
in {
  flake.lib.factorioPort = port;

  nixos.modules.artemis = {
    config,
    lib,
    ...
  }: let
    stateDir = "/var/lib/${config.services.factorio.stateDirName}";
  in {
    persistence.directories = [
      {
        directory = stateDir;
        inherit user;
        group = user;
        mode = stateMode;
      }
    ];
    backups.persist = {
      paths = [stateDir];
      stopUnits = [unit];
    };
    monitoredUnits = [unit];

    services.factorio = {
      enable = true;
      inherit port;
      game-name = "cornn-flaek";
      autosave-interval = 10;
      # JSON merged into server-settings.json at start: {"game_password": "..."}.
      extraSettingsFile = config.sops.secrets."factorio/settings".path;
    };

    sops.secrets."factorio/settings" = {
      sopsFile = ./secrets.yaml;
      owner = user;
      restartUnits = [unit];
    };

    users = {
      groups.${user} = {};
      users.${user} = {
        isSystemUser = true;
        group = user;
      };
    };

    # A static user keeps the saves at /var/lib/factorio; DynamicUser would
    # move them into /var/lib/private, which restic would then back up as a
    # symlink.
    systemd.services.factorio.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = user;
      Group = user;
      StateDirectoryMode = stateMode;
    };
  };
}
