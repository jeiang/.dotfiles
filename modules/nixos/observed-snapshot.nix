{lib, ...}: {
  flake.nixosModules.observedSnapshot = {
    config,
    pkgs,
    ...
  }: let
    cfg = config.observedSnapshot;
    snapshot = pkgs.writers.writePython3Bin "observed-snapshot" {} (builtins.readFile ./hermes-snapshot.py);
  in {
    options.observedSnapshot = {
      bindAddress = lib.mkOption {
        type = lib.types.str;
        description = "Private address that serves the current snapshot.";
      };
      services = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
      volumes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
    };

    config = {
      systemd = {
        services = {
          observed-snapshot = {
            description = "Write a bounded observed host snapshot";
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              StateDirectory = "observed-snapshot";
              StateDirectoryMode = "0755";
              ExecStart = "${snapshot}/bin/observed-snapshot /var/lib/observed-snapshot/current.json";
            };
            environment = {
              HERMES_SNAPSHOT_SERVICES = lib.concatStringsSep "," cfg.services;
              HERMES_SNAPSHOT_VOLUMES = lib.concatStringsSep "," cfg.volumes;
            };
          };
          observed-snapshot-export = {
            description = "Serve the current observed snapshot on the private network";
            wantedBy = ["multi-user.target"];
            after = ["observed-snapshot.service"];
            requires = ["observed-snapshot.service"];
            serviceConfig = {
              ExecStart = "${pkgs.python3}/bin/python -m http.server 9787 --bind ${cfg.bindAddress} --directory /var/lib/observed-snapshot";
              Restart = "always";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ReadOnlyPaths = ["/var/lib/observed-snapshot"];
            };
          };
        };
        timers.observed-snapshot = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "5m";
            OnUnitActiveSec = "15m";
          };
        };
        tmpfiles.rules = [
          "d /var/lib/observed-snapshot/history 0755 root root 7d -"
        ];
      };
    };
  };
}
