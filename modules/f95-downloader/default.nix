{
  inputs,
  self,
  ...
}: let
  unit = "f95-downloader";
  stateDir = "/var/lib/${unit}";
  tokenSecret = "f95-downloader/token";
in {
  nixos.modules.artemis = {
    config,
    lib,
    ...
  }: let
    user = config.preferences.user.name;
  in {
    imports = [inputs.f95-tracker.nixosModules.downloader];

    sops.secrets.${tokenSecret} = {
      sopsFile = ./secrets.yaml;
      restartUnits = ["${unit}.service"];
    };

    services.f95-downloader = {
      enable = true;
      inherit user stateDir;
      group = config.users.users.${user}.group;
      trackerUrl = self.lib.f95TrackerUrl;
      tokenFile = config.sops.secrets.${tokenSecret}.path;
    };

    persistence.directories = [stateDir];

    # Downloads would eat the uplink a remote Moonlight session needs.
    gaming.pauseUnits = ["${unit}.service"];
  };
}
