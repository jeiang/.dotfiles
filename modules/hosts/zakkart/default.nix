{config, ...}: let
  inherit (config.darwin) modules;
  name = "zakkart";
in {
  darwin.configurations.${name}.module = {
    imports = [modules.base];

    networking = {
      hostName = name;
      computerName = name;
    };

    nixpkgs.hostPlatform = "aarch64-darwin";
  };
}
