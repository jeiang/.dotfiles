{
  self,
  inputs,
  ...
}: let
  icloudAppleId = "aidan@aidanpinard.co";
  stateDirName = "atrium";
  stateDir = "/var/lib/${stateDirName}";
  modelsDir = "${stateDir}/cache/models";
  chatPort = 8187;
  embedPort = 8188;
  webPort = 8480;
  webLocalPort = webPort + 1;
  atriumHostname = "atrium.jeiang.dev";
  hf = repo: rev: file: "https://huggingface.co/${repo}/resolve/${rev}/${file}";
  models = {
    chat = {
      file = "Qwen3.5-9B-Q4_K_M.gguf";
      url = hf "lmstudio-community/Qwen3.5-9B-GGUF" "1379f25c6b505a3fc737bd7818cb09389cf807c1" "Qwen3.5-9B-Q4_K_M.gguf";
      sha256 = "cd76ec205963b3b33350093e6904d9de16c4e666fd104e1f632d25c7f15f2a13";
    };
    embed = {
      file = "embeddinggemma-2-Q8_0.gguf";
      url = hf "ggml-org/embeddinggemma-2-GGUF" "bfcd298762cc34d0357ece5ebdd31791a3a374d8" "embeddinggemma-2-Q8_0.gguf";
      sha256 = "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135";
    };
  };
  llamaUnits = ["atrium-llm.service" "atrium-embed.service"];
in {
  flake.lib = {
    atriumWebPort = webPort;
    atriumWebLocalPort = webLocalPort;
    inherit atriumHostname;
  };

  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: let
    llamaServer = self.lib.llamaServer {
      inherit lib pkgs stateDirName modelsDir models;
      name = "atrium";
      user = "atrium";
    };
    llamaService = llamaServer.service;
  in {
    imports = [inputs.atrium.nixosModules.default];

    services.atrium = {
      enable = true;
      mode = "live";
      environmentFiles = [config.sops.secrets."atrium/env".path];
      modelServerUnits = llamaUnits;
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

    gaming.pauseUnits = llamaUnits;

    persistence.directories = [
      {
        directory = stateDir;
        user = "atrium";
        group = "atrium";
        mode = "0750";
      }
    ];

    sops.secrets."atrium/env" = {
      sopsFile = ./secrets.yaml;
      mode = "0400";
      restartUnits = ["atrium-agent-scheduler.service" "atrium-notion-sync.service" "atrium-vdirsyncer-sync.service" "atrium-watch.service" "atrium-web.service" "atrium-web-local.service"];
    };

    systemd.services = {
      atrium-models-fetch = llamaServer.fetch;

      atrium-llm = llamaService "atrium-llm" {
        description = "Qwen3.5-9B chat server for atrium";
        model = models.chat;
        port = chatPort;
        args = [
          "--ctx-size"
          "8192"
          "--jinja"
          "--chat-template-kwargs"
          (builtins.toJSON {enable_thinking = false;})
        ];
      };

      atrium-embed = llamaService "atrium-embed" {
        description = "EmbeddingGemma 2 embedding server for atrium";
        model = models.embed;
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
}
