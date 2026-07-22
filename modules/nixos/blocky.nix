_: {
  # Blocky DNS for legion-node2 (moved from legion-node3 for capacity
  # reasons), reachable only from NetBird peers (replaces the dropped
  # Kubernetes NetworkResource). First-party `services.blocky` (DESIGN.md
  # Service Ownership). No explicit prometheus section is configured:
  # metrics ride the same `ports.http` listener.
  flake.nixosModules.blocky = {config, ...}: {
    services.blocky = {
      enable = true;
      settings = {
        blocking = {
          blockType = "nxDomain";
          clientGroupsBlock.default = ["ads"];
          denylists.ads = [
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
            "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@37522026.188.69901/hosts/pro.plus.txt"
            "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@37522026.188.69901/hosts/tif.txt"
          ];
        };
        customDNS.mapping = {};
        ports = {
          dns = 53;
          http = 8000;
        };
        upstreams.groups.default = [
          "1.1.1.1"
          "8.8.8.8"
          "8.8.4.4"
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

    # The NetBird interface's IP isn't known at eval time (assigned by the
    # tunnel at runtime), so `services.blocky.settings.ports.dns` above
    # stays a bare port (binds 0.0.0.0, every interface) rather than an
    # `<ip>:53` pin. Reachability is scoped by the firewall instead:
    # modules/nixos/netbird.nix is imported fleet-wide, which already adds
    # the client's interface to `networking.firewall.trustedInterfaces` --
    # combined with 53 never being added to this node's public/private
    # inventory-derived openings
    # (modules/hosts/legion/_service-inventory.nix `blocky.firewall = []`),
    # that leaves port 53 open only on the NetBird interface, i.e. reachable
    # from NetBird peers only.
    #
    # Startup ordering: wait for the NetBird tunnel so Blocky's port-53
    # listener doesn't win a race against the interface it's meant to serve
    # (harmless either way since the bind is 0.0.0.0, but blocklist
    # downloads need working egress, which the client's own network-online
    # ordering already provides -- this just keeps Blocky from starting
    # before the tunnel it's semantically bound to conceptually exists).
    systemd.services.blocky = {
      after = [(config.services.netbird.clients.default.service.name + ".service")];
      wants = [(config.services.netbird.clients.default.service.name + ".service")];
    };

    # Single point of failure: peer DNS runs as a single instance on
    # legion-node2, no replica/HPA equivalent. Accepted by the operator.

    # The old 1.22 GiB "peak" reading was an artifact of a prior no-limits
    # config; blocklist load caps real usage at <=350 MiB.
    systemd.services.blocky.serviceConfig.MemoryMax = "512M";

    # Stateless (Workload Inventory: Blocky "none"): blocklists are
    # re-downloaded on start, so no Volume/backupSet -- matches the
    # `blocky` entry in modules/hosts/legion/_service-inventory.nix
    # (stateful = false, no volume, no backupSet).
  };
}
