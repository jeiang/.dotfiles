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

  nixos.modules.pumpkin = {
    config,
    lib,
    pkgs,
    ...
  }: let
    whitelistFile = pkgs.writeText "pumpkin-whitelist.json" (builtins.toJSON [
      {
        uuid = "a73ca049-08fa-42d1-84c1-4eb4f13af055";
        name = "Jeiang";
      }
      {
        uuid = "e90cc15c-5885-4670-96c6-be196e9e73c7";
        name = "justinmybubble";
      }
      {
        uuid = "3e63deaa-3d4e-4104-a3f6-869cd04894fe";
        name = "jkmn";
      }
      {
        uuid = "2001e481-ca78-47e9-a7dd-bca90bf5fa85";
        name = "Wiierd";
      }
    ]);
  in {
    services.pumpkin = {
      enable = true;
      settings = {
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

    systemd = {
      services.pumpkin = {
        preStart = ''
          mkdir -p "${config.services.pumpkin.dataDir}/data"
          install -m600 ${whitelistFile} "${config.services.pumpkin.dataDir}/data/whitelist.json"
        '';
        # peria's other services fit in what is left of its 2 GB.
        serviceConfig.MemoryMax = "1G";
      };

      # The root disk holds the only live copy, so the interval is the
      # play a lost node loses.
      timers.restic-backups-pumpkin.timerConfig = {
        OnCalendar = lib.mkForce "00/6:00";
        RandomizedDelaySec = lib.mkForce "15m";
      };
    };
  };
}
