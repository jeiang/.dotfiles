{inputs, ...}: {
  darwin.modules.base = {config, ...}: {
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
        upgrade = true;
        cleanup = "zap";
      };

      casks = [
        "helium-browser"
        "gimp"
        "microsoft-word"
        "microsoft-excel"
        "roblox"
        "notion-calendar"
        # The .app manages its own daemon/tunnel (a nix-managed daemon around the netbird CLI would fight it). A switch upgrades the cask but leaves the running daemon on the old build -- bump the netbird-tap input, switch, then `just netbird-update`.
        "netbirdio/tap/netbird-ui"
      ];

      brews = [
        "k06a/tap/macpow"
      ];

      masApps = {
        Bitwarden = 1352778147;
        "Yubico Authenticator" = 1497506650;
        "Wipr 2" = 1662217862;
      };
    };
  };
}
