{self, ...}: let
  node2 = self.lib.legionNodes.legion-node2;
  blockyDnsPort = self.nixosConfigurations.legion-node2.config.services.blocky.settings.ports.dns;

  expected = {
    # The Quad9 nameserver group matching this domain must never mark it as
    # a search domain (netbird-dns-config.md: node1's wildcard trap).
    quad9Domain = "jeiang.dev";
    # The primary (all-domains) nameserver group: Blocky on node2, then
    # Quad9 as failover.
    primaryNameservers = [
      {
        ip = node2.privateIPv4;
        port = blockyDnsPort;
      }
      {
        ip = "9.9.9.9";
        port = 53;
      }
    ];
    # Bare IP: matched against a Networks resource address with or without /32.
    legionNode2Ip = node2.privateIPv4;
    autoUpdateVersion = "disabled";
    crowdsecMode = "enforce";
  };
in {
  flake.lib.netbirdInvariantsExpectedJson = builtins.toJSON expected + "\n";
}
