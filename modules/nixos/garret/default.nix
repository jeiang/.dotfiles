{
  self,
  inputs,
  ...
}: {
  # garret (jeiang/garret) for legion-node4, the fleet's Nix binary cache
  # and Attic's replacement (docs/adr/0013). Two units from two upstream
  # modules, colocated on one host over a shared SQLite index:
  #
  #   - Pusher  -- OIDC-authenticated push API, behind the edge at
  #                cache-push.jeiang.dev (must stay grey-clouded: a push is
  #                one streaming PUT of a whole compressed NAR and
  #                Cloudflare 413s bodies > 100 MB on free).
  #   - Puller  -- anonymous substituter at cache.jeiang.dev. NAR requests
  #                answer 302 to a presigned S3 URL, so NAR bytes never
  #                traverse the edge; only narinfo does.
  #
  # The Pusher is deliberately NOT on its upstream default of 8080: that
  # port belonged to atticd while the two ran side by side, and moving it
  # back now would only churn the edge routes and firewall for nothing.
  flake.nixosModules.garret = {
    config,
    pkgs,
    ...
  }: let
    # legion-node4's declared Volume mountpoint
    # (modules/hosts/legion/_service-inventory.nix garret.volume). The
    # SQLite index lives here rather than the upstream default
    # /var/lib/garret: it is the only record of what is in the S3 bucket,
    # so losing it strands every stored object as an unreclaimable orphan.
    dataDir = "/mnt/garret";
    dbPath = "${dataDir}/garret.db";

    pusherPort = self.lib.ports.legion-node4.garret-pusher;
    pullerPort = self.lib.ports.legion-node4.garret-puller;
    pusherMetricsPort = self.lib.ports.legion-node4.garret-pusher-metrics;
    pullerMetricsPort = self.lib.ports.legion-node4.garret-puller-metrics;

    # Metrics listeners bind this node's private address rather than
    # loopback (the upstream default) so legion-node3's VictoriaMetrics can
    # scrape them cross-node over the trusted enp7s0 interface, exactly
    # like every other backend scrape in modules/nixos/monitoring.
    privateIPv4 = self.lib.legionNodes.legion-node4.privateIPv4;

    sopsFile = ./secrets.yaml;

    # Pocket ID OIDC client registered for garret. Operator prerequisite
    # (docs/runbooks/garret.md): create the client, restrict it to the
    # admin group in Pocket ID's own UI, and paste its id here. The
    # assertion below refuses to build while the placeholder is in place --
    # a wrong audience would otherwise fail closed at runtime with nothing
    # in the config to point at.
    pocketIdAudience = "384a5193-a040-4025-a8d3-7815d6269ca2";

    # Shared by both units: garret grants no read/write tiers, so an
    # accepted token means full push on the Pusher. Authorization lives at
    # the issuer wherever possible (garret ADR-0003) -- hence the empty
    # allowed_groups on Pocket ID, whose per-client group restriction is
    # the actual gate.
    pocketIdIssuer = {
      issuer = "https://auth.jeiang.dev";
      audience = pocketIdAudience;
      # Skips discovery; the same JWKS URL Attic's pocketid provider used.
      jwks_url = "https://auth.jeiang.dev/.well-known/jwks.json";
      allowed_groups = [];
    };

    s3 = {
      bucket = "garret";
      endpointUrl = "https://s3.ca-montreal.megas4.com";
      region = "ca-montreal";
      # Upstream default; flip to false if MEGA S4 rejects path-style
      # addressing.
      pathStyle = true;
      credentialsFile = config.sops.templates."garret-s3.env".path;
    };
  in {
    imports = [
      inputs.garret.nixosModules.pusher
      inputs.garret.nixosModules.puller
      # The store watcher (inputs.garret.nixosModules.watcher) is
      # deliberately NOT imported: it runs on build machines rather than
      # the cache host, needs a Pocket ID confidential client per machine,
      # and is out of scope for the attic replacement (docs/adr/0013).
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

        # The one thing the Pusher cannot infer about itself. Advertised by
        # `/api/v1/discovery` so `garret login` writes a complete client
        # config; without it `garret use`, `list` and `tree` stay
        # unconfigured on every machine that logs in.
        pullerEndpoint = "https://cache.jeiang.dev";

        # 250 GiB budget with LRU eviction between the watermarks. Attic's
        # equivalent was time-based with a zero retention period, i.e. it
        # never evicted anything; a quota is what keeps the MEGA S4 bill
        # bounded now that nothing else does.
        quotaBytes = 268435456000;
        watermarks = {
          high = 0.95;
          low = 0.85;
        };

        # Sized for a 2 vCPU / 1.9 GiB node shared with actual and hath.
        # `maxInFlightBytes` is the real memory bound: garret turns
        # it into a process-wide semaphore over part-sized buffers
        # (garret-server/src/storage.rs UploadLimits::new), so it holds
        # regardless of how many uploads arrive. `maxConcurrentUploads` is
        # only the point at which excess requests are shed with 429.
        # `partSize` doubles as the single-PutObject threshold and must
        # stay at or above S3's 5 MiB multipart minimum.
        limits = {
          maxConcurrentUploads = 16;
          maxInFlightBytes = 402653184; # 384 MiB
          partSize = 33554432; # 32 MiB
          maxPartsInFlight = 2;
        };

        oidc = [
          {
            # GitHub Actions. Attic granted push on `ref_protected =
            # "true"` (any protected branch of any repo owned by this
            # account); garret implements no such check
            # (garret-server/src/auth.rs `authorize`), only trailing-`*`
            # globs against the `ref` claim. `refs/heads/main` is the
            # closest equivalent for this repo, and differs in principle:
            # an unprotected `main` in another jeiang-owned repo would now
            # be allowed to push where attic would have refused it.
            issuer = "https://token.actions.githubusercontent.com";
            audience = "https://cache-push.jeiang.dev/";
            jwks_url = "https://token.actions.githubusercontent.com/.well-known/jwks";
            # Immutable owner id, not the name: names are renameable.
            github_owner_id = "31970261";
            ref_patterns = ["refs/heads/main"];
            allowed_groups = [];
          }
          # `client_id` lives here rather than in `pocketIdIssuer` itself for
          # two reasons: the Puller's `browseOidc` submodule has no such
          # option (eval fails if it is set there), and discovery advertises
          # the *first* issuer that sets one -- so exactly one issuer should,
          # and it must be the human one. Without it `/api/v1/discovery`
          # returns `"oidc": null` and `garret login` fails with "the
          # server's discovery document has no oidc section". Pocket ID uses
          # the client id as the audience, hence the same value twice.
          (pocketIdIssuer // {client_id = pocketIdAudience;})
        ];
      };

      puller = {
        enable = true;
        listen = "0.0.0.0:${toString pullerPort}";
        metricsListen = "${privateIPv4}:${toString pullerMetricsPort}";
        inherit dbPath s3;
        # Browse API (list/detail/tree/referrers), gated by the same Pocket
        # ID client as the Pusher. narinfo and NAR routes stay anonymous
        # regardless, so every machine's nix.conf keeps working untouched.
        browseOidc = pocketIdIssuer;
      };
    };

    # The Volume mount is `nofail` (modules/hosts/legion/default.nix
    # fileSystems derivation), so without a guard a late or missing Volume
    # would silently initialize a fresh, empty index on the root disk --
    # which reads as "the cache is empty" while every object in S3 becomes
    # unreferenced. Same guard every other Volume-backed service uses.
    systemd.services = let
      # A freshly formatted ext4 Volume's root is root:root 0755, and both
      # units run as the unprivileged `garret` user the upstream modules
      # create -- so without this they cannot create the database and exit
      # with SQLite error 14.
      #
      # Deliberately NOT a `systemd.tmpfiles.rules` entry:
      # systemd-tmpfiles-setup.service is not ordered after this
      # Volume's mount unit, so on the activation that first mounts the
      # Volume it runs against the empty pre-mount directory and the mount
      # then hides its work (observed on the first legion-node4 deploy).
      # modules/nixos/hath.nix and netbird-server/default.nix used to use
      # tmpfiles here and only escaped it because their Volumes were
      # already mounted and owned from an earlier deploy; both now use this
      # same ExecStartPre shape. An ExecStartPre inherits the unit's own `RequiresMountsFor`, so it cannot
      # run before the mount exists, and it re-asserts ownership on every
      # start -- which also covers replacing or reformatting the Volume.
      #
      # The `+` prefix runs it as root despite the unit's User=garret.
      ensureDataDir = "+${pkgs.coreutils}/bin/install -d -o garret -g garret -m 0750 ${dataDir}";
    in {
      # MemoryMax: 896M + 192M on a 1922 MiB node, leaving room for
      # actual (320M) and hath. The Pusher absorbs the 256M that atticd
      # held before it retired -- it is the unit that buffers uploads
      # (`maxInFlightBytes` above is 384 MiB of that ceiling), while the
      # Puller only serves narinfo from SQLite and signs redirect URLs, so
      # it needs very little.
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
        # Read directly by the Pusher as `signing_key_files`, so unlike the
        # S3 credentials it needs an owner: both units run as the named
        # `garret` user (the upstream modules set DynamicUser = false), not
        # as root via systemd's EnvironmentFile handling.
        #
        # restartUnits is load-bearing, not tidiness: the Pusher reads its
        # signing keys once at start-up, and a deploy that only changes the
        # secret leaves both unit definitions byte-identical -- so without
        # this, sops rewrites /run/secrets and the running process keeps
        # signing with the previous key. Observed exactly that: every path
        # pushed after a key change kept the old signature, and no consumer
        # could verify it against the trusted public key.
        "garret/signing-key" = {
          inherit sopsFile;
          owner = "garret";
          restartUnits = ["garret-pusher.service"];
        };
      };

      # No `owner`: an EnvironmentFile is read by systemd (PID 1, root)
      # before it drops privileges, same precedent as
      # netbird-server's netbird-relay.
      #
      # Both units get restartUnits for the same reason as the signing key
      # above: an EnvironmentFile is read once at start-up, so rotated S3
      # credentials would otherwise not take effect until something else
      # happened to restart them.
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
