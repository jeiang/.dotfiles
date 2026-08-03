{self, ...}: {
  flake.darwinModules.netbird = {
    pkgs,
    lib,
    ...
  }: let
    netbird = self.packages.${pkgs.stdenv.hostPlatform.system}.netbird;
  in {
    environment.systemPackages = [netbird];

    # Mirrors nixpkgs' own NixOS module (services.networking.netbird:
    # `ExecStart = "${getExe client.wrapper} service run";`, no extra
    # flags) -- netbird's own config/log defaults are enough for a single
    # client peer.
    launchd.daemons.netbird = {
      command = "${lib.getExe netbird} service run";
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/netbird.log";
        StandardErrorPath = "/var/log/netbird.log";
      };
    };
  };
}
