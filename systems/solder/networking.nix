_: {
  networking = {
    interfaces.enp1s0 = {
      # set the correct ip for ipv6
      ipv6.addresses = [
        {
          address = "2a01:4ff:f0:d8d2::1";
          prefixLength = 64;
        }
      ];
      ipv6.routes = [
        {
          address = "fe80::1";
          prefixLength = 128;
        }
      ];
    };

    # Set default IPv6 gateway
    defaultGateway6 = {
      address = "fe80::1";
      interface = "enp1s0";
    };

    # Disable privacy extensions (critical for servers)
    tempAddresses = "disabled";

    # configure firewall
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        80
        443
      ];
    };
  };
}
