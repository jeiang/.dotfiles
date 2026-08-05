_: {
  # Local models served on artemis, fronted by llama-swap so VRAM is freed
  # after idle instead of holding a model resident forever.
  flake.nixosModules.llama-swap = {
    pkgs,
    lib,
    ...
  }: let
    llama-cpp = pkgs.llama-cpp.override {vulkanSupport = true;};
    llama-server = lib.getExe' llama-cpp "llama-server";
    # Models hash-pinned into the store so they survive reboots (nix store
    # is persisted) with no impermanence entry.
    ornith = pkgs.fetchurl {
      url = "https://huggingface.co/deepreinforce-ai/Ornith-1.0-9B-GGUF/resolve/main/ornith-1.0-9b-Q6_K.gguf";
      hash = "sha256-M7b2o+PwUHhDjhLfiktVyKz3jOrcxjnSrxzzWgJug4c=";
    };
    qwen = pkgs.fetchurl {
      url = "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q8_0.gguf";
      hash = "sha256-gJYmV00MtD1L7PpWFpmA2iu0SPIpknD3vkQ8uJ0KauQ=";
    };
    gemma = pkgs.fetchurl {
      url = "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/main/gemma-4-12b-it-Q6_K.gguf";
      hash = "sha256-bzlDNlALtUCb1owxqp11CXteYQT2zzDIKgmntk30H68=";
    };
    nemotron = pkgs.fetchurl {
      url = "https://huggingface.co/bartowski/nvidia_NVIDIA-Nemotron-Nano-12B-v2-GGUF/resolve/main/nvidia_NVIDIA-Nemotron-Nano-12B-v2-Q6_K.gguf";
      hash = "sha256-ZZZhGQ2fZQrku6JS3jqI7Qu8tg67ToM8xtHbOWEEFtw=";
    };
  in {
    services.llama-swap = {
      enable = true;
      # Bind all interfaces; the firewall (not the listen address) is what
      # keeps this off the LAN -- see openFirewall below.
      listenAddress = "0.0.0.0";
      port = 8080;
      # openFirewall stays at its false default. artemis trusts the netbird
      # interface (modules/nixos/netbird.nix), so with the firewall closed
      # this is reachable from localhost and the netbird mesh, but blocked
      # from the LAN.
      settings = {
        # Model load (7.4 GB, full GPU offload) can take longer than
        # llama-swap's default health-check timeout.
        healthCheckTimeout = 300;
        # ${PORT} in each cmd is llama-swap's own macro (escaped with the
        # extra $ so Nix leaves it literal in the generated YAML), not a Nix
        # interpolation like ${llama-server}/${ornith} etc.
        # Shared flags: -ngl 99 full GPU offload; --jinja use the model's
        # embedded chat template; ttl 1800 frees all VRAM after 30 min idle.
        # Sampling flags follow each model card.
        models = {
          "ornith-1.0-9b" = {
            # -np 4: four parallel slots; -c 98304 is the total KV budget, so
            # each slot gets 24576 tokens of context.
            cmd = "${llama-server} --port \${PORT} -m ${ornith} -ngl 99 -c 98304 -np 4 --jinja --temp 0.6 --top-p 0.95 --top-k 20";
            aliases = ["ornith"];
            ttl = 1800;
          };
          "qwen3.5-9b" = {
            cmd = "${llama-server} --port \${PORT} -m ${qwen} -ngl 99 -c 40960 --jinja --temp 0.6 --top-p 0.95 --top-k 20";
            aliases = ["qwen"];
            ttl = 1800;
          };
          "gemma-4-12b" = {
            cmd = "${llama-server} --port \${PORT} -m ${gemma} -ngl 99 -c 32768 --jinja --temp 1.0 --top-p 0.95 --top-k 64";
            aliases = ["gemma"];
            ttl = 1800;
          };
          "nemotron-nano-12b-v2" = {
            cmd = "${llama-server} --port \${PORT} -m ${nemotron} -ngl 99 -c 32768 --jinja --temp 0.6 --top-p 0.95";
            aliases = ["nemotron"];
            ttl = 1800;
          };
        };
      };
    };

    systemd.services.llama-swap = {
      # rocm-smi on PATH gives llama-swap's UI VRAM/temperature stats -- it
      # probes LACT, nvidia-smi, then rocm-smi (v224 has no sysfs fallback).
      # The standalone sysfs reader, not the full ROCm stack.
      path = [pkgs.rocmPackages.rocm-smi];
      serviceConfig = {
        # GPU render-node access for the DynamicUser the upstream unit runs as.
        SupplementaryGroups = ["render" "video"];
        # Writable RADV shader cache; disposable state, fine for nukeRoot to
        # wipe on reboot.
        CacheDirectory = "llama-swap";
      };
      environment.XDG_CACHE_HOME = "/var/cache/llama-swap";
    };
  };
}
