{self, ...}: let
  # Every host (Legion + artemis) runs LibreSpeed on the same port, so this
  # is a fleet-wide constant rather than a per-host lookup; exposed for
  # modules/edge (public speed.jeiang.dev route) and modules/glance (mesh
  # links).
  speedtestPort = 8989;
in {
  flake.lib.speedtestPort = speedtestPort;

  # LibreSpeed on every NixOS host. Each host serves its own plain-http
  # page on the mesh listing all five hosts, so any page can test any
  # peer; speed.jeiang.dev (modules/edge) fronts legion-node1's
  # instance for the public path with a one-entry list, because a https
  # page cannot call these http listeners. iperf3 rides along for raw
  # numbers from headless hosts. Neither opens a firewall port: the
  # netbird interface is already trusted (modules/netbird.nix).
  nixos.modules.base = {lib, ...}: {
    services = {
      librespeed = {
        enable = true;
        settings.listen_port = speedtestPort;
        # Without an ipinfo key the module's default ExecStartPre fetches a
        # GeoIP database on every start, gating the unit on outbound HTTP.
        downloadIPDB = false;
        frontend = {
          enable = true;
          pageTitle = "Speed test";
          contactEmail = "";
          settings.telemetry_level = "off";
          servers =
            lib.mapAttrsToList (name: ip: {
              name = "${name} (mesh)";
              server = "//${ip}:${toString speedtestPort}";
            })
            self.lib.netbirdPeers;
        };
      };
      iperf3.enable = true;
    };
  };
}
