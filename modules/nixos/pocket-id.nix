_: {
  # Pocket ID (idp) for legion-node2, behind the edge at auth.jeiang.dev
  # (modules/nixos/edge/default.nix `auth.jeiang.dev { reverse_proxy
  # ${node2}:1411 }`). First-party `services.pocket-id` (DESIGN.md Service
  # Ownership: prefer a first-party module when it fits) -- unlike
  # netbird-server/proxy, no custom systemd unit is needed here. Imported
  # only for the inventory node that places `pocket-id`
  # (modules/hosts/legion/default.nix, same optional-import pattern as
  # netbird-server/netbird-proxy).
  flake.nixosModules.pocket-id = {config, ...}: let
    # legion-node2's declared Volume mountpoint
    # (modules/hosts/legion/_service-inventory.nix pocket-id.volume).
    # WorkingDirectory=dataDir (nixpkgs' services.pocket-id systemd unit),
    # so the app's relative default paths (DB_CONNECTION_STRING
    # "data/pocket-id.db", UPLOAD_PATH "data/uploads") resolve to
    # ${dataDir}/data/*.
    dataDir = "/mnt/pocket-id";
  in {
    services.pocket-id = {
      enable = true;
      inherit dataDir;
      settings = {
        APP_URL = "https://auth.jeiang.dev";
        # Edge Caddy terminates TLS and forwards here, hence
        # TRUST_PROXY=true.
        TRUST_PROXY = true;
      };
      # ENCRYPTION_KEY / STATIC_API_KEY delivered as plain env vars through
      # the sops-templated environmentFile below, same pattern as every
      # other module in this repo (modules/nixos/netbird-server/*.nix) --
      # simpler than the nixpkgs module's alternate `_FILE`-suffix
      # convention (backend/internal/common/env_config.go
      # `options:"file"` fields), which would additionally require
      # granting the pocket-id service user read access to the raw sops
      # secret file. Secret generation: `pocket-id-encryption-key`
      # (openssl rand -base64 32, keep stable) and
      # `pocket-id-static-api-key` (openssl rand -hex 32).
      #
      # SMTP is intentionally NOT wired here. An older Pocket ID release
      # (v2.9.0) configures SMTP_HOST/PORT/FROM/USER/PASSWORD_FILE/TLS as
      # env vars, but the nixpkgs-pinned v2.10.0 binary has none of those
      # fields left in EnvConfigSchema -- confirmed against source
      # (backend/internal/common/env_config.go has no SMTP_* env at all;
      # backend/internal/service/email_service.go reads
      # dbConfig.SmtpHost/SmtpPassword/etc instead, and
      # backend/internal/model/app_config.go shows those are DB-backed
      # `AppConfigVariable` rows, admin-UI/API configured, not env vars).
      # This is the v1->v2 migration the module's own deprecation warnings
      # reference. Since Pocket ID's data is retained end-to-end, an SMTP
      # config already set previously travels with the DB; there is
      # nothing this module can express for a from-scratch SMTP setup.
      # SMTP must be re-entered via the admin UI, or an older pocket-id
      # version pin used to keep env-var SMTP config.
      environmentFile = config.sops.templates."pocket-id.env".path;
    };

    # Overrides the nixpkgs services.pocket-id unit (fixed "pocket-id"
    # user, not DynamicUser), same as every other MemoryMax override in
    # this repo.
    systemd.services.pocket-id.serviceConfig.MemoryMax = "256M";

    # Mount guard (Codex review C2): refuse to start unless ${dataDir} is
    # actually mounted, so a missing/late Volume never silently
    # initializes a fresh sqlite DB on the root disk instead of the
    # retained data.
    systemd.services.pocket-id.unitConfig = {
      RequiresMountsFor = [dataDir];
      ConditionPathIsMountPoint = dataDir;
    };

    sops = {
      secrets = {
        "pocket-id/encryption-key" = {};
        "pocket-id/static-api-key" = {};
      };
      templates."pocket-id.env" = {
        owner = config.services.pocket-id.user;
        content = ''
          ENCRYPTION_KEY=${config.sops.placeholder."pocket-id/encryption-key"}
          STATIC_API_KEY=${config.sops.placeholder."pocket-id/static-api-key"}
        '';
      };
    };
  };
}
