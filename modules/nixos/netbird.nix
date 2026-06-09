{
  flake.nixosModules.netbird = {
    config,
    lib,
    ...
  }: {
    config = {
      netbird.client.enable = lib.mkDefault true;
      services = {
        netbird = {
          inherit (config.netbird.client) enable;
          useRoutingFeatures = "both";
        };
      };

      networking.firewall.trustedInterfaces = [
        config.services.netbird.clients.default.interface
      ];
    };
  };
}
