{self, ...}: {
  flake.darwinModules.apps = {pkgs, ...}: {
    # nix-darwin ships a real programs.direnv module (unlike the NixOS side,
    # which gets direnv through modules/nixos/nix.nix's `programs.direnv`
    # block) -- same settings, so nix-direnv behaves identically here.
    programs.direnv = {
      enable = true;
      silent = false;
      loadInNixShell = true;
    };

    environment.systemPackages = let
      wrapped = self.packages.${pkgs.stdenv.hostPlatform.system};
    in
      (with pkgs; [
        # GUI, nixpkgs-first (docs/adr/0009)
        discord
        iina
        # Client for artemis's Sunshine stream (modules/nixos/sunshine.nix);
        # VideoToolbox hardware decode, prefer HEVC over AV1 (AV1 decode is
        # software in moonlight-qt as of 2026).
        moonlight-qt
        mos
        # nixpkgs-first (docs/adr/0009): the vendor .app unpacked from
        # Notion's own per-arch desktop zip (the aarch64 entry of the
        # package's info.json), so no Homebrew cask exception is needed.
        notion-app
        obsidian
        qbittorrent
        raycast
        telegram-desktop
        utm
        zed-editor
        wrapped.ghostty

        # CLI
        bat
        btop
        # The CLI, separate from the "claude" desktop cask in
        # modules/darwin/homebrew.nix. nixpkgs disables its self-updater,
        # so it tracks this flake's nixpkgs input.
        claude-code
        defaultbrowser
        erdtree
        fd
        # withWhisper defaults on for ffmpeg-full >=8.0 (whisper speech
        # recognition support); whisper-cpp's CoreML backend fails to link
        # on this pinned nixpkgs' aarch64-darwin toolchain (ld crashes with
        # "Trace/BPT trap: 5" building libwhisper.coreml.dylib). Disabling
        # it here only drops that one feature, not ffmpeg-full itself.
        # doCheck also disabled: ffmpeg's FATE suite (hundreds of
        # encode/decode roundtrip cases) is impractical for a hosted-runner
        # CI build of a CLI tool, not a correctness requirement here.
        ((ffmpeg-full.override {withWhisper = false;}).overrideAttrs (_: {doCheck = false;}))
        gallery-dl
        ggshield
        gh
        gnupg
        pinentry_mac
        go
        hcloud
        kubernetes-helm
        helm-ls
        imagemagick
        kubectl
        kyverno
        mcfly
        megatools
        miniserve
        nmap
        nodejs
        ouch
        pkgconf
        pnpm
        ripgrep
        tokei
        unbound
        upx
        uv
        zig
      ])
      ++ [
        wrapped.git
        wrapped.difft
        wrapped.helix
      ];
  };
}
