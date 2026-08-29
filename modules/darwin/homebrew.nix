{inputs, ...}: {
  flake.darwinModules.homebrew = {config, ...}: {
    imports = [inputs.nix-homebrew.darwinModules.nix-homebrew];

    nix-homebrew = {
      enable = true;
      enableRosetta = false;
      user = config.preferences.user.name;
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
        "can1357/homebrew-tap" = inputs.can1357-tap;
        "k06a/homebrew-tap" = inputs.k06a-tap;
        "netbirdio/homebrew-tap" = inputs.netbird-tap;
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
        upgrade = false;
        cleanup = "zap";
      };

      casks = [
        "helium-browser"
        "whatsapp"
        "chatgpt"
        "claude"
        "crossover"
        "actual"
        "gimp"
        "balenaetcher"
        "microsoft-word"
        "microsoft-excel"
        "roblox"
        "qview"
        "handbrake-app"
        # The .app manages its own daemon/tunnel (a nix-managed daemon around the netbird CLI would fight it); the cask never auto-updates -- bump the netbird-tap input and run `brew upgrade --cask netbirdio/tap/netbird-ui` after switching.
        "netbirdio/tap/netbird-ui"
      ];

      brews = [
        "can1357/tap/omp"
        "k06a/tap/macpow"
        "mole"
        "displayplacer"
      ];

      masApps = {
        Bitwarden = 1352778147;
        "Yubico Authenticator" = 1497506650;
        "Wipr 2" = 1662217862;
      };
    };
  };
}
