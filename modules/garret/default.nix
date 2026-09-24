{
  self,
  inputs,
  ...
}: let
  # The SQLite index is the only record of what is in the S3 bucket.
  dataDir = "/mnt/garret";
  # Written by the Pusher, which can create files only beside the database.
  backupFile = "${dataDir}/backup.db";

  watermarks = {
    high = 0.95;
    low = 0.85;
  };

  pullerPort = 8081;
  pusherPort = 8082;
  pusherMetricsPort = 9091;
  pullerMetricsPort = 9092;
in {
  flake.lib.garretWatermarks = watermarks;

  legion.services.garret = {
    node = "legion-node4";
    module = "garret";
    stateful = true;
    units = ["garret-pusher" "garret-puller"];
    ports = {
      puller = pullerPort;
      pusher = pusherPort;
      pusher-metrics = pusherMetricsPort;
      puller-metrics = pullerMetricsPort;
    };
    firewall = [
      {
        port = pullerPort;
        proto = "tcp";
        scope = "private";
      }
      {
        port = pusherPort;
        proto = "tcp";
        scope = "private";
      }
      {
        port = pusherMetricsPort;
        proto = "tcp";
        scope = "private";
      }
      {
        port = pullerMetricsPort;
        proto = "tcp";
        scope = "private";
      }
    ];
    volume = {
      name = "legion-garret";
      mountpoint = dataDir;
      hcloudVolumeId = "106562809";
      sizeGiB = 10;
    };
    backupSet = [backupFile];
  };

  nixos.modules.garret = {
    config,
    lib,
    pkgs,
    ...
  }: let
    dbPath = "${dataDir}/garret.db";

    garretAdmin = inputs.garret.packages.${pkgs.stdenv.hostPlatform.system}.garret-admin;

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
        inherit watermarks;

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
            # Release tags are unprotected, so ref_protected stays unset.
            ref_patterns = ["refs/heads/main" "refs/tags/v*"];
            # jeiang/.dotfiles, jeiang/garret, jeiang/ripper.
            repository_ids = ["553667153" "1324491067" "1380302823"];
            event_names = ["push" "workflow_dispatch"];
            job_workflow_refs = [
              "jeiang/.dotfiles/.github/workflows/ci.yml@refs/heads/main"
              "jeiang/garret/.github/workflows/ci.yml@refs/heads/main"
              "jeiang/garret/.github/workflows/ci.yml@refs/tags/v*"
              "jeiang/ripper/.github/workflows/release.yml@refs/tags/v*"
            ];
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
        # Shares the Pusher's bucket-write S3 key until a GetObject-only key
        # is created for it.
        inherit dbPath s3;
        # narinfo and NAR routes stay anonymous; only the browse API is
        # gated.
        browseOidc = pocketIdIssuer;
      };
    };

    # The Volume mount is `nofail`, so without the guard a late or missing
    # Volume silently initializes a fresh, empty index on the root disk.
    systemd.services = let
      guard = self.lib.mountGuard dataDir {
        inherit pkgs;
        owner = "garret";
        mode = "0750";
      };
    in {
      garret-pusher = lib.recursiveUpdate {serviceConfig.MemoryMax = "896M";} guard;
      garret-puller = lib.recursiveUpdate {serviceConfig.MemoryMax = "192M";} guard;
    };

    environment.systemPackages = [garretAdmin];

    # An online copy, so the backup never stops the cache. The Pusher never
    # overwrites a file, hence the rm.
    backups.jobs.garret = {
      pauseUnits = [];
      prepareCommand = ''
        rm -f ${backupFile}
        ${lib.getExe' garretAdmin "garret-admin"} backup ${backupFile}
      '';
    };

    sops = {
      secrets = {
        "garret/s3-access-key-id" = {inherit sopsFile;};
        "garret/s3-secret-access-key" = {inherit sopsFile;};
        # Signing keys are read once at start-up; a secret-only deploy leaves the unit unchanged.
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
