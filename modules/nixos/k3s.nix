{
  flake = {
    nixosModules.k3s = {
      lib,
      config,
      ...
    }: {
      networking.firewall = {
        allowedTCPPorts = [6443 10250];
        allowedUDPPorts = [8472];
      };
      services.k3s = {
        enable = true;
        role = lib.mkDefault "agent";
        tokenFile = config.sops.secrets."k3s/token".path;
      };
      sops.secrets = {
        "k3s/token".owner = "root";
      };
    };
  };
}
