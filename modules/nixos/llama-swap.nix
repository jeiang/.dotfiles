_: {
  # Ornith-1.0-9B (Q6_K) served locally on artemis, fronted by llama-swap so
  # VRAM is freed after idle instead of holding the model resident forever.
  flake.nixosModules.llama-swap = {
    pkgs,
    lib,
    ...
  }: let
    llama-cpp = pkgs.llama-cpp.override {vulkanSupport = true;};
    llama-server = lib.getExe' llama-cpp "llama-server";
    # Ornith-1.0-9B Q6_K, hash-pinned into the store so it survives
    # reboots (nix store is persisted) with no impermanence entry.
    model = pkgs.fetchurl {
      url = "https://huggingface.co/deepreinforce-ai/Ornith-1.0-9B-GGUF/resolve/main/ornith-1.0-9b-Q6_K.gguf";
      hash = "sha256-M7b2o+PwUHhDjhLfiktVyKz3jOrcxjnSrxzzWgJug4c=";
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
        models."ornith-1.0-9b" = {
          # ${PORT} above is llama-swap's own macro (escaped with the extra
          # $ so Nix leaves it literal in the generated YAML), not a Nix
          # interpolation like ${llama-server}/${model} below.
          # -ngl 99: full GPU offload. -c 40960: still inside the 16 GB VRAM
          # budget at this quant. --jinja: use the model's embedded chat
          # template (Ornith is Qwen 3.5-based). --temp/--top-p/--top-k:
          # sampling defaults per the Ornith-1.0-9B model card.
          cmd = "${llama-server} --port \${PORT} -m ${model} -ngl 99 -c 40960 --jinja --temp 0.6 --top-p 0.95 --top-k 20";
          aliases = ["ornith"];
          # Free all VRAM after 30 min idle.
          ttl = 1800;
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
