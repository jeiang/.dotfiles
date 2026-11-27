{
  self,
  inputs,
  ...
}: {
  darwin.modules.workstation = {config, ...}: {
    imports = [inputs.nix-homebrew.darwinModules.nix-homebrew];

    nix-homebrew = {
      enable = true;
      enableRosetta = false;
      user = self.lib.facts.userName;
      mutableTaps = false;
      # Pin Homebrew itself rather than trusting nix-homebrew's bundled default.
      package = inputs.homebrew-brew;
      taps = {
        "homebrew/homebrew-core" = inputs.homebrew-core;
        "homebrew/homebrew-cask" = inputs.homebrew-cask;
      };
    };

    homebrew = {
      enable = true;
      taps = builtins.attrNames config.nix-homebrew.taps;

      onActivation = {
        autoUpdate = false;
        upgrade = true;
        cleanup = "zap";
      };

      # Bitwarden, Wipr 2, Xcode, Yubico Authenticator and Office come from the App Store by hand: Spotlight does not index Bitwarden and Wipr 2, so mas would reinstall them on every switch, brew bundle cannot verify App Store apps without mas, and the Office cask keeps a 3.5 GB installer payload in Caskroom.
      casks = [
        "helium-browser"
        "gimp"
        "whatsapp"
        "steam"
        "notion-calendar"
      ];
    };
  };
}
