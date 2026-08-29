_: {
  flake.nixosModules.llama-swap = {
    pkgs,
    lib,
    ...
  }: let
    llama-cpp = pkgs.llama-cpp.override {vulkanSupport = true;};
    llama-server = lib.getExe' llama-cpp "llama-server";
    # models are persisted into this directory to avoid storing them in the
    # nix store
    modelDir = "/var/lib/llama-swap-models";
    models = {
      "ornith-1.0-9b-Q6_K.gguf" = {
        url = "https://huggingface.co/deepreinforce-ai/Ornith-1.0-9B-GGUF/resolve/main/ornith-1.0-9b-Q6_K.gguf";
        hash = "sha256-M7b2o+PwUHhDjhLfiktVyKz3jOrcxjnSrxzzWgJug4c=";
      };
      "Qwen3.5-9B-Q8_0.gguf" = {
        url = "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q8_0.gguf";
        hash = "sha256-gJYmV00MtD1L7PpWFpmA2iu0SPIpknD3vkQ8uJ0KauQ=";
      };
    };
    model = name: "${modelDir}/${name}";
  in {
    services.llama-swap = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 8080;
      settings = {
        # model load can exceed llama-swap's default health-check timeout
        healthCheckTimeout = 300;
        # ${PORT} in each cmd is llama-swap's own macro, escaped so Nix
        # leaves it literal in the generated YAML.
        models = {
          "ornith-1.0-9b" = {
            # -np 4: four parallel slots; -c 98304 is the total KV budget,
            # so each slot gets 24576 tokens of context.
            cmd = "${llama-server} --port \${PORT} -m ${model "ornith-1.0-9b-Q6_K.gguf"} -ngl 99 -c 98304 -np 4 --jinja --temp 0.6 --top-p 0.95 --top-k 20";
            aliases = ["ornith"];
            ttl = 1800;
          };
          "qwen3.5-9b" = {
            cmd = "${llama-server} --port \${PORT} -m ${model "Qwen3.5-9B-Q8_0.gguf"} -ngl 99 -c 40960 --jinja --temp 0.6 --top-p 0.95 --top-k 20";
            aliases = ["qwen"];
            ttl = 1800;
          };
        };
      };
    };

    # Downloads each model and refuses to hand it over unless the hash
    # matches; a no-op on every boot after the first.
    systemd.services.llama-swap-models = {
      description = "Fetch llama-swap GGUF models";
      # requiredBy + before: llama-swap must not start against a model file
      # that is absent or half-written.
      before = ["llama-swap.service"];
      requiredBy = ["llama-swap.service"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      path = [pkgs.curl pkgs.nix];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # tens of GB outlive the 90s default; a dead transfer fails in
        # minutes via curl's --speed-limit instead
        TimeoutStartSec = "infinity";
      };
      script =
        ''
          mkdir -p ${modelDir}
        ''
        + lib.concatStrings (lib.mapAttrsToList (name: m: ''
            dest=${model name}
            if [ "$(nix-hash --type sha256 --sri --flat "$dest" 2>/dev/null || true)" = "${m.hash}" ]; then
              echo "${name}: present"
            else
              echo "${name}: fetching"
              curl -fL --retry 3 --speed-limit 1024 --speed-time 120 -o "$dest.tmp" "${m.url}"
              got=$(nix-hash --type sha256 --sri --flat "$dest.tmp")
              if [ "$got" != "${m.hash}" ]; then
                echo "${name}: hash mismatch: got $got, want ${m.hash}" >&2
                rm -f "$dest.tmp"
                exit 1
              fi
              mv "$dest.tmp" "$dest"
            fi
          '')
          models);
    };

    systemd.services.llama-swap = {
      # rocm-smi on PATH gives the UI its VRAM/temperature stats (llama-swap
      # v224 has no sysfs fallback).
      path = [pkgs.rocmPackages.rocm-smi];
      serviceConfig = {
        # GPU render-node access for the upstream unit's DynamicUser
        SupplementaryGroups = ["render" "video"];
        # writable RADV shader cache
        CacheDirectory = "llama-swap";
      };
      environment.XDG_CACHE_HOME = "/var/cache/llama-swap";
    };
  };
}
