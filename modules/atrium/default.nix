{
  self,
  inputs,
  ...
}: let
  icloudAppleId = "aidan@aidanpinard.co";
  stateDir = "/var/lib/atrium";
  chatPort = 8187;
  embedPort = 8188;
  webPort = 8480;
  webLocalPort = webPort + 1;
  atriumHostname = "atrium.jeiang.dev";
  appUnits = ["atrium-agent-scheduler.service" "atrium-notion-sync.service" "atrium-dav-sync.service" "atrium-watch.service" "atrium-web.service" "atrium-web-local.service"];
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
    llamaServer = self.lib.llamaServer {
      inherit lib pkgs;
      name = "atrium";
      modelsDir = "${stateDir}/cache/models";
      servers = {
        llm = {
          description = "Qwen3.5-9B chat server for atrium";
          model = models.qwen35;
          port = chatPort;
          args = [
            "--ctx-size"
            "8192"
            "--jinja"
            "--chat-template-kwargs"
            (builtins.toJSON {enable_thinking = false;})
          ];
        };
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
  in {
    imports = [inputs.atrium.nixosModules.default];

    services.atrium = {
      enable = true;
      environmentFiles = [(secret "env")];
      secretFiles = {
        "db.key" = secret "db-key";
        "notion.notion_token" = secret "notion-token";
        "grafana.grafana_viewer_token" = secret "grafana-viewer-token";
        "media.media_tmdb_token" = secret "tmdb-token";
      };
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
      modelServerUnits = llamaServer.units;
      port = webPort;
      web = {
        auth = "proxy+oidc";
        allowedHost = atriumHostname;
        local.port = webLocalPort;
      };
      media = {
        enable = true;
        group = self.lib.mediaGroup;
      };
      backup = {
        enable = true;
        directory = "${stateDir}/backups";
      };
      observability.tracesEndpoint = "${self.lib.otlpTracesEndpoint config.networking.hostName}/v1/traces";
      settings = {
        core.public_url = "https://${atriumHostname}";
        core.ops_listen = "${self.lib.netbirdPeers.artemis}:${toString self.lib.atriumOpsPort}";
        mail = {
          mail_mode = "live";
          mail_chat_url = "http://127.0.0.1:${toString chatPort}/v1";
          mail_embed_url = "http://127.0.0.1:${toString embedPort}/v1";
        };
        calendar.icloud_apple_id = icloudAppleId;
        grafana.grafana_url = self.lib.grafanaMeshUrl;
        notify.webpush_subject = "mailto:aidan@aidanpinard.co";
        media = {
          media_root = self.lib.mediaDir;
          media_qbittorrent_url = "http://127.0.0.1:${toString self.lib.qbittorrentWebuiPort}";
          media_movies_url = "http://${self.deploy.nodes.artemis.hostname}:${toString self.lib.mediaMoviesPort}";
          media_tv_url = "http://${self.deploy.nodes.artemis.hostname}:${toString self.lib.mediaTvPort}";
        };
        notion.wiki_root = "3f47a0cdb63e812c9030ffb39de864be";
      };
    };

    gaming.pauseUnits = llamaServer.units;

    persistence.directories = [
      {
        directory = stateDir;
        user = "atrium";
        group = "atrium";
        mode = "0750";
      }
    ];
    backups.persist = {
      paths = [stateDir];
      exclude = ["${stateDir}/cache"];
    };

    sops.secrets = lib.genAttrs (map (name: "atrium/${name}") ["env" "db-key" "notion-token" "grafana-viewer-token" "tmdb-token" "icloud-app-password" "gmail-app-password"]) (_: {
      sopsFile = ./secrets.yaml;
      mode = "0400";
      restartUnits = appUnits;
    });

    systemd.services = llamaServer.services;
  };
}
