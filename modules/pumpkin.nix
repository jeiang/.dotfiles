_: let
  javaPort = 25565;
  bedrockPort = 19132;
  # DynamicUser keeps the state under /var/lib/private.
  stateDir = "/var/lib/private/pumpkin";
in {
  legion.services.pumpkin = {
    node = "peria";
    module = "pumpkin";
    stateful = true;
    units = ["pumpkin"];
    ports = {
      java = javaPort;
      bedrock = bedrockPort;
    };
    firewall = [
      {
        port = javaPort;
        proto = "tcp";
        scope = "public";
      }
      {
        port = bedrockPort;
        proto = "udp";
        scope = "public";
      }
    ];
    backupSet = [stateDir];
  };

  nixos.modules.pumpkin = {lib, ...}: {
    services.pumpkin = {
      enable = true;
      settings = {
        # The list itself is whitelist.json in the state directory, edited
        # by hand; pumpkin reads it at start.
        white_list = true;
        enforce_whitelist = true;
        networking = {
          java.address = "0.0.0.0:${toString javaPort}";
          bedrock = {
            enabled = true;
            address = "0.0.0.0:${toString bedrockPort}";
          };
        };
      };
    };

    # peria's other services fit in what is left of its 2 GB.
    systemd.services.pumpkin.serviceConfig.MemoryMax = "1G";

    # The root disk holds the only live copy, so the interval is the
    # play a lost node loses.
    systemd.timers.restic-backups-pumpkin.timerConfig = {
      OnCalendar = lib.mkForce "00/6:00";
      RandomizedDelaySec = lib.mkForce "15m";
    };
  };
}
