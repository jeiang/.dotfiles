{
  self,
  inputs,
  ...
}: {
  # docs/MIGRATION.md piece 5.1: Attic (jeiang/attic fork, OIDC-enabled) for
  # legion-node4, behind the edge at attic.jeiang.dev
  # (modules/nixos/edge/default.nix `attic.jeiang.dev { reverse_proxy
  # ${node4}:8080 ... }`). First-party `services.atticd`, imported from the
  # fork's own module (inputs.attic.nixosModules.atticd) rather than
  # nixpkgs' upstream one: the fork's Rust binary has an extra `oidc` config
  # section stock attic lacks, and the module's `checked-attic-server.toml`
  # build step runs `${cfg.package}/bin/atticd --mode check-config` against
  # whichever module owns `settings` -- pairing the fork's module with the
  # fork's `attic-server` package (confirmed present via `nix flake show`
  # against the pinned inputs.attic rev) keeps the config schema and binary
  # in lockstep. Stateless (Confirmed Decisions: external managed Postgres +
  # Mega S4, no local state) -- no Volume, no backupSet; the
  # modules/hosts/legion/_service-inventory.nix `attic` entry already
  # reflects this (stateful = false, no volume).
  flake.nixosModules.attic = {
    config,
    lib,
    pkgs,
    ...
  }: let
    system = pkgs.stdenv.hostPlatform.system;
    serverPort = 8080; # matches modules/nixos/edge/default.nix node4:8080
  in {
    imports = [inputs.attic.nixosModules.atticd];

    services.atticd = {
      enable = true;
      package = self.packages.${system}.attic-server;

      # Piece 5.1: ATTIC_SERVER_DATABASE_URL (external managed Postgres),
      # AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY (Mega S4), and
      # ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64 (signing key) all arrive as
      # plain env vars through this file -- none of the four are readable
      # from `settings` below, so none land in the store-rendered
      # server.toml (checked by the `settings` override immediately below).
      environmentFile = config.sops.templates."attic.env".path;

      # `lib.mkForce`, not a plain assignment: the fork's atticd.nix (like
      # upstream nixpkgs) sets `settings.database.url = lib.mkDefault
      # "sqlite:///var/lib/atticd/server.db?mode=rwc"` and `settings.storage
      # = lib.mkDefault { type = "local"; ... }` unconditionally whenever
      # the service is enabled. `settings` uses a freeform TOML type, which
      # deep-merges nested attrs leaf-by-leaf across every module that
      # contributes to it -- a plain `services.atticd.settings.database.url
      # = ...` here would only add a HIGHER-priority value at that same
      # leaf, and simply *omitting* database.url wouldn't remove the
      # module's own mkDefault leaf either (verified empirically: `nix
      # eval` against a minimal `lib.evalModules` reproduction of this
      # exact freeform-merge shape). The only way to make server/src/config.rs's
      # `#[serde(default = "load_database_url_from_env")]` fallback fire
      # (i.e. to get a rendered server.toml with NO `database.url` key at
      # all, so ATTIC_SERVER_DATABASE_URL from the env file above is what
      # the server actually reads) is to replace the *entire* `settings`
      # value at the option level with `lib.mkForce`, which -- unlike a
      # nested leaf override -- wins outright over every other module's
      # contribution instead of merging with it. That means every setting
      # the fork module would otherwise default (database.mmap-size,
      # storage, ...) must be spelled out explicitly below.
      settings = lib.mkForce {
        listen = "0.0.0.0:${toString serverPort}";
        allowed-hosts = ["attic.jeiang.dev"];
        api-endpoint = "https://attic.jeiang.dev/";
        require-proof-of-possession = true;

        # Concurrency/memory tuning carried from the cluster
        # (k8s-manifests attic/values.yaml, docs/MIGRATION.md RAM notes):
        # 16 concurrent authenticated uploads, but chunk inserts are
        # throttled to 2 concurrent (SQLite write-lock contention bridge,
        # per the chart's own comment) to fit the MemoryMax below.
        max-concurrent-uploads = 16;
        max-concurrent-chunk-uploads = 2;

        database = {
          # url deliberately absent -- see the mkForce comment above.
          mmap-size = 134217728; # 128 MiB, matches the chart
          max-connections = 32;
        };

        storage = {
          type = "s3";
          region = "ca-montreal";
          bucket = "attic";
          endpoint = "https://s3.ca-montreal.megas4.com";
          # credentials deliberately absent: server/src/storage/s3.rs falls
          # back to AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY from the
          # environment when unset, supplied by the env file above.
        };

        chunking = {
          nar-size-threshold = 65536;
          min-size = 16384;
          avg-size = 65536;
          max-size = 262144;
        };

        compression = {
          type = "zstd";
          level = 3;
        };

        garbage-collection = {
          interval = "12 hours";
          default-retention-period = "0 seconds";
        };

        # OIDC provider config mirrors the live cluster config
        # (k8s-manifests attic/values.yaml `oidc.githubActions`/
        # `oidc.pocketId`, rendered 1:1 by attic/templates/configmap.yaml
        # into `[[oidc.providers]]` blocks) -- none of these values are
        # secret (issuer/jwks-url/audience are public OIDC metadata), so
        # they're safe in the store-rendered settings.
        oidc.providers = [
          {
            name = "github-actions";
            mode = "github-actions";
            issuer = "https://token.actions.githubusercontent.com";
            audience = "https://attic.jeiang.dev/";
            jwks-url = "https://token.actions.githubusercontent.com/.well-known/jwks";
            token-validity = "12 hours";
            rules = [
              {
                claims = {
                  repository_owner_id = "31970261";
                  ref_protected = "true";
                };
                caches.default = {
                  pull = true;
                  push = true;
                  delete = false;
                  create = false;
                  configure = false;
                  configure-retention = false;
                  destroy = false;
                };
              }
              {
                claims.repository_owner_id = "31970261";
                caches.default = {
                  pull = true;
                  push = false;
                  delete = false;
                  create = false;
                  configure = false;
                  configure-retention = false;
                  destroy = false;
                };
              }
            ];
          }
          {
            name = "pocketid";
            display-name = "Pocket ID";
            mode = "authorization-code-pkce";
            issuer = "https://auth.jeiang.dev";
            audience = "0304a563-8b46-4731-9eb0-224e8f0d1c7b";
            jwks-url = "https://auth.jeiang.dev/.well-known/jwks.json";
            authorization-endpoint = "https://auth.jeiang.dev/authorize";
            token-endpoint = "https://auth.jeiang.dev/api/oidc/token";
            scopes = ["openid" "profile" "groups"];
            token-validity = "12 hours";
            rules = [
              {
                claims.attic_role = "admin";
                caches."*" = {
                  pull = true;
                  push = true;
                  delete = true;
                  create = true;
                  configure = true;
                  configure-retention = true;
                  destroy = true;
                };
              }
              {
                claims.attic_role = "writer";
                caches."*" = {
                  pull = true;
                  push = true;
                  delete = false;
                  create = false;
                  configure = false;
                  configure-retention = false;
                  destroy = false;
                };
              }
              {
                claims.attic_role = "reader";
                caches."*" = {
                  pull = true;
                  push = false;
                  delete = false;
                  create = false;
                  configure = false;
                  configure-retention = false;
                  destroy = false;
                };
              }
            ];
          }
        ];
      };
    };

    # docs/MIGRATION.md RAM notes: "Attic was tuned to fit a 512 Mi limit"
    # in the cluster, but the *live* chart (k8s-manifests attic/values.yaml
    # `resources.limits.memory`) actually ran 768Mi. Piece 0.6 capacity
    # audit raises this to 896M (measured steady-state, docs/MIGRATION.md).
    systemd.services.atticd.serviceConfig.MemoryMax = "896M";

    sops = {
      secrets = {
        "attic/database-url" = {};
        "attic/s3-access-key-id" = {};
        "attic/s3-secret-access-key" = {};
        "attic/token-rs256-secret-base64" = {};
      };

      # No `owner` set: services.atticd runs with DynamicUser = true (the
      # fork module, same as nixpkgs upstream), so -- same precedent as
      # modules/nixos/netbird-server/default.nix's netbird-relay -- the
      # EnvironmentFile is read by systemd (PID 1, root) before it drops
      # privileges to the dynamically allocated UID; it never needs to be
      # readable by a named service user.
      templates."attic.env".content = ''
        ATTIC_SERVER_DATABASE_URL=${config.sops.placeholder."attic/database-url"}
        AWS_ACCESS_KEY_ID=${config.sops.placeholder."attic/s3-access-key-id"}
        AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."attic/s3-secret-access-key"}
        ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=${config.sops.placeholder."attic/token-rs256-secret-base64"}
      '';
    };
  };
}
