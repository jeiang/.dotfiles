_: {
  flake.darwinModules.system = {config, ...}: {
    system.primaryUser = config.preferences.user.name;

    security.pam.services.sudo_local.touchIdAuth = true;

    networking = {
      hostName = "zakkart";
      computerName = "zakkart";
      # localHostName defaults to hostName already.

      applicationFirewall = {
        enable = true;
        allowSigned = true;
        allowSignedApp = true;
      };
    };

    time.timeZone = "America/Port_of_Spain";

    # Current max supported by the pinned nix-darwin (config.system.maxStateVersion).
    system.stateVersion = 7;
  };
}
