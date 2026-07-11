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
      # Declared for future opt-in only: legion hosts don't import
      # self.nixosModules.impermanence and persistence.enable defaults to
      # false, so this has no effect until a host explicitly turns
      # persistence on.
      persistence.directories = [
        "/var/lib/rancher/k3s"
        "/var/lib/kubelet"
        "/etc/rancher/k3s"
      ];
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
