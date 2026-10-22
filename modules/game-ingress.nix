{self, ...}: let
  node = self.lib.legionNodes.ricklent;
  target = self.lib.netbirdPeers.artemis;
  gamePorts = [
    {
      port = self.lib.minecraftJavaPort;
      proto = "tcp";
    }
    {
      port = self.lib.minecraftBedrockPort;
      proto = "tcp";
    }
    {
      port = self.lib.minecraftBedrockPort;
      proto = "udp";
    }
    {
      port = self.lib.factorioPort;
      proto = "udp";
    }
  ];
in {
  legion.services.game-ingress = {
    node = "ricklent";
    module = "game-ingress";
    units = ["nginx"];
    publishedPorts = gamePorts;
  };

  nixos.modules.game-ingress = {lib, ...}: {
    # Separate sockets bridge both public address families to the IPv4-only mesh;
    # replies return through the proxy, without a public route into the mesh.
    services.nginx = {
      enable = true;
      virtualHosts = lib.mkForce {};
      streamConfig =
        lib.concatMapStringsSep "\n" ({
          port,
          proto,
        }: let
          portString = toString port;
          udp = lib.optionalString (proto == "udp") " udp reuseport";
        in ''
          server {
            listen ${node.publicIPv4}:${portString}${udp};
            listen [${node.publicIPv6}]:${portString}${udp};
            proxy_pass ${target}:${portString};
            proxy_timeout 10m;
          }
        '')
        gamePorts;
    };

    systemd.services.nginx = {
      wants = ["network-online.target"];
      after = ["network-online.target"];
    };
  };
}
