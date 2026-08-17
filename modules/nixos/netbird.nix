{self, ...}: {
  flake.nixosModules.netbird = {
    config,
    pkgs,
    ...
  }: {
    services.netbird = {
      enable = true;
      package = self.packages.${pkgs.stdenv.hostPlatform.system}.netbird;
      useRoutingFeatures = "both";
      clients.default.config = let
        urlConfig = {
          Scheme = "https";
          Opaque = "";
          User = null;
          Host = "netbird.jeiang.dev:443";
          Path = "";
          RawPath = "";
          OmitHost = false;
          ForceQuery = false;
          RawQuery = "";
          Fragment = "";
          RawFragment = "";
        };
      in {
        ManagementURL = urlConfig;
        AdminUrl = urlConfig;
        # Never answer mesh :22 with netbird's embedded SSH server -- it
        # has a crippled PATH/env (no nix-daemon), which breaks anything
        # protocol-shaped over mesh ssh, e.g. deploy-rs remote builds to
        # artemis.jeiang.vpn. With it off, mesh ssh reaches the real sshd
        # (trustedInterfaces already admits it).
        ServerSSHAllowed = false;
      };
    };

    networking.firewall.trustedInterfaces = [
      config.services.netbird.clients.default.interface
    ];
  };
}
