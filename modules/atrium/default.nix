{
  self,
  inputs,
  ...
}: let
  icloudAppleId = "aidan@aidanpinard.co";
  stateDir = "/var/lib/atrium";
  agentStateDir = "/var/lib/atrium-media-agent";
  embedPort = 8188;
  webPort = 8480;
  emergencyPort = webPort + 1;
  atriumHostname = "atrium.jeiang.dev";
  # Pocket ID client of atrium: the web sign-in and the iOS app share it.
  oidcClientId = "91089791-ffe4-4826-b616-2ce9f9c0eaa7";
in {
  flake.lib = {
    atriumWebPort = webPort;
    atriumOpsPort = 9180;
    inherit atriumHostname;
  };

  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: let
    models = self.lib.llamaModels;
    # Embedding server only: the local chat server is retired in v3 (mail
    # classification uses the service/anthropic connection).
    llamaServer = self.lib.llamaServer {
      inherit lib pkgs;
      name = "atrium";
      modelsDir = "${stateDir}/cache/models";
      servers = {
        embed = {
          description = "EmbeddingGemma 2 embedding server for atrium";
          model = models.embeddinggemma;
          port = embedPort;
          args = [
            "--embedding"
            "--ctx-size"
            "2048"
            "--batch-size"
            "2048"
            "--ubatch-size"
            "2048"
          ];
        };
      };
    };
    secret = name: config.sops.secrets."atrium/${name}".path;
    # atrium.service and the media agent read these; a rotation restarts both.
    appUnits = ["atrium.service" "atrium-media-agent.service"];
  in {
    imports = [inputs.atrium.nixosModules.default];

    services.atrium = {
      enable = true;
      database.keyFile = secret "db-key";
      mailAccounts = {
        icloud = {
          preset = "icloud";
          login = icloudAppleId;
          passwordFile = secret "icloud-app-password";
        };
        gmail = {
          preset = "gmail";
          login = "otakuman86@gmail.com";
          passwordFile = secret "gmail-app-password";
        };
      };
      embeddingServerUnits = llamaServer.units;
      port = webPort;
      web = {
        # Pinned: v3 also defaults to oidc, but the host states it.
        auth = "oidc";
        allowedHost = atriumHostname;
        emergency.port = emergencyPort;
        # alda's Caddy overwrites CF-Connecting-IP with the client address it resolved.
        trustedProxyCidrs = ["${self.lib.netbirdPeers.alda}/32"];
      };
      host = {
        core.public_url = "https://${atriumHostname}";
        core.ops_listen = "${self.lib.netbirdPeers.artemis}:${toString self.lib.atriumOpsPort}";
        grafana.ops_hosts = lib.concatStringsSep "," self.lib.nodeExporterHosts;
        media.media_download_path_prefix = self.lib.mediaDownloadDir;
      };
      connections = {
        "service/anthropic" = {
          kind = "service/anthropic";
          capabilities = ["models"];
          credentialFiles.api_key = secret "anthropic-api-key";
        };
        "service/oidc" = {
          kind = "service/oidc";
          config = {
            preset = "pocket_id";
            issuer = self.lib.pocketIdUrl;
            client_id = oidcClientId;
            api_client_id = oidcClientId;
            access_groups = "atrium_access,atrium_admin";
          };
          capabilities = ["discovery" "client_auth"];
          credentialFiles.client_secret = secret "oidc-client-secret";
        };
        "service/embedding" = {
          kind = "service/embedding";
          config = {
            url = "http://127.0.0.1:${toString embedPort}/v1";
            model = "embeddinggemma";
          };
          capabilities = ["embeddings"];
        };
        "service/grafana" = {
          kind = "service/grafana";
          config = {
            url = self.lib.grafanaMeshUrl;
            metrics_uid = self.lib.grafanaMetricsDatasourceUid;
          };
          capabilities = ["viewer"];
          credentialFiles.viewer_token = secret "grafana-viewer-token";
        };
        "service/notion" = {
          kind = "service/notion";
          config.api = "https://api.notion.com";
          capabilities = ["api"];
          credentialFiles.token = secret "notion-token";
        };
        "service/tmdb" = {
          kind = "service/tmdb";
          capabilities = ["api" "images"];
          credentialFiles.read_token = secret "tmdb-token";
        };
        "service/qbittorrent" = {
          kind = "service/qbittorrent";
          config.url = "http://127.0.0.1:${toString self.lib.qbittorrentWebuiPort}";
          capabilities = ["api"];
        };
      };
      media = {
        enable = true;
        group = self.lib.mediaGroup;
      };
      # The only process with access to the media tree. All four roots sit
      # under self.lib.mediaDir, the one directory it may write.
      mediaAgent = {
        enable = true;
        bearerFile = secret "media-agent-bearer";
        capabilities = ["scan" "thumbnail" "file" "stream"];
        roots = {
          movies = "${self.lib.mediaDir}/movies";
          tv = "${self.lib.mediaDir}/tv";
          downloads = self.lib.mediaDownloadDir;
          import = self.lib.mediaImportDir;
        };
      };
      backup = {
        enable = true;
        directory = "${stateDir}/backups";
      };
      observability.tracesEndpoint = "${self.lib.otlpTracesEndpoint config.networking.hostName}/v1/traces";
    };

    gaming.pauseUnits = llamaServer.units;

    monitoredUnits = ["atrium.service" "atrium-media-agent.service"];

    persistence.directories = [
      {
        directory = stateDir;
        user = "atrium";
        group = "atrium";
        mode = "0750";
      }
      {
        # Filing receipts: losing them loses replay and undo of past filings.
        directory = agentStateDir;
        user = config.services.atrium.mediaAgent.user;
        group = config.services.atrium.mediaAgent.group;
        mode = "0700";
      }
    ];
    backups.persist = {
      paths = [stateDir agentStateDir];
      # cache/: model weights, raw messages, media caches. Lock files hold no data.
      exclude = ["${stateDir}/cache" "${stateDir}/*.lock" "${stateDir}/**/*.lock" "${agentStateDir}/*.lock"];
    };

    sops.secrets = lib.genAttrs (map (name: "atrium/${name}") ["db-key" "anthropic-api-key" "oidc-client-secret" "notion-token" "grafana-viewer-token" "tmdb-token" "icloud-app-password" "gmail-app-password" "media-agent-bearer"]) (_: {
      sopsFile = ./secrets.yaml;
      mode = "0400";
      restartUnits = appUnits;
    });

    systemd.services = llamaServer.services;
  };
}
