{
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    # Native RDP server for Hyprland (github.com/MuNeNICK/hypr-rdp), used to
    # reach artemis' session from an RDP client over the NetBird mesh.
    #
    # Packaged here rather than run straight from upstream's own flake for two
    # reasons. Upstream's `cargoHash` is stale -- `nix run
    # github:MuNeNICK/hypr-rdp#hypr-rdp` fails outright on a fixed-output hash
    # mismatch against the vendor derivation -- and, more importantly, building
    # against this flake's nixpkgs is what makes VA-API work: upstream's flake
    # pins its own nixpkgs, so its libva did not match artemis' Mesa and
    # `radeonsi_drv_video.so` loaded with "no function __vaDriverInit_1_0",
    # silently dropping the session to software H.264. Same nixpkgs, same libva
    # ABI, hardware encode.
    #
    # The dependency set and the pulseaudio wrapper mirror upstream's
    # pkg/nix/package.nix; `pactl` is reached through PipeWire's PulseAudio
    # compatibility layer for the default remote-audio routing mode.
    #
    # Linux-only (Wayland/VA-API): absent on darwin rather than an eval error,
    # so output-enumerating commands work there.
    packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      hypr-rdp = pkgs.rustPlatform.buildRustPackage rec {
        pname = "hypr-rdp";
        version = "0.1.5";

        src = pkgs.fetchFromGitHub {
          owner = "MuNeNICK";
          repo = "hypr-rdp";
          tag = "v${version}";
          hash = "sha256-yrC8fITJofWJ2wpZMiaX06UVCMFI4GRg9pGyaTdosHg=";
        };

        # Upstream's own package.nix declares
        # sha256-2TDPG/FvF9eaAxpdzocVnBZ6KMwKIkHmqq8s50xubCo=, which no longer
        # matches what `cargo vendor` produces for this Cargo.lock.
        cargoHash = "sha256-fx2SA0xXlxDIBI/2EtvzW9LGK1pbAZevK0y/dJAw2vg=";

        # hypr-rdp sizes its headless output with `keyword monitor <rule>` and
        # only falls back to `eval hl.monitor{...}` when Hyprland's refusal says
        # "keyword can't work with non-legacy parsers". Hyprland 0.56 (what
        # artemis runs, with the Lua config parser) answers `keyword` with a bare
        # "unknown request" instead, which that check does not match -- so
        # start-up died with "failed to set headless output resolution" before
        # the server ever listened. Widen the check to the message we actually
        # get; the eval path it then takes is verified working against 0.56.
        postPatch = ''
          substituteInPlace src/hyprland.rs \
            --replace-fail \
              '.any(|cause| cause.to_string().contains("non-legacy parsers"))' \
              '.any(|cause| { let msg = cause.to_string(); msg.contains("non-legacy parsers") || msg.contains("unknown request") })'
        '';

        nativeBuildInputs = with pkgs; [
          pkg-config
          cmake
          clang
          makeWrapper
          rustPlatform.bindgenHook
        ];

        buildInputs = with pkgs; [
          ffmpeg
          libdrm
          libgbm
          libva
          libxkbcommon
          mesa
          pipewire
          wayland
        ];

        postInstall = ''
          wrapProgram $out/bin/hypr-rdp \
            --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.pulseaudio]}
        '';

        doCheck = false;

        meta = {
          description = "Native RDP server for Hyprland";
          homepage = "https://github.com/MuNeNICK/hypr-rdp";
          license = pkgs.lib.licenses.mit;
          mainProgram = "hypr-rdp";
          platforms = pkgs.lib.platforms.linux;
        };
      };
    };
  };
}
