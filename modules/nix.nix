{
  inputs,
  withSystem,
  self,
  ...
}: {
  perSystem = {system, ...}: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  };

  nixos.modules.base = {config, ...}: {
    imports = [
      # Determinate keeps the stock nix.* options and renders them to /etc/nix/nix.custom.conf.
      inputs.determinate.nixosModules.default
    ];

    nixpkgs.pkgs = withSystem config.nixpkgs.hostPlatform.system ({pkgs, ...}: pkgs);

    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 7d --keep 14";
    };

    nix = {
      registry.nixpkgs.flake = inputs.nixpkgs;
      # set the path for channels compat
      nixPath = ["nixpkgs=flake:nixpkgs"];

      settings = {
        auto-optimise-store = true;
        builders-use-substitutes = true;
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        flake-registry = "/etc/nix/registry.json";

        # Self-hosted cache; do not let an outage stall deploys
        connect-timeout = 5;
        fallback = true;

        substituters = [
          self.lib.facts.cacheUrl
        ];
        trusted-public-keys = [
          self.lib.facts.cacheKey
        ];
        trusted-users = ["root"];
      };
    };

    hjem.users.${config.preferences.user.name}.files.".config/nixpkgs/config.nix".text = self.lib.facts.allowUnfreeConfigNix;
  };

  # Determinate Nix forces nix.enable = false, so every nix.settings equivalent must go through determinateNix.customSettings.
  darwin.modules.base = {config, ...}: {
    imports = [inputs.determinate.darwinModules.default];

    nixpkgs.pkgs = withSystem config.nixpkgs.hostPlatform.system ({pkgs, ...}: pkgs);

    determinateNix = {
      registry.nixpkgs.flake = inputs.nixpkgs;

      customSettings = {
        connect-timeout = 5;
        fallback = true;

        keep-derivations = true;
        keep-outputs = true;

        # extra-, not the bare keys: customSettings does no NixOS-style merging, so bare substituters/trusted-public-keys would replace Determinate's defaults and drop cache.nixos.org.
        extra-substituters = [
          self.lib.facts.cacheUrl
        ];
        extra-trusted-public-keys = [
          self.lib.facts.cacheKey
        ];
        # @admin, not @wheel: macOS's wheel group has no members besides root.
        extra-trusted-users = ["@admin"];
      };
    };

    hjem.users.${config.preferences.user.name}.files.".config/nixpkgs/config.nix".text = self.lib.facts.allowUnfreeConfigNix;
  };

  nixos.modules.artemis = {
    imports = [
      inputs.nix-index-database.nixosModules.nix-index
    ];

    programs = {
      nix-index-database.comma.enable = true;
      direnv = {
        enable = true;
        silent = false;
        loadInNixShell = true;
        nix-direnv.enable = true;
      };
      nix-ld.enable = true;
    };

    # for direnv GC roots
    nix.settings = {
      keep-derivations = true;
      keep-outputs = true;
    };

    persistence = {
      data.directories = [".local/share/direnv" ".local/share/devenv"];
      cache.directories = [".cache/devenv" ".cache/direnv" ".cache/nix-direnv"];
    };
  };
}
