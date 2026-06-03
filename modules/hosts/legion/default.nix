{
  inputs,
  self,
  lib,
  ...
}: {
  flake = {
    nixosModules.legionConfiguration = {...}: {
      imports = [
        self.nixosModules.base
        self.nixosModules.sharedConfiguration
        self.nixosModules.sops
        self.nixosModules.legionHardware
        self.nixosModules.doas
        self.nixosModules.k3s
        self.diskoConfigurations.legion
      ];
      boot.loader.grub.enable = true;
      boot.tmp.cleanOnBoot = true;
      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";
      users.users.root.openssh.authorizedKeys.keys = [
        "AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ"
      ];
    };
    nixosConfigurations = let
      mkLegionSystem = name: additionalConfig:
        inputs.nixpkgs.lib.nixosSystem {
          modules = [
            self.nixosModules.legionConfiguration
            {
              networking.hostName = name;
              services.k3s = {
                serverAddr = "https://172.16.0.2:6443";
                extraFlags = [
                  "--flannel-iface=enp7s0"
                ];
              };
            }
            additionalConfig
          ];
        };
    in
      builtins.mapAttrs mkLegionSystem {
        legion = {
          systemd.network.networks."10-wan".address = [
            "2a01:4ff:f0:6b8e::1/64"
          ];
          services.k3s = {
            role = "server";
            nodeIP = "172.16.0.2";
            serverAddr = lib.mkForce "";
            clusterInit = true;
          };
        };
        legion-node1 = {
          systemd.network.networks."10-wan".address = [
            "2a01:4ff:f0:ca96::1/64"
          ];
        };
        legion-node2 = {
          systemd.network.networks."10-wan".address = [
            "2a01:4ff:f0:c52a::1/64"
          ];
        };
        legion-node3 = {
          systemd.network.networks."10-wan".address = [
            "2a01:4ff:f0:a1ff::1/64"
          ];
        };
      };
    deploy.nodes = let
      mkDeploy = node: {
        hostname = "override-this.example";
        sudo = "doas -u";
        profiles.system = {
          user = "root";
          path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.${node};
        };
      };
      nodes = ["legion" "legion-node1" "legion-node2" "legion-node3"];
    in
      lib.genAttrs nodes mkDeploy;
  };
}
