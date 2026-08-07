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
    # Models are fetched at runtime into a persisted directory rather than
    # hash-pinned into the store. As `pkgs.fetchurl` results they were store
    # paths referenced by each `cmd` below, which put 34 GB of GGUF inside
    # nixos-system-artemis's closure: every CI leg and every deploy had to
    # drag all of it over the wire just to prove the configuration evaluates,
    # and it made toplevel-artemis the slowest job in the matrix by a factor
    # of four.
    #
    # The store was doing three jobs here -- fetching, integrity, and
    # surviving the nukeRoot reboot (via the persisted /nix). The unit below
    # takes over the first two; the third needs the /var/lib/llama-swap-models
    # entry in modules/hosts/artemis/default.nix `persistence.directories`,
    # which is what the original "no impermanence entry" comment was avoiding.
    # Without that entry every reboot re-downloads the lot.
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
      "gemma-4-12b-it-Q6_K.gguf" = {
        url = "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/main/gemma-4-12b-it-Q6_K.gguf";
        hash = "sha256-bzlDNlALtUCb1owxqp11CXteYQT2zzDIKgmntk30H68=";
      };
      "nvidia_NVIDIA-Nemotron-Nano-12B-v2-Q6_K.gguf" = {
        url = "https://huggingface.co/bartowski/nvidia_NVIDIA-Nemotron-Nano-12B-v2-GGUF/resolve/main/nvidia_NVIDIA-Nemotron-Nano-12B-v2-Q6_K.gguf";
        hash = "sha256-ZZZhGQ2fZQrku6JS3jqI7Qu8tg67ToM8xtHbOWEEFtw=";
      };
    };
    # A plain string, deliberately: interpolating a store path here is exactly
    # what pulled the weights into the closure.
    model = name: "${modelDir}/${name}";
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
        # interpolation like ${llama-server}/${model "..."} etc.
        # Shared flags: -ngl 99 full GPU offload; --jinja use the model's
        # embedded chat template; ttl 1800 frees all VRAM after 30 min idle.
        # Sampling flags follow each model card.
        models = {
          "ornith-1.0-9b" = {
            # -np 4: four parallel slots; -c 98304 is the total KV budget, so
            # each slot gets 24576 tokens of context.
            cmd = "${llama-server} --port \${PORT} -m ${model "ornith-1.0-9b-Q6_K.gguf"} -ngl 99 -c 98304 -np 4 --jinja --temp 0.6 --top-p 0.95 --top-k 20";
            aliases = ["ornith"];
            ttl = 1800;
          };
          "qwen3.5-9b" = {
            cmd = "${llama-server} --port \${PORT} -m ${model "Qwen3.5-9B-Q8_0.gguf"} -ngl 99 -c 40960 --jinja --temp 0.6 --top-p 0.95 --top-k 20";
            aliases = ["qwen"];
            ttl = 1800;
          };
          "gemma-4-12b" = {
            cmd = "${llama-server} --port \${PORT} -m ${model "gemma-4-12b-it-Q6_K.gguf"} -ngl 99 -c 32768 --jinja --temp 1.0 --top-p 0.95 --top-k 64";
            aliases = ["gemma"];
            ttl = 1800;
          };
          "nemotron-nano-12b-v2" = {
            cmd = "${llama-server} --port \${PORT} -m ${model "nvidia_NVIDIA-Nemotron-Nano-12B-v2-Q6_K.gguf"} -ngl 99 -c 32768 --jinja --temp 0.6 --top-p 0.95";
            aliases = ["nemotron"];
            ttl = 1800;
          };
        };
      };
    };

    # Replaces what pkgs.fetchurl used to do at build time: download each
    # model and refuse to hand it over unless the hash matches. Idempotent, so
    # it is a no-op on every boot after the first, and re-fetches only a file
    # that has gone missing or been corrupted.
    systemd.services.llama-swap-models = {
      description = "Fetch llama-swap GGUF models";
      # requiredBy + before rather than a plain wantedBy: llama-swap must not
      # start against a model file that is absent or half-written. A failed
      # fetch now holds llama-swap down instead of crash-looping llama-server
      # against a missing -m argument.
      before = ["llama-swap.service"];
      requiredBy = ["llama-swap.service"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      path = [pkgs.curl pkgs.nix];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Tens of GB will blow past the 90s default long before it finishes;
        # a genuinely dead transfer is caught by curl's --speed-limit instead,
        # which fails in minutes rather than hanging the boot forever.
        TimeoutStartSec = "infinity";
      };
      # nix-hash --sri prints the same format the `hash` attrs above are
      # written in, so the check compares against those strings verbatim --
      # nothing to convert, nothing to keep in sync.
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
