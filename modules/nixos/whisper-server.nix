_: {
  flake.nixosModules.whisper-server = {
    pkgs,
    lib,
    ...
  }: let
    # Vulkan, not ROCm: RADV is what the desktop stack already loads, and
    # the ROCm build multiplies compile time for no gain here.
    whisper = pkgs.whisper-cpp-vulkan;
    whisperServer = lib.getExe' whisper "whisper-server";

    port = 8081;

    # models are persisted into this directory to avoid storing them in the
    # nix store
    modelDir = "/var/lib/whisper-models";
    modelName = "ggml-large-v3-turbo-q5_0.bin";
    modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${modelName}";
    modelHash = "sha256-OUIhcJzVrR9AxG5gMcphvOiJMebgiMGIKUxtWlX/p+I=";
    modelPath = "${modelDir}/${modelName}";
  in {
    # Downloads the model and refuses to hand it over unless the hash
    # matches; a no-op after the first boot. Root, not DynamicUser, so the
    # file lands in the persisted modelDir.
    systemd.services.whisper-models = {
      description = "Fetch whisper.cpp GGML model";
      # requiredBy + before: whisper-server must not start against a model
      # file that is absent or half-written.
      before = ["whisper-server.service"];
      requiredBy = ["whisper-server.service"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      path = [pkgs.curl pkgs.nix];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # the download can outlive the 90s default; a dead transfer fails in
        # minutes via curl's --speed-limit instead
        TimeoutStartSec = "infinity";
      };
      script = ''
        mkdir -p ${modelDir}
        dest=${modelPath}
        if [ "$(nix-hash --type sha256 --sri --flat "$dest" 2>/dev/null || true)" = "${modelHash}" ]; then
          echo "${modelName}: present"
        else
          echo "${modelName}: fetching"
          curl -fL --retry 3 --speed-limit 1024 --speed-time 120 -o "$dest.tmp" "${modelUrl}"
          got=$(nix-hash --type sha256 --sri --flat "$dest.tmp")
          if [ "$got" != "${modelHash}" ]; then
            echo "${modelName}: hash mismatch: got $got, want ${modelHash}" >&2
            rm -f "$dest.tmp"
            exit 1
          fi
          mv "$dest.tmp" "$dest"
        fi
      '';
    };

    systemd.services.whisper-server = {
      description = "whisper.cpp speech-to-text server";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      environment = {
        AMD_VULKAN_ICD = "RADV";
        # writable RADV shader cache
        XDG_CACHE_HOME = "/var/cache/whisper-server";
      };
      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          whisperServer
          "-m"
          modelPath
          "--host"
          "0.0.0.0"
          "--port"
          (toString port)
          # OpenAI-shaped clients work against this path with no rewriting
          "--inference-path"
          "/v1/audio/transcriptions"
          # transcode uploads via ffmpeg instead of requiring 16 kHz WAV
          "--convert"
          # the upstream default "en" silently mistranscribes other languages
          "-l"
          "auto"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = true;
        # GPU render-node access; deliberately no PrivateDevices -- it would
        # hide /dev/dri and drop the unit back to CPU decoding.
        SupplementaryGroups = ["render" "video"];
        CacheDirectory = "whisper-server";
        # MemoryDenyWriteExecute is absent on purpose: the Vulkan driver
        # JITs shaders and dies under it.
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectClock = true;
        ProtectProc = "invisible";
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        SystemCallFilter = ["@system-service" "~@privileged"];
      };
    };
  };
}
