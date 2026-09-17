_: {
  darwin.modules.system = {config, ...}: {
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

    system = {
      primaryUser = config.preferences.user.name;

      # macOS caps TCP autotuning at 4 MB per socket, which at the ~85 ms to
      # the Legion nodes holds one stream near 400 Mbps. sysctl writes are
      # not persistent: this reapplies on every switch, and a reboot reverts
      # it until the next one.
      activationScripts.postActivation.text = ''
        sysctl -w net.inet.tcp.autosndbufmax=16777216 net.inet.tcp.autorcvbufmax=16777216
      '';

      # Current max supported by the pinned nix-darwin (config.system.maxStateVersion).
      stateVersion = 7;
    };
  };
}
