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
      services.k3s = {
        serverAddr = "https://172.17.0.1:6443";
        extraFlags = [
          "--flannel-iface=enp7s0"
        ];
      };
      boot = {
        kernel = {
          sysctl = {
            "net.ipv4.ip_forward" = 1;
            "net.ipv6.conf.all.forwarding" = 1;
          };
        };
        kernelModules = [
          "br_netfilter"
          "overlay"
          "nf_conntrack"
          "vxlan"
        ];
        loader = {grub = {enable = true;};};
        tmp = {cleanOnBoot = true;};
      };
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
        legion-node1 = {
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
          # forward ipv4 through main node for kubernetes
          networking.nat = {
            enable = true;
            externalInterface = "enp1s0";
            internalInterfaces = ["enp7s0"];
          };
          services.k3s = {
            role = "server";
            nodeIP = "172.17.0.1";
            nodeExternalIP = "178.156.226.145";
            serverAddr = lib.mkForce "";
            extraFlags = [
              "--tls-san=pinard.co.tt"
              "--tls-san=jeiang.dev"
              "--tls-san=aidanpinard.co"
              "--tls-san=178.156.226.145"
              "--tls-san=2a01:4ff:f0:6b8e::1"
            ];
            clusterInit = true;
          };
        };
        legion-node2 = {
          systemd.network.networks = {
            "10-wan".address = [
              "2a01:4ff:f0:a1ff::1/64"
            ];
            "10-control-plane-nat" = natforwarding;
          };
          services.k3s = {
            role = "server";
            nodeIP = "172.17.0.2";
          };
        };
        legion-node3 = {
          systemd.network.networks = {
            "10-wan".address = [
              "2a01:4ff:f0:c52a::1/64"
            ];
            "10-control-plane-nat" = natforwarding;
          };
          services.k3s = {
            role = "server";
            nodeIP = "172.17.0.3";
          };
        };
        legion-node4 = {
          systemd.network.networks = {
            "10-wan".address = [
              "2a01:4ff:f0:ca96::1/64"
            ];
            "10-control-plane-nat" = natforwarding;
          };
          services.k3s.nodeIP = "172.17.0.4";
        };
      };
    deploy.nodes = let
      mkDeploy = name: {
        sshOpts,
        hostname,
      }: {
        inherit hostname sshOpts;
        sudo = "doas -u";
        profiles.system = {
          user = "root";
          path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.${name};
        };
      };
      nodes = {
        legion-node1 = {
          sshOpts = [];
          hostname = "jeiang.dev";
        };
        legion-node2 = {
          sshOpts = ["-J" "jeiang.dev"];
          hostname = "172.17.0.2";
        };
        legion-node3 = {
          sshOpts = ["-J" "jeiang.dev"];
          hostname = "172.17.0.3";
        };
        legion-node4 = {
          sshOpts = ["-J" "jeiang.dev"];
          hostname = "172.17.0.4";
        };
      };
    in
      builtins.mapAttrs mkDeploy nodes;
  };
}
