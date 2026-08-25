_: {
  # Speech-to-text endpoint for the fleet, served from artemis's GPU.
  # nixpkgs ships whisper.cpp as a package only -- no NixOS module exists
  # (DESIGN.md Service Ownership) -- so this is the systemd unit for it.
  flake.nixosModules.whisper-server = {
    pkgs,
    lib,
    ...
  }: let
    # Vulkan, not ROCm, matching llama-swap and the rest of this host's
    # deliberate backend choice: RADV is what the desktop stack already
    # loads, and the ROCm build multiplies compile time by the GPU target
    # list for no gain here.
    whisper = pkgs.whisper-cpp-vulkan;
    whisperServer = lib.getExe' whisper "whisper-server";

    port = 8081;

    # Same reasoning as modules/nixos/llama-swap.nix, and the same mechanism:
    # weights are fetched at runtime into a persisted directory instead of
    # being hash-pinned with fetchurl. A fetchurl model is a store path, and
    # a store path referenced from ExecStart is part of
    # nixos-system-artemis's closure -- which is what made every CI leg and
    # every deploy drag the GGUF over the wire just to prove the config
    # evaluates. The store's fetch and integrity jobs are done by the oneshot
    # below; its third job, surviving the nukeRoot reboot, is the
    # /var/lib/whisper-models entry in modules/hosts/artemis/default.nix
    # `persistence.directories`. Without that entry every boot re-downloads.
    modelDir = "/var/lib/whisper-models";
    # large-v3-turbo at q5_0: ~550 MB, the accuracy of large-v3 at roughly a
    # fifth of its decode cost, which fits alongside llama-swap's resident
    # model instead of fighting it for VRAM.
    modelName = "ggml-large-v3-turbo-q5_0.bin";
    modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${modelName}";
    modelHash = "sha256-OUIhcJzVrR9AxG5gMcphvOiJMebgiMGIKUxtWlX/p+I=";
    # A plain string, deliberately: interpolating a store path here is
    # exactly what would pull the weights into the closure.
    modelPath = "${modelDir}/${modelName}";
  in {
    # Replaces what pkgs.fetchurl would have done at build time: download the
    # model and refuse to hand it over unless the hash matches. Idempotent,
    # so it is a no-op on every boot after the first, and re-fetches only a
    # file that has gone missing or been corrupted. Runs as root (no
    # DynamicUser) so the file lands in the persisted, world-readable
    # ${modelDir} rather than in a per-unit StateDirectory the server's
    # DynamicUser could not be pointed at across restarts.
    systemd.services.whisper-models = {
      description = "Fetch whisper.cpp GGML model";
      # requiredBy + before rather than a plain wantedBy: whisper-server must
      # not start against a model file that is absent or half-written. A
      # failed fetch holds the server down instead of crash-looping it
      # against a missing -m argument.
      before = ["whisper-server.service"];
      requiredBy = ["whisper-server.service"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      path = [pkgs.curl pkgs.nix];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Half a gigabyte can outrun the 90s default on a slow link; a
        # genuinely dead transfer is caught by curl's --speed-limit instead,
        # which fails in minutes rather than hanging the boot forever.
        TimeoutStartSec = "infinity";
      };
      # nix-hash --sri prints the same format modelHash is written in, so the
      # check compares against that string verbatim -- nothing to convert,
      # nothing to keep in sync.
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
        # Writable RADV shader cache, pointed at the CacheDirectory below.
        # Disposable state; fine for nukeRoot to wipe on reboot.
        XDG_CACHE_HOME = "/var/cache/whisper-server";
      };
      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          whisperServer
          "-m"
          modelPath
          # Bind all interfaces; as with llama-swap and qdrant, it is the
          # closed firewall plus artemis trusting only the netbird interface
          # (modules/nixos/netbird.nix) that keeps this on the mesh and off
          # the LAN. Nothing opens ${toString port}.
          "--host"
          "0.0.0.0"
          "--port"
          (toString port)
          # whisper-server serves exactly one inference route, at whatever
          # path this names, and reads OpenAI's field names off the multipart
          # body (file, language, response_format, prompt, temperature).
          # Naming it /v1/audio/transcriptions means an OpenAI-shaped client
          # pointed at http://artemis.jeiang.vpn:${toString port} works with
          # no path rewriting.
          "--inference-path"
          "/v1/audio/transcriptions"
          # Transcode uploads through ffmpeg instead of rejecting everything
          # that is not 16 kHz WAV. The nixpkgs derivation already wraps
          # whisper-server with ffmpeg on PATH, so this needs nothing else.
          "--convert"
          # Detect the spoken language rather than assuming English. The
          # upstream default is "en", which silently mistranscribes anything
          # else; callers that know better still override it per request.
          "-l"
          "auto"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        # No persistent state of its own: the model comes from the persisted
        # ${modelDir} above and everything else is per-request, so the unit
        # can take an ephemeral identity.
        DynamicUser = true;
        # GPU render-node access for that DynamicUser. Deliberately no
        # PrivateDevices: it would hide /dev/dri and drop the unit back to
        # CPU decoding.
        SupplementaryGroups = ["render" "video"];
        CacheDirectory = "whisper-server";
        # DynamicUser already implies ProtectSystem=strict, PrivateTmp, and
        # RemoveIPC; the rest mirrors the hardening nixpkgs applies to
        # qdrant. MemoryDenyWriteExecute is absent on purpose -- the Vulkan
        # driver JITs shaders and dies under it.
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
