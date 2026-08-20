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
        "netbirdio/homebrew-tap" = inputs.netbird-tap;
      };
    };

    homebrew = {
      enable = true;
      # Keep nix-homebrew's declarative tap set and nix-darwin's Brewfile
      # tap list in sync, per nix-homebrew's own README. Homebrew >= 6.0
      # refuses to load formulae/casks from unofficial taps unless the
      # Brewfile marks them `trusted: true`; every tap here is a pinned
      # flake input, so trusting it declaratively trusts exactly the
      # revision in flake.lock. Redundant-but-harmless on the official
      # homebrew/* taps. Manual `brew trust` doesn't survive activation:
      # the `cleanup = "zap"` pass resets Homebrew's trust file to what
      # the Brewfile declares.
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
        # No working nixpkgs darwin package (ADR 0009's Homebrew-fallback
        # case), same as the rest of this list. qview's own nixpkgs
        # derivation transitively depends on kimageformats, a Linux-only
        # KDE Frameworks package. HandBrake's nixpkgs derivation is marked
        # broken; its cask token was renamed from "handbrake" to
        # "handbrake-app" upstream -- verified against the pinned
        # homebrew-cask tap (Casks/h/handbrake-app.rb).
        "qview"
        "handbrake-app"
        # The desktop client, from NetBird's own tap (not the main
        # homebrew-cask tap -- verified via the GitHub API,
        # netbirdio/homebrew-tap's only cask). The .app bundles and
        # manages its own system daemon/tunnel; that's the reason for the
        # cask here rather than a nix-managed launchd daemon around the
        # netbird CLI (modules/packages/netbird.nix, still used as-is by
        # the Linux hosts) -- two daemons would fight over the same
        # tunnel. The cask does NOT auto-update (no auto_updates stanza,
        # verified against the pinned tap) and onActivation.upgrade is
        # false, so tracking a netbird release means bumping the
        # netbird-tap flake input and running
        # `brew upgrade --cask netbirdio/tap/netbird-ui` after the switch
        # -- keep the tap input roughly in step with the Linux side's
        # version pin (modules/packages/netbird.nix).
        "netbirdio/tap/netbird-ui"
      ];

      brews = [
        "can1357/tap/omp"
        "k06a/tap/macpow"
        # No working nixpkgs darwin package (nixpkgs' mole is marked
        # broken); a plain "mole" formula exists in the pinned
        # homebrew-core (Formula/m/mole.rb, tw93/Mole -- same Mac cleanup
        # tool), so it doesn't need a tap.
        "mole"
        # Not packaged in nixpkgs for darwin (ADR 0009 exception); a plain
        # "displayplacer" formula exists in the pinned homebrew-core
        # (Formula/d/displayplacer.rb v1.4.0, arm64_tahoe bottle), so it
        # doesn't need a tap either.
        "displayplacer"
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
