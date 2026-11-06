{self, ...}: let
  name = "cod4e-vision";
  stateDir = "/var/lib/${name}";
  embedPort = 8189;
  reviewPort = 8190;
in {
  nixos.modules.artemis = {
    lib,
    pkgs,
    ...
  }: let
    models = self.lib.llamaModels;
    llamaServer = self.lib.llamaServer {
      inherit lib pkgs name;
      modelsDir = "${stateDir}/models";
      # Both servers listen on every interface but open no firewall port: only the trusted NetBird interface reaches them.
      servers = {
        embed = {
          description = "EmbeddingGemma 2 image and text embeddings for cod4e footage";
          model = models.embeddinggemma;
          projector = models.embeddinggemmaProjector;
          port = embedPort;
          host = "0.0.0.0";
          args = [
            "--embedding"
            "--ctx-size"
            "8192"
            "--batch-size"
            "8192"
            "--ubatch-size"
            "8192"
          ];
        };
        review = {
          description = "Qwen3.5-9B vision review of cod4e footage";
          model = models.qwen35;
          projector = models.qwen35Projector;
          port = reviewPort;
          host = "0.0.0.0";
          args = [
            "--ctx-size"
            "16384"
            "--jinja"
            "--chat-template-kwargs"
            (builtins.toJSON {enable_thinking = false;})
          ];
        };
      };
    };
  in {
    users = {
      users.${name} = {
        isSystemUser = true;
        group = name;
      };
      groups.${name} = {};
    };

    persistence.directories = [
      {
        directory = stateDir;
        user = name;
        group = name;
        mode = "0750";
      }
    ];

    gaming.pauseUnits = llamaServer.units;

    systemd.services = llamaServer.services;
  };
}
