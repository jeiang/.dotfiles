{config, ...}: let
  inherit (config.darwin) modules;
in {
  darwin.configurations.zakkart.module = {
    imports = [modules.base];

    nixpkgs.hostPlatform = "aarch64-darwin";
  };
}
