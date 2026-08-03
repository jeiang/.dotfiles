{inputs, ...}: {
  # nixpkgs-first sourcing with declared Homebrew/App Store exceptions
  # (docs/adr/0009). Homebrew itself and its taps are pinned flake inputs so
  # `mutableTaps = false` has something to pin to instead of `brew tap`
  # mutating state at activation.
  flake.darwinModules.homebrew = {config, ...}: {
    imports = [inputs.nix-homebrew.darwinModules.nix-homebrew];

    nix-homebrew = {
      enable = true;
      enableRosetta = false;
      user = config.preferences.user.name;
      mutableTaps = false;
      # Pin Homebrew itself too, rather than trusting nix-homebrew's own
      # bundled default -- same shape nix-homebrew's own flake.nix uses for
      # that default (a flake = false source with name/version stamped on).
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
      };
    };

    homebrew = {
      enable = true;
      # Keep nix-homebrew's declarative tap set and nix-darwin's Brewfile
      # tap list in sync, per nix-homebrew's own README.
      taps = builtins.attrNames config.nix-homebrew.taps;

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
        # No working nixpkgs darwin package (ADR 0009's Homebrew-fallback
        # case), same as the rest of this list. qview's own nixpkgs
        # derivation transitively depends on kimageformats, a Linux-only
        # KDE Frameworks package. HandBrake's nixpkgs derivation is marked
        # broken; its cask token was renamed from "handbrake" to
        # "handbrake-app" upstream -- verified against the pinned
        # homebrew-cask tap (Casks/h/handbrake-app.rb).
        "qview"
        "handbrake-app"
      ];

      brews = [
        "can1357/tap/omp"
        "k06a/tap/macpow"
        # No working nixpkgs darwin package (nixpkgs' mole is marked
        # broken); a plain "mole" formula exists in the pinned
        # homebrew-core (Formula/m/mole.rb, tw93/Mole -- same Mac cleanup
        # tool), so it doesn't need a tap.
        "mole"
      ];

      # App Store IDs verified against the apps.apple.com Mac listings.
      # Wipr 2 (not the delisted single-word "Wipr") is the current
      # Mac-supported app, confirmed via its App Store page listing macOS
      # 14+ compatibility.
      masApps = {
        Bitwarden = 1352778147;
        "Yubico Authenticator" = 1497506650;
        "Wipr 2" = 1662217862;
      };
    };
  };
}
