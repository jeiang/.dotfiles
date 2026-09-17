{config, ...}: let
  inherit (config.darwin) modules;
in {
  darwin.configurations.zakkart.module = modules.zakkartConfiguration;

  darwin.modules.zakkartConfiguration = _: {
    imports = [
      modules.base
      modules.nix
      modules.hjem
      modules.homebrew
      modules.apps
      modules.system
      modules.preferences
    ];

    nixpkgs.hostPlatform = "aarch64-darwin";
  };
}
