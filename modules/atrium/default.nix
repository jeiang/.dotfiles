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
  enabled = false;
in {
  flake.lib = {
    atriumWebPort = webPort;
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
    off = names: lib.genAttrs names (_: {enable = false;});
  in {
    imports = [inputs.atrium.nixosModules.default];

    services.atrium = {
      enable = true;
      mode = "live";
      environmentFiles = [config.sops.secrets."atrium/env".path];
      modelServerUnits = llamaServer.units;
      chatUrl = "http://127.0.0.1:${toString chatPort}/v1";
      embedUrl = "http://127.0.0.1:${toString embedPort}/v1";
      publicUrl = "https://${atriumHostname}";
      grafanaUrl = self.lib.grafanaMeshUrl;
      inherit icloudAppleId;
      web = {
        port = webPort;
        allowedHost = atriumHostname;
        local.port = webLocalPort;
      };
      ntfy = {
        url = self.lib.ntfyBaseUrl;
        topic = self.lib.ntfyAtriumTopic;
        mediaTopic = self.lib.ntfyMediaTopic;
      };
      media = {
        enable = true;
        group = self.lib.mediaGroup;
        root = self.lib.mediaDir;
        qbittorrentUrl = "http://127.0.0.1:${toString self.lib.qbittorrentWebuiPort}";
        moviesUrl = "http://${self.deploy.nodes.artemis.hostname}:${toString self.lib.mediaMoviesPort}";
        tvUrl = "http://${self.deploy.nodes.artemis.hostname}:${toString self.lib.mediaTvPort}";
      };
      extraEnvironment.ATRIUM_NOTION_WIKI_ROOT = "3f47a0cdb63e812c9030ffb39de864be";
    };

    gaming.pauseUnits = lib.mkIf enabled llamaServer.units;

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

    sops.secrets."atrium/env" = {
      sopsFile = ./secrets.yaml;
      mode = "0400";
      restartUnits = ["atrium-agent-scheduler.service" "atrium-notion-sync.service" "atrium-vdirsyncer-sync.service" "atrium-watch.service" "atrium-web.service" "atrium-web-local.service"];
    };

    systemd = {
      timers = lib.mkIf (!enabled) (off ["atrium-sync" "atrium-notion-sync" "atrium-scan" "atrium-vdirsyncer-sync" "atrium-backup"]);
      sockets = lib.mkIf (!enabled) (off ["atrium-codemode"]);

      services =
        llamaServer.services
        // lib.optionalAttrs (!enabled) (off ["atrium-llm" "atrium-embed" "atrium-watch" "atrium-agent-scheduler" "atrium-web" "atrium-web-local"]);
    };
  };
}
