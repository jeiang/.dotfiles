{
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    # Packaged here instead of upstream's flake: its cargoHash is stale, and building against this flake's nixpkgs matches libva to artemis' Mesa (upstream's pin silently dropped VA-API to software H.264).
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

        cargoHash = "sha256-fx2SA0xXlxDIBI/2EtvzW9LGK1pbAZevK0y/dJAw2vg=";

        # Hyprland 0.56 answers `keyword` with "unknown request" rather than the "non-legacy parsers" refusal hypr-rdp's fallback check matches, so startup died before listening; widen the check.
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
