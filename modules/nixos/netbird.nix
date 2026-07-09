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
        # Set Management URL for netbird configuration file
        ManagementURL = urlConfig;
        AdminUrl = urlConfig;
      };
    };

    networking.firewall.trustedInterfaces = [
      config.services.netbird.clients.default.interface
    ];
  };
}
