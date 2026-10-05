{inputs, ...}: let
  githubAppId = 5188290;
  # Pocket ID's confidential client for buildbot's garret pushes; its token's `aud` is this id, which modules/garret/default.nix accepts.
  garretClientId = "3e6177be-ac36-4523-8d5b-e941356b3007";
  port = 8010;
  workerPort = 9989;
  workerCount = 1;
  domain = "buildbot.jeiang.dev";
  dump = "/var/backup/buildbot/buildbot.sql";
in {
  flake.lib.buildbotGarretClientId = garretClientId;

  legion.services.buildbot = {
    node = "ricklent";
    module = "buildbot";
    stateful = true;
    units = ["buildbot-master" "buildbot-worker" "buildbot-garret-push" "postgresql"];
    ports.app = port;
    firewall = [
      {
        inherit port;
        proto = "tcp";
        scope = "private";
      }
    ];
    backupSet = [dump];
  };

  nixos.modules.buildbot = {
    config,
    lib,
    pkgs,
    ...
  }: let
    sopsFile = ./secrets.yaml;
    secret = name: config.sops.secrets."buildbot/${name}".path;
    garret = inputs.garret.packages.${pkgs.stdenv.hostPlatform.system}.garret;
    garretConfig = (pkgs.formats.toml {}).generate "buildbot-garret.toml" {
      endpoint = "https://cache-push.jeiang.dev";
      oidc = {
        issuer = "https://auth.jeiang.dev";
        client_id = garretClientId;
        audience = garretClientId;
      };
    };

    # buildbot-nix registers a gcroot for every default-branch push output, built or already local, and for no pull request output, so the roots are exactly what garret should hold.
    gcroots = "/nix/var/nix/gcroots/per-user/buildbot-worker";

    # GARRET_TOKEN is handed to the client as-is, so the config's oidc table only has to parse.
    pushGcroots = pkgs.writeShellScript "buildbot-garret-push" ''
      set -euo pipefail
      GARRET_TOKEN=$(${lib.getExe pkgs.curl} -fsS https://auth.jeiang.dev/api/oidc/token \
        --data-urlencode grant_type=client_credentials \
        --data-urlencode client_id=${garretClientId} \
        --data-urlencode "client_secret@${secret "garret-client-secret"}" \
        | ${lib.getExe pkgs.jq} -er .access_token)
      export GARRET_TOKEN
      find ${gcroots} -type l -print0 \
        | xargs -0 -r readlink -f \
        | grep -v '\.drv$' \
        | sort -u \
        | xargs -r ${lib.getExe' garret "garret"} --config ${garretConfig} push
    '';
  in {
    imports = [
      inputs.buildbot-nix.nixosModules.buildbot-master
      inputs.buildbot-nix.nixosModules.buildbot-worker
    ];

    config = {
      services = {
        buildbot-master = {
          inherit port;
          pbPort = "'tcp:${toString workerPort}:interface=127.0.0.1'";
        };

        buildbot-nix = {
          master = {
            enable = true;
            inherit domain;
            # Caddy on the edge node terminates TLS and tinyauth gates the UI,
            # so buildbot has no login of its own.
            enableNginx = false;
            useHTTPS = true;
            authBackend = "none";
            allowUnauthenticatedControl = true;
            github = {
              enable = true;
              appId = githubAppId;
              appSecretKeyFile = secret "github-app-key";
              webhookSecretFile = secret "github-webhook-secret";
              userAllowlist = ["jeiang"];
            };
            evalWorkerCount = 2;
            evalMaxMemorySize = 2048;
            workersFile = config.sops.templates."buildbot-workers.json".path;
          };

          worker = {
            enable = true;
            workers = workerCount;
            masterUrl = "tcp:host=127.0.0.1:port=${toString workerPort}";
            workerPasswordFile = secret "worker-password";
          };
        };
      };

      # A push that fails (cache outage) or a build that finished while the
      # cache was down is retried on the next tick; garret negotiates, so
      # paths it already holds cost one request.
      systemd = {
        # buildbot-nix never removes its gcroots. Age by mtime alone: the push
        # service reads every link, which refreshes atime. A default-branch
        # evaluation re-registers a root that expired while its output is
        # still current.
        tmpfiles.rules = ["e ${gcroots} - - - m:14d"];

        services.buildbot-garret-push = {
          description = "Push buildbot default-branch outputs to garret";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          path = [config.nix.package pkgs.findutils pkgs.coreutils pkgs.gnugrep];
          environment = {
            NIX_REMOTE = "daemon";
            NIX_CONFIG = "extra-experimental-features = nix-command";
          };
          serviceConfig = {
            Type = "oneshot";
            User = "buildbot-worker";
            ExecStart = pushGcroots;
          };
        };
        timers.buildbot-garret-push = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "2m";
            OnUnitInactiveSec = "5m";
          };
        };
      };

      backups.jobs.buildbot = {
        # pg_dump is consistent without stopping the master, and stopping the
        # worker would kill a running build.
        pauseUnits = [];
        prepareCommand = ''
          set -e
          install -d -m 0700 ${builtins.dirOf dump}
          ${lib.getExe' pkgs.util-linux "runuser"} -u postgres -- ${lib.getExe' config.services.postgresql.package "pg_dump"} --clean --if-exists buildbot > ${dump}.new
          mv ${dump}.new ${dump}
        '';
      };

      sops = {
        secrets = {
          "buildbot/github-app-key" = {
            inherit sopsFile;
            restartUnits = ["buildbot-master.service"];
          };
          "buildbot/github-webhook-secret" = {
            inherit sopsFile;
            restartUnits = ["buildbot-master.service"];
          };
          "buildbot/garret-client-secret" = {
            inherit sopsFile;
            owner = "buildbot-worker";
          };
          "buildbot/worker-password" = {
            inherit sopsFile;
            restartUnits = ["buildbot-worker.service"];
          };
        };

        templates."buildbot-workers.json" = {
          restartUnits = ["buildbot-master.service"];
          content = builtins.toJSON [
            {
              name = config.networking.hostName;
              pass = config.sops.placeholder."buildbot/worker-password";
              cores = workerCount;
            }
          ];
        };
      };
    };
  };
}
