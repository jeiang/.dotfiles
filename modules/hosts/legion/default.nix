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
      natforwarding = {
        matchConfig.Name = "enp7s0";
        networkConfig = {
          DHCP = "ipv4";
        };
        dhcpV4Config = {
          UseRoutes = false;
        };
        routes = [
          # hetzner private network
          {
            Destination = "172.16.0.0/12";
            Gateway = "172.16.0.1";
            GatewayOnLink = true;
          }
          # hetzner forwards requests through the primary node
          # this is configured within the web console
          {
            Destination = "0.0.0.0/0";
            Gateway = "172.16.0.1";
            GatewayOnLink = true;
          }
        ];
      };
    in
      builtins.mapAttrs mkLegionSystem {
        legion = {
          systemd.network.networks."10-wan" = {
            address = [
              "2a01:4ff:f0:6b8e::1/64"
              "178.156.226.145/32"
            ];
            routes = [
              {
                Destination = "172.31.1.1/32";
              }
              {
                Gateway = "172.31.1.1";
                GatewayOnLink = true;
              }
            ];
            networkConfig = {
              DHCP = "no";
              IPv6AcceptRA = false;
            };
          };
          boot.kernel.sysctl = {
            "net.ipv4.ip_forward" = 1;
          };

          # forward ipv4 through main node for kubernetes
          networking.nat = {
            enable = true;
            externalInterface = "enp1s0";
            internalInterfaces = ["enp7s0"];
          };

          networking.firewall = {
            trustedInterfaces = ["enp7s0"];
          };
          services.k3s = {
            role = "server";
            nodeIP = "172.16.0.2";
            serverAddr = lib.mkForce "";
            clusterInit = true;
          };
        };
        legion-node1 = {
          systemd.network.networks = {
            "10-wan".address = [
              "2a01:4ff:f0:ca96::1/64"
            ];
            "10-control-plane-nat" = natforwarding;
          };
        };
        legion-node2 = {
          systemd.network.networks = {
            "10-wan".address = [
              "2a01:4ff:f0:c52a::1/64"
            ];
            "10-control-plane-nat" = natforwarding;
          };
        };
        legion-node3 = {
          systemd.network.networks = {
            "10-wan".address = [
              "2a01:4ff:f0:a1ff::1/64"
            ];
            "10-control-plane-nat" = natforwarding;
          };
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
