{self, ...}: let
  httpPort = 8000;
  # 553, not 53: NetBird's embedded DNS resolver binds 53 on these hosts.
  dnsPort = 553;

  service = node: module: {
    inherit node module;
    units = ["blocky"];
    ports.http = httpPort;
  };

  listen = host: port:
    if host == null
    then port
    else "${host}:${toString port}";

  mkBlocky = host: {
    config,
    lib,
    ...
  }: {
    services.blocky = {
      enable = true;
      settings = {
        blocking = {
          blockType = "nxDomain";
          clientGroupsBlock.default = ["ads"];
          denylists.ads = [
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
            "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@37522026.259.33134/hosts/pro.plus.txt"
            "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@37522026.259.33134/hosts/tif.txt"
          ];
        };
        customDNS.mapping = {};
        prometheus.enable = true;
        ports = {
          dns = listen host dnsPort;
          http = listen host httpPort;
        };
        upstreams.groups.default = [
          "1.1.1.1"
          "1.0.0.1"
          "8.8.8.8"
          "8.8.4.4"
          "9.9.9.9"
          "149.112.112.112"
          "tcp-tls:one.one.one.one:853"
          "tcp-tls:dns.google:853"
          "tcp-tls:dns.quad9.net:853"
        ];
        log = {
          level = "info";
          format = "text";
        };
      };
    };

    systemd.services.blocky = lib.mkMerge [
      {
        after = [(config.services.netbird.clients.default.service.name + ".service")];
        wants = [(config.services.netbird.clients.default.service.name + ".service")];
        serviceConfig.MemoryMax = "512M";
      }
      (lib.mkIf (host != null) {
        # The mesh address appears only once NetBird connects; keep retrying the bind until then.
        startLimitIntervalSec = 0;
        serviceConfig.RestartSec = 5;
      })
    ];
  };
in {
  legion.services = {
    blocky = service "vida" "blocky";
    blocky-ricklent = service "ricklent" "blocky-ricklent";
  };

  nixos.modules = {
    blocky = mkBlocky null;
    blocky-ricklent = mkBlocky self.lib.netbirdPeers.ricklent;
  };
}
