{config, ...}: let
  inherit (config.darwin) modules;
in {
  darwin.configurations.zakkart.module = {
    imports = [modules.base];

    networking = {
      hostName = "zakkart";
      computerName = "zakkart";
    };

    nixpkgs.hostPlatform = "aarch64-darwin";
  };
}
