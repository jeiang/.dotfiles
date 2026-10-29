{self, ...}: let
  name = "cod4e-vision";
  stateDir = "/var/lib/${name}";
  modelsDir = "${stateDir}/models";
  embedPort = 8189;
  reviewPort = 8190;
  hf = repo: rev: file: {
    inherit file;
    url = "https://huggingface.co/${repo}/resolve/${rev}/${file}";
  };
  embeddinggemma = hf "ggml-org/embeddinggemma-2-GGUF" "bfcd298762cc34d0357ece5ebdd31791a3a374d8";
  qwen = hf "lmstudio-community/Qwen3.5-9B-GGUF" "1379f25c6b505a3fc737bd7818cb09389cf807c1";
  models = {
    embed = embeddinggemma "embeddinggemma-2-Q8_0.gguf" // {sha256 = "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135";};
    embedProjector = embeddinggemma "mmproj-embeddinggemma-2-Q8_0.gguf" // {sha256 = "c4a8a52691ecef40618438928bdf9e68379b854e24166f292592353db0aab64f";};
    review = qwen "Qwen3.5-9B-Q4_K_M.gguf" // {sha256 = "cd76ec205963b3b33350093e6904d9de16c4e666fd104e1f632d25c7f15f2a13";};
    reviewProjector = qwen "mmproj-Qwen3.5-9B-BF16.gguf" // {sha256 = "330d17547bfdbcd0e7a0cb3f4b06b4ceeac0aaa1e449122d9d66ef957aeb74b3";};
  };
in {
  nixos.modules.artemis = {
    lib,
    pkgs,
    ...
  }: let
    llamaServer = self.lib.llamaServer {
      inherit lib pkgs name modelsDir models;
      user = name;
      stateDirName = name;
    };
    projector = model: ["--mmproj" "${modelsDir}/${model.file}"];
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

    gaming.pauseUnits = ["${name}-embed.service" "${name}-review.service"];

    # Both servers listen on every interface but open no firewall port: only the trusted NetBird interface reaches them.
    systemd.services = {
      "${name}-models-fetch" = llamaServer.fetch;

      "${name}-embed" = llamaServer.service "${name}-embed" {
        description = "EmbeddingGemma 2 image and text embeddings for cod4e footage";
        model = models.embed;
        port = embedPort;
        host = "0.0.0.0";
        args =
          projector models.embedProjector
          ++ [
            "--embedding"
            "--ctx-size"
            "8192"
            "--batch-size"
            "8192"
            "--ubatch-size"
            "8192"
          ];
      };

      "${name}-review" = llamaServer.service "${name}-review" {
        description = "Qwen3.5-9B vision review of cod4e footage";
        model = models.review;
        port = reviewPort;
        host = "0.0.0.0";
        args =
          projector models.reviewProjector
          ++ [
            "--ctx-size"
            "16384"
            "--jinja"
            "--chat-template-kwargs"
            (builtins.toJSON {enable_thinking = false;})
          ];
      };
    };
  };
}
