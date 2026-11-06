{
  inputs,
  lib,
  withSystem,
  self,
  ...
}: let
  nixpkgsConfig.allowUnfree = true;

  caches = [
    {
      url = self.lib.facts.cacheUrl;
      key = self.lib.facts.cacheKey;
    }
    {
      url = "https://cache.numtide.com";
      key = "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=";
    }
  ];
  workstationCaches = [
    {
      url = "https://devenv.cachix.org";
      key = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    }
  ];
  urls = map (c: c.url);
  keys = map (c: c.key);

  # Self-hosted cache; do not let an outage stall deploys
  settings = {
    connect-timeout = 5;
    fallback = true;
  };
  # for direnv GC roots
  workstationSettings = {
    keep-derivations = true;
    keep-outputs = true;
  };
in {
  perSystem = {system, ...}: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config = nixpkgsConfig;
    };
  };

  shared.modules.base = {config, ...}: {
    nixpkgs.pkgs = withSystem config.nixpkgs.hostPlatform.system ({pkgs, ...}: pkgs);

    hjem.users.${self.lib.facts.userName}.files.".config/nixpkgs/config.nix".text = lib.generators.toPretty {} nixpkgsConfig + "\n";
  };

  shared.modules.workstation.programs.direnv.enable = true;

  nixos.modules.base = {config, ...}: {
    imports = [
      # Determinate keeps the stock nix.* options and renders them to /etc/nix/nix.custom.conf.
      inputs.determinate.nixosModules.default
    ];

    programs.nh.enable = true;

    # determinate-nixd collects garbage, but every system generation is a GC root it never deletes. Prune
    # old generations only (no store GC, which would be a second collector); the next switch drops their
    # boot entries.
    systemd.services.prune-generations = {
      description = "Delete system generations beyond the newest 14";
      startAt = "weekly";
      serviceConfig.Type = "oneshot";
      script = "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +14";
    };
    systemd.timers.prune-generations.timerConfig.Persistent = true;

    nix = {
      registry.nixpkgs.flake = inputs.nixpkgs;
      nixPath = ["nixpkgs=flake:nixpkgs"];

      settings =
        settings
        // {
          auto-optimise-store = true;
          builders-use-substitutes = true;
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          flake-registry = "/etc/nix/registry.json";
          substituters = urls caches;
          trusted-public-keys = keys caches;
          trusted-users = ["root"];
        };
    };
  };

  # Determinate Nix forces nix.enable = false, so every nix.settings equivalent must go through determinateNix.customSettings.
  darwin.modules.base = {
    imports = [inputs.determinate.darwinModules.default];

    determinateNix = {
      registry.nixpkgs.flake = inputs.nixpkgs;

      customSettings =
        settings
        // workstationSettings
        // {
          # extra-, not the bare keys: customSettings does no NixOS-style merging, so bare substituters/trusted-public-keys would replace Determinate's defaults and drop cache.nixos.org.
          extra-substituters = urls (caches ++ workstationCaches);
          extra-trusted-public-keys = keys (caches ++ workstationCaches);
          # @admin, not @wheel: macOS's wheel group has no members besides root.
          extra-trusted-users = ["@admin"];
        };
    };
  };

  nixos.modules.artemis = {
    imports = [
      inputs.nix-index-database.nixosModules.nix-index
    ];

    programs = {
      nix-index-database.comma.enable = true;
      nix-ld.enable = true;
    };

    nix = {
      # Builds yield to games and streaming.
      daemonCPUSchedPolicy = "idle";
      daemonIOSchedClass = "idle";

      settings =
        workstationSettings
        // {
          substituters = urls workstationCaches;
          trusted-public-keys = keys workstationCaches;
        };
    };

    persistence = {
      data.directories = [".local/share/direnv" ".local/share/devenv"];
      cache.directories = [".cache/devenv" ".cache/direnv" ".cache/nix-direnv"];
    };
  };
}
