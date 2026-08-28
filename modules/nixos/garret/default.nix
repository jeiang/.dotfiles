{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.garret = {
    config,
    pkgs,
    ...
  }: let
    # The SQLite index is the only record of what is in the S3 bucket;
    # losing it strands every stored object as an unreclaimable orphan.
    dataDir = "/mnt/garret";
    dbPath = "${dataDir}/garret.db";

    pusherPort = self.lib.ports.legion-node4.garret-pusher;
    pullerPort = self.lib.ports.legion-node4.garret-puller;
    pusherMetricsPort = self.lib.ports.legion-node4.garret-pusher-metrics;
    pullerMetricsPort = self.lib.ports.legion-node4.garret-puller-metrics;

    privateIPv4 = self.lib.legionNodes.legion-node4.privateIPv4;

    sopsFile = ./secrets.yaml;

    pocketIdAudience = "384a5193-a040-4025-a8d3-7815d6269ca2";

    # garret grants no read/write tiers -- any accepted token means full
    # push; the real gate is Pocket ID's per-client group restriction,
    # hence the empty allowed_groups.
    pocketIdIssuer = {
      issuer = "https://auth.jeiang.dev";
      audience = pocketIdAudience;
      jwks_url = "https://auth.jeiang.dev/.well-known/jwks.json";
      allowed_groups = [];
    };

    s3 = {
      bucket = "garret";
      endpointUrl = "https://s3.ca-montreal.megas4.com";
      region = "ca-montreal";
      # Flip to false if MEGA S4 rejects path-style addressing.
      pathStyle = true;
      credentialsFile = config.sops.templates."garret-s3.env".path;
    };
  in {
    imports = [
      inputs.garret.nixosModules.pusher
      inputs.garret.nixosModules.puller
      # The watcher module is deliberately not imported: it belongs on
      # build machines, not the cache host.
    ];

    assertions = [
      {
        assertion = pocketIdAudience != "TODO-REPLACE-WITH-POCKET-ID-GARRET-CLIENT-ID";
        message = "modules/nixos/garret/default.nix: pocketIdAudience is still the placeholder. Register the garret client in Pocket ID and paste its client id here (docs/runbooks/garret.md).";
      }
    ];

    services.garret = {
      pusher = {
        enable = true;
        listen = "0.0.0.0:${toString pusherPort}";
        metricsListen = "${privateIPv4}:${toString pusherMetricsPort}";
        inherit dbPath s3;
        signingKeyFiles = [config.sops.secrets."garret/signing-key".path];

        # Advertised by /api/v1/discovery; without it `garret login` leaves
        # every client's use/list/tree unconfigured.
        pullerEndpoint = "https://cache.jeiang.dev";

        quotaBytes = 268435456000;
        watermarks = {
          high = 0.95;
          low = 0.85;
        };

        # maxInFlightBytes is the real memory bound (a process-wide
        # semaphore over part-sized buffers); partSize must stay at or
        # above S3's 5 MiB multipart minimum.
        limits = {
          maxConcurrentUploads = 16;
          maxInFlightBytes = 402653184; # 384 MiB
          partSize = 33554432; # 32 MiB
          maxPartsInFlight = 2;
        };

        oidc = [
          {
            issuer = "https://token.actions.githubusercontent.com";
            audience = "https://cache-push.jeiang.dev/";
            jwks_url = "https://token.actions.githubusercontent.com/.well-known/jwks";
            # Immutable owner id, not the name: names are renameable.
            github_owner_id = "31970261";
            ref_patterns = ["refs/heads/main"];
            allowed_groups = [];
          }
          # Exactly one issuer may set client_id (discovery advertises the
          # first that does, and it must be the human one; the Puller's
          # browseOidc submodule rejects the option entirely). Pocket ID
          # uses the client id as the audience, hence the same value twice.
          (pocketIdIssuer // {client_id = pocketIdAudience;})
        ];
      };

      puller = {
        enable = true;
        listen = "0.0.0.0:${toString pullerPort}";
        metricsListen = "${privateIPv4}:${toString pullerMetricsPort}";
        inherit dbPath s3;
        # narinfo and NAR routes stay anonymous; only the browse API is
        # gated.
        browseOidc = pocketIdIssuer;
      };
    };

    # The Volume mount is `nofail`, so without the guard a late or missing
    # Volume silently initializes a fresh, empty index on the root disk.
    systemd.services = let
      # ExecStartPre, NOT tmpfiles: tmpfiles-setup is not ordered after the
      # Volume mount, so a first-mount activation would have its work hidden
      # (observed on the first legion-node4 deploy); `+` runs it as root.
      ensureDataDir = "+${pkgs.coreutils}/bin/install -d -o garret -g garret -m 0750 ${dataDir}";
    in {
      garret-pusher =
        {
          serviceConfig = {
            MemoryMax = "896M";
            ExecStartPre = ensureDataDir;
          };
        }
        // self.lib.mountGuard dataDir;

      garret-puller =
        {
          serviceConfig = {
            MemoryMax = "192M";
            ExecStartPre = ensureDataDir;
          };
        }
        // self.lib.mountGuard dataDir;
    };

    sops = {
      secrets = {
        "garret/s3-access-key-id" = {inherit sopsFile;};
        "garret/s3-secret-access-key" = {inherit sopsFile;};
        # restartUnits is load-bearing: signing keys are read once at
        # start-up, and a secret-only deploy leaves the unit byte-identical
        # -- observed as pushes signed with the pre-rotation key.
        "garret/signing-key" = {
          inherit sopsFile;
          owner = "garret";
          restartUnits = ["garret-pusher.service"];
        };
      };

      templates."garret-s3.env" = {
        restartUnits = ["garret-pusher.service" "garret-puller.service"];
        content = ''
          AWS_ACCESS_KEY_ID=${config.sops.placeholder."garret/s3-access-key-id"}
          AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."garret/s3-secret-access-key"}
        '';
      };
    };
  };
}
