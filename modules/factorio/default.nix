_: let
  port = 34197;
  stateDir = "/var/lib/factorio";
in {
  legion.services.factorio = {
    node = "ricklent";
    module = "factorio";
    stateful = true;
    units = ["factorio"];
    ports.game = port;
    firewall = [
      {
        inherit port;
        proto = "udp";
        scope = "public";
      }
    ];
    backupSet = [stateDir];
  };

  nixos.modules.factorio = {
    config,
    lib,
    ...
  }: {
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
    };

    # The root disk holds the only live copy, so the interval is the
    # play a lost node loses.
    systemd.timers.restic-backups-factorio.timerConfig = {
      OnCalendar = lib.mkForce "00/6:00";
      RandomizedDelaySec = lib.mkForce "15m";
    };
  };
}
