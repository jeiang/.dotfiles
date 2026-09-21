{self, ...}: let
  webuiPort = 8081;
  filesPort = 8082;
  # Inside netbird-proxy's ad hoc band, so publishing inbound peers through
  # the proxy later needs no port change here.
  torrentingPort = 42881;
  stateDir = "/var/lib/qbittorrent";
  downloadDir = "${stateDir}/downloads";
in {
  # Web UI, file listing and peer port all ride the NetBird interface, which
  # is already trusted (modules/netbird.nix); nothing here opens a port on
  # the home network, so peers cannot reach the client from outside the mesh.
  nixos.modules.artemis = _: {
    persistence.directories = [stateDir];

    # Seeding would eat the uplink a remote Moonlight session needs.
    gaming.pauseUnits = ["qbittorrent.service"];

    services = {
      qbittorrent = {
        enable = true;
        inherit webuiPort torrentingPort;
        profileDir = stateDir;
        openFirewall = false;
        # The unit reinstalls this file on every start, so the flake owns
        # every preference: a change made in the web UI is lost on the next
        # restart, and gamemode restarts the service for each game.
        serverConfig = {
          LegalNotice.Accepted = true;
          BitTorrent.Session.DefaultSavePath = downloadDir;
          # Nothing may punch a hole in the home router.
          Network.PortForwardingEnabled = false;
          Preferences.WebUI = {
            # Every mesh peer is one of our own hosts, and the firewall is
            # the real boundary; without a match qBittorrent logs a
            # single-use password at each start.
            AuthSubnetWhitelistEnabled = true;
            AuthSubnetWhitelist = "${self.lib.netbirdMeshCidrv4},${self.lib.netbirdMeshCidrv6}";
          };
        };
      };

      darkhttpd = {
        enable = true;
        # The module always adds --ipv6, which makes darkhttpd parse --addr as
        # an IPv6 literal; it clears IPV6_V6ONLY, so :: also takes IPv4.
        address = "::";
        port = filesPort;
        rootDir = downloadDir;
      };
    };

    systemd.tmpfiles.settings.qbittorrent-downloads.${downloadDir}.d = {
      user = "qbittorrent";
      group = "qbittorrent";
      # World-readable: darkhttpd runs under a DynamicUser that is in no
      # group of ours.
      mode = "0755";
    };
  };
}
