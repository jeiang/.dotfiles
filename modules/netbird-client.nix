{self, ...}: {
  darwin.modules.base = {
    lib,
    pkgs,
    ...
  }: let
    packages = self.packages.${pkgs.stdenv.hostPlatform.system};
  in {
    services.netbird = {
      enable = true;
      package = packages.netbird;
    };
    # nix-darwin points NB_CONFIG at config.json; the daemon's existing identity is upstream's default profile.
    launchd.daemons.netbird.serviceConfig.EnvironmentVariables.NB_CONFIG = lib.mkForce "/var/lib/netbird/default.json";

    environment.systemPackages = [packages.netbird-ui];
  };
}
