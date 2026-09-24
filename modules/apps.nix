{
  self,
  inputs,
  ...
}: {
  darwin.modules.base = {
    config,
    pkgs,
    ...
  }: let
    wrapped = self.packages.${pkgs.stdenv.hostPlatform.system};
    agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  in {
    fonts.packages = [pkgs.nerd-fonts.mononoki];

    # Ghostty.app ignores the wrapper's --config-file flag when launched from
    # the Dock or Raycast, so the same config is installed at the XDG path.
    hjem.users.${config.preferences.user.name}.files.".config/ghostty/config".source = wrapped.ghostty-config;

    programs.direnv = {
      enable = true;
      silent = false;
      loadInNixShell = true;
    };

    environment.systemPackages =
      (with pkgs; [
        crossover
        discord
        iina
        moonlight-qt
        mos
        nomacs
        notion-app
        obsidian
        qbittorrent
        raycast
        telegram-desktop
        utm
        whatsapp-for-mac
        zed-editor
        wrapped.ghostty

        bat
        btop
        caligula
        defaultbrowser
        # withWhisper off: whisper-cpp's CoreML backend fails to link on this pinned aarch64-darwin toolchain. doCheck off: ffmpeg's FATE suite is impractical for a CI build.
        ((ffmpeg-full.override {withWhisper = false;}).overrideAttrs (_: {doCheck = false;}))
        gallery-dl
        ggshield
        gh
        gnupg
        pinentry_mac
        go
        hcloud
        imagemagick
        megatools
        mole-cleaner
        miniserve
        nmap
        nodejs
        ouch
        pkgconf
        pnpm
        tokei
        unbound
        upx
        uv
        zig
      ])
      ++ [
        wrapped.git
        wrapped.difft
        agents.chatgpt
        agents.claude-desktop
      ];
  };
}
