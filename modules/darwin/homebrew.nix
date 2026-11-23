{
  self,
  inputs,
  ...
}: {
  darwin.modules.base = {config, ...}: let
    # brew bundle never installs these; install them from the App Store by hand. Spotlight does not index Bitwarden and Wipr 2, so mas would reinstall them on every switch.
    manualMasApps = {
      Bitwarden = 1352778147;
      "Wipr 2" = 1662217862;
      Xcode = 497799835;
    };
  in {
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
        "k06a/homebrew-tap" = inputs.k06a-tap;
        "omlahore/homebrew-tap" = inputs.omlahore-tap;
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
        extraEnv.HOMEBREW_BUNDLE_MAS_SKIP = toString (builtins.attrValues manualMasApps);
      };

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
        "codex-app"
      ];

      brews = [
        "k06a/tap/macpow"
        "omlahore/tap/removemacai"
      ];

      masApps = manualMasApps // {"Yubico Authenticator" = 1497506650;};
    };
  };
}
