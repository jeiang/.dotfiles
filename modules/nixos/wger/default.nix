{self, ...}: {
  flake.nixosModules.wger = {
    config,
    lib,
    pkgs,
    ...
  }: let
    image = "docker.io/wger/server:2.7.0";
    powersyncImage = "docker.io/journeyapps/powersync-service:1.25.0";
    dataDir = "/var/lib/wger";
    siteUrl = "https://wger.jeiang.dev";
    sopsFile = ./secrets.yaml;
    webPort = 8000;
    powersyncPort = 8090;
    redisPort = 6379;
    envFile = config.sops.templates."wger.env".path;
    podman = lib.getExe config.virtualisation.podman.package;

    volumeDirs = {
      unitConfig.RequiresMountsFor = [dataDir];
      # The persistence bind mount lands on top of anything tmpfiles created
      # at activation, so the volume dirs are made at each start.
      serviceConfig.ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o 1000 -g 1000 ${dataDir}/static ${dataDir}/media ${dataDir}/beat";
    };

    environment = {
      SITE_URL = siteUrl;
      CSRF_TRUSTED_ORIGINS = siteUrl;
      X_FORWARDED_PROTO_HEADER_SET = "True";
      USE_X_FORWARDED_HOST = "True";
      NUMBER_OF_PROXIES = "2";
      AXES_IPWARE_PROXY_COUNT = "1";
      AXES_IPWARE_META_PRECEDENCE_ORDER = "HTTP_X_FORWARDED_FOR,REMOTE_ADDR";
      TIME_ZONE = config.time.timeZone;
      TZ = config.time.timeZone;

      DJANGO_DEBUG = "False";
      WGER_USE_GUNICORN = "True";
      WGER_PORT = toString webPort;
      DJANGO_PERFORM_MIGRATIONS = "True";
      DJANGO_COLLECTSTATIC_ON_STARTUP = "True";

      DJANGO_CACHE_BACKEND = "django_redis.cache.RedisCache";
      DJANGO_CACHE_LOCATION = "redis://127.0.0.1:${toString redisPort}/1";
      DJANGO_CACHE_TIMEOUT = "1296000";
      DJANGO_CACHE_CLIENT_CLASS = "django_redis.client.DefaultClient";
      USE_CELERY = "True";
      CELERY_BROKER = "redis://127.0.0.1:${toString redisPort}/2";
      CELERY_BACKEND = "redis://127.0.0.1:${toString redisPort}/2";
      SYNC_EXERCISES_CELERY = "True";
      SYNC_EXERCISE_IMAGES_CELERY = "True";
      SYNC_EXERCISE_VIDEOS_CELERY = "True";
      SYNC_INGREDIENTS_CELERY = "True";
      CACHE_API_EXERCISES_CELERY = "True";

      PS_PORT = toString powersyncPort;
      PS_JWKS_URL = "http://127.0.0.1:${toString webPort}/api/v2/powersync-keys";
      POWERSYNC_CONFIG_PATH = "/config/powersync.yaml";

      ALLOW_REGISTRATION = "False";
      ALLOW_GUEST_USERS = "False";
      # Cloudflare 413s bodies over 100 MB on the free plan.
      ALLOW_UPLOAD_VIDEOS = "False";

      # 127.0.0.1 is the nginx hop below; the header only counts on
      # requests that came through it.
      AUTH_PROXY_HEADER = "HTTP_X_REMOTE_USER";
      AUTH_PROXY_TRUSTED_IPS = "127.0.0.1";
      AUTH_PROXY_CREATE_UNKNOWN_USER = "True";
      AUTH_PROXY_USER_EMAIL_HEADER = "HTTP_X_REMOTE_EMAIL";
      # auth_user.first_name is NOT NULL and the backend passes the name
      # header verbatim, so an unset header makes every user creation fail.
      AUTH_PROXY_USER_NAME_HEADER = "HTTP_X_REMOTE_USER";
    };

    container = extra:
      {
        inherit image environment;
        environmentFiles = [envFile];
        # ponytail: host network so loopback reaches Postgres/Redis/nginx and
        # wger's own AUTH_PROXY_TRUSTED_IPS check sees nginx as 127.0.0.1;
        # move to a podman network + --userns=auto if the uid 1000 mapping
        # (the image's `wger` user lands on the host's uid 1000) becomes a
        # problem.
        extraOptions = ["--network=host"];
      }
      // extra;
  in {
    imports = [self.nixosModules.backups];

    backups.jobs.wger.paths = ["${dataDir}/media" "${dataDir}/backup"];

    virtualisation = {
      podman.enable = true;
      oci-containers = {
        backend = "podman";
        containers = {
          wger-web = container {
            volumes = [
              "${dataDir}/static:/home/wger/static"
              "${dataDir}/media:/home/wger/media"
            ];
          };
          wger-worker = container {
            cmd = ["/start-worker"];
            volumes = ["${dataDir}/media:/home/wger/media"];
            dependsOn = ["wger-web"];
          };
          wger-beat = container {
            cmd = ["/start-beat"];
            volumes = ["${dataDir}/beat:/home/wger/beat"];
            dependsOn = ["wger-worker"];
          };
          wger-powersync = container {
            image = powersyncImage;
            cmd = ["start" "-r" "unified"];
            volumes = ["${./powersync}:/config:ro"];
            dependsOn = ["wger-web"];
          };
        };
      };
    };

    services = {
      postgresql = {
        enable = true;
        settings.wal_level = "logical";
        ensureDatabases = ["wger"];
        ensureUsers = [
          {
            name = "wger";
            ensureDBOwnership = true;
          }
        ];
      };

      redis.servers.wger = {
        enable = true;
        bind = "127.0.0.1";
        port = redisPort;
      };

      nginx = {
        enable = true;
        recommendedProxySettings = true;
        virtualHosts.wger = {
          listen = [
            {
              addr = "0.0.0.0";
              port = self.lib.ports.artemis.wger;
            }
          ];
          extraConfig = "client_max_body_size 20m;";
          locations = {
            "/" = {
              proxyPass = "http://127.0.0.1:${toString webPort}";
              proxyWebsockets = true;
            };
            "/ps/" = {
              proxyPass = "http://127.0.0.1:${toString powersyncPort}/";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_buffering off;
                proxy_request_buffering off;
                proxy_read_timeout 1d;
                proxy_send_timeout 1d;
              '';
            };
            "/static/" = {
              alias = "${dataDir}/static/";
              extraConfig = ''add_header Cache-Control "public, max-age=31536000, immutable" always;'';
            };
            "/media/".alias = "${dataDir}/media/";
          };
        };
      };
    };

    systemd = {
      services = {
        wger-db-setup = {
          after = ["postgresql-setup.service"];
          requires = ["postgresql-setup.service"];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            RemainAfterExit = true;
          };
          path = [config.services.postgresql.package];
          script = ''
            psql -v ON_ERROR_STOP=1 \
              -v wger_pw="$(cat ${config.sops.secrets."wger/db-password".path})" \
              -v ps_pw="$(cat ${config.sops.secrets."wger/powersync-storage-password".path})" \
              -d wger <<'SQL'
            ALTER ROLE wger WITH REPLICATION PASSWORD :'wger_pw';
            DO $$ BEGIN
              IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'powersync_storage') THEN
                CREATE ROLE powersync_storage LOGIN;
              END IF;
            END $$;
            ALTER ROLE powersync_storage WITH PASSWORD :'ps_pw';
            CREATE SCHEMA IF NOT EXISTS powersync AUTHORIZATION powersync_storage;
            DO $$ BEGIN
              IF NOT EXISTS (SELECT FROM pg_publication WHERE pubname = 'powersync') THEN
                CREATE PUBLICATION powersync FOR ALL TABLES;
              END IF;
            END $$;
            SQL
          '';
        };

        podman-wger-web =
          volumeDirs
          // {
            after = ["wger-db-setup.service" "redis-wger.service"];
            requires = ["wger-db-setup.service" "redis-wger.service"];
          };
        podman-wger-worker = volumeDirs;
        podman-wger-beat = volumeDirs;

        wger-pg-dump = {
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o postgres -g postgres -m 0750 ${dataDir}/backup";
          };
          path = [config.services.postgresql.package];
          script = "pg_dump -Fc wger > ${dataDir}/backup/wger.dump";
        };

        restic-backups-wger = {
          after = ["wger-pg-dump.service"];
          requires = ["wger-pg-dump.service"];
        };

        wger-powersync-compact = {
          startAt = "03:00";
          serviceConfig.Type = "oneshot";
          script = ''
            ${podman} run --rm --network=host \
              --env-file ${envFile} \
              ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "-e ${k}=${lib.escapeShellArg v}") environment)} \
              -v ${./powersync}:/config:ro \
              ${powersyncImage} compact
          '';
        };
      };
    };

    sops = {
      secrets = {
        "wger/secret-key" = {inherit sopsFile;};
        "wger/jwt-public-key" = {inherit sopsFile;};
        "wger/jwt-private-key" = {inherit sopsFile;};
        "wger/db-password" = {
          inherit sopsFile;
          owner = "postgres";
        };
        "wger/powersync-storage-password" = {
          inherit sopsFile;
          owner = "postgres";
        };
      };
      templates."wger.env" = {
        restartUnits = ["podman-wger-web.service" "podman-wger-worker.service" "podman-wger-beat.service" "podman-wger-powersync.service"];
        content = ''
          SECRET_KEY=${config.sops.placeholder."wger/secret-key"}
          JWT_PUBLIC_KEY=${config.sops.placeholder."wger/jwt-public-key"}
          JWT_PRIVATE_KEY=${config.sops.placeholder."wger/jwt-private-key"}
          PS_DATABASE_URI=postgres://wger:${config.sops.placeholder."wger/db-password"}@127.0.0.1:5432/wger
          PS_STORAGE_PG_URI=postgres://powersync_storage:${config.sops.placeholder."wger/powersync-storage-password"}@127.0.0.1:5432/wger
        '';
      };
    };

    persistence.directories = [
      dataDir
      "/var/lib/postgresql"
      "/var/lib/containers"
    ];
  };
}
