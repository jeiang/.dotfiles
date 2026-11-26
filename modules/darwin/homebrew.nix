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
      package =
        inputs.homebrew-brew
        // {
          name = "brew-${inputs.homebrew-brew.shortRev}";
          version = inputs.homebrew-brew.shortRev;
        };
      taps = {
        "homebrew/homebrew-core" = inputs.homebrew-core;
        "homebrew/homebrew-cask" = inputs.homebrew-cask;
      };
    };

    homebrew = {
      enable = true;
      # Homebrew >= 6.0 refuses formulae/casks from unofficial taps unless the Brewfile marks them trusted; manual `brew trust` doesn't survive the cleanup = "zap" pass.
      taps = map (name: {
        inherit name;
        trusted = true;
      }) (builtins.attrNames config.nix-homebrew.taps);

      onActivation = {
        autoUpdate = false;
        upgrade = true;
        cleanup = "zap";
      };

      # Bitwarden, Wipr 2, Xcode and Yubico Authenticator come from the App Store by hand: Spotlight does not index the first two, so mas would reinstall them on every switch, and brew bundle cannot verify App Store apps without mas.
      casks = [
        "helium-browser"
        "gimp"
        "whatsapp"
        "microsoft-word"
        "microsoft-excel"
        "microsoft-powerpoint"
        "roblox"
        "steam"
        "notion-calendar"
        # These apps update themselves in place, which a read-only store copy under /Applications/Nix Apps cannot take.
        "claude"
        "notion"
        "chatgpt"
      ];
    };
  };
}
