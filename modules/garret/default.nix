{inputs, ...}: let
  # The SQLite index is the only record of what is in the S3 bucket.
  # pusher.nix's default dbPath lives in its StateDirectory.
  dataDir = "/var/lib/garret";
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
    node = "ricklent";
    module = "garret";
    stateful = true;
    units = ["garret-pusher" "garret-puller"];
    ports = {
      puller = pullerPort;
      pusher = pusherPort;
      pusher-metrics = pusherMetricsPort;
      puller-metrics = pullerMetricsPort;
    };
    publicHostnames = ["cache.jeiang.dev" "cache-push.jeiang.dev"];
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
      {
        port = 443;
        proto = "tcp";
        scope = "public";
      }
    ];
    backupSet = [backupFile];
  };

  nixos.modules.garret = {
    config,
    lib,
    pkgs,
    ...
  }: let
    garretAdmin = inputs.garret.packages.${pkgs.stdenv.hostPlatform.system}.garret-admin;

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
        metricsListen = "0.0.0.0:${toString pusherMetricsPort}";
        inherit s3;
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
            # jeiang/.dotfiles, jeiang/garret, jeiang/ripper, jeiang/renpy_proj.
            repository_ids = ["553667153" "1324491067" "1380302823" "1395832586"];
            event_names = ["push" "workflow_dispatch"];
            job_workflow_refs = [
              "jeiang/.dotfiles/.github/workflows/ci.yml@refs/heads/main"
              "jeiang/garret/.github/workflows/ci.yml@refs/heads/main"
              "jeiang/garret/.github/workflows/ci.yml@refs/tags/v*"
              "jeiang/ripper/.github/workflows/release.yml@refs/tags/v*"
              "jeiang/renpy_proj/.github/workflows/garret.yml@refs/heads/main"
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
        metricsListen = "0.0.0.0:${toString pullerMetricsPort}";
        # Its own key, limited to GetObject on the bucket: the Puller only
        # presigns GETs, so this public-facing process cannot write or
        # delete cache objects.
        s3 = s3 // {credentialsFile = config.sops.templates."garret-puller-s3.env".path;};
        # narinfo and NAR routes stay anonymous; only the browse API is
        # gated.
        browseOidc = pocketIdIssuer;
      };
    };

    systemd = {
      # The Pusher creates a missing database, and its startup orphan sweep
      # then deletes every bucket object older than 24 h. A missing index
      # must leave garret stopped until the operator restores one or creates
      # an empty one on purpose (docs/runbooks/garret.md).
      services = let
        indexPresent = {ConditionPathExists = config.services.garret.pusher.dbPath;};
      in {
        # garret's sizing rule (spec 10): 2 x maxInFlightBytes + per-upload decoder
        # window and preamble = 2 x 384 MiB + 16 x 9 MiB = 912 MiB, plus headroom.
        garret-pusher = {
          unitConfig = indexPresent;
          serviceConfig.MemoryMax = "960M";
        };
        garret-puller = {
          unitConfig = indexPresent;
          serviceConfig.MemoryMax = "192M";
        };
        # Ordering only: a backup must never start a Pusher stopped for a restore.
        restic-backups-garret.after = ["garret-pusher.service"];
      };

      # The root disk holds the only live index, so the interval is the
      # pushes a lost node forgets.
      timers.restic-backups-garret.timerConfig = {
        OnCalendar = lib.mkForce "00/6:00";
        RandomizedDelaySec = lib.mkForce "15m";
      };
    };

    services.caddy = {
      enable = true;
      # appsec is not available here, and clients legitimately fetch in
      # high-volume bursts. garret closes a connection idle for 30 s, so
      # Caddy must drop its pooled upstream connections first or reuse one
      # mid-close (502).
      virtualHosts."cache.jeiang.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:${toString pullerPort} {
          transport http {
            keepalive 20s
          }
        }
      '';
      # MUST stay DNS-only in Cloudflare: a push is one streaming PUT of a
      # whole NAR and Cloudflare 413s bodies over 100 MB on the free plan.
      virtualHosts."cache-push.jeiang.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:${toString pusherPort} {
          transport http {
            keepalive 20s
            read_timeout 15m
            write_timeout 15m
            response_header_timeout 15m
          }
        }
      '';
    };

    environment.systemPackages = [garretAdmin];

    # An online copy, so the backup never stops the cache. The Pusher never
    # overwrites a file, hence the rm. The Pusher is Type=notify and signals
    # ready only once the admin socket exists, so ordering after its unit
    # is enough.
    backups.jobs.garret = {
      pauseUnits = [];
      prepareCommand = let
        socket = config.services.garret.pusher.adminSocketPath;
      in ''
        rm -f ${backupFile}
        ${lib.getExe' garretAdmin "garret-admin"} --socket ${socket} backup ${backupFile}
      '';
    };

    sops = {
      secrets = {
        "garret/s3-access-key-id" = {inherit sopsFile;};
        "garret/s3-secret-access-key" = {inherit sopsFile;};
        "garret/puller-s3-access-key-id" = {inherit sopsFile;};
        "garret/puller-s3-secret-access-key" = {inherit sopsFile;};
        # Signing keys are read once at start-up; a secret-only deploy leaves the unit unchanged.
        "garret/signing-key" = {
          inherit sopsFile;
          owner = "garret";
          restartUnits = ["garret-pusher.service"];
        };
      };

      templates."garret-s3.env" = {
        restartUnits = ["garret-pusher.service"];
        content = ''
          AWS_ACCESS_KEY_ID=${config.sops.placeholder."garret/s3-access-key-id"}
          AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."garret/s3-secret-access-key"}
        '';
      };
      templates."garret-puller-s3.env" = {
        restartUnits = ["garret-puller.service"];
        content = ''
          AWS_ACCESS_KEY_ID=${config.sops.placeholder."garret/puller-s3-access-key-id"}
          AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."garret/puller-s3-secret-access-key"}
        '';
      };
    };
  };
}
