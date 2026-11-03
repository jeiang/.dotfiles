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
    # The app's own launch-at-login registers through SMAppService, which does not take this bundle: its linker signature does not bind the Info.plist.
    launchd.user.agents.netbird-ui.serviceConfig = {
      ProgramArguments = ["/Applications/Nix Apps/NetBird.app/Contents/MacOS/netbird-ui"];
      RunAtLoad = true;
      ProcessType = "Interactive";
    };
  };
}
