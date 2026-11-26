{self, ...}: {
  darwin.modules.workstation = {pkgs, ...}: let
    wrapped = self.packages.${pkgs.stdenv.hostPlatform.system};
  in {
    # Ghostty.app ignores the wrapper's --config-file flag when launched from
    # the Dock or a launcher, so the same config is installed at the XDG path.
    hjem.users.${self.lib.facts.userName}.files.".config/ghostty/config".source = wrapped.ghostty-config;

    environment.systemPackages = with pkgs; [
      discord
      iina
      # Prism defaults to Java 8, 17 and 21 as well, for instances that need them; this host keeps only the current one.
      (prismlauncher.override {jdks = [jdk25];})
      wrapped.ghostty

      bat
      btop
      defaultbrowser
      ffmpeg
      gnupg
      pinentry_mac
      imagemagick
      megatools
      mole-cleaner
    ];
  };
}
