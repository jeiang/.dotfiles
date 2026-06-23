{
  inputs,
  self,
  lib,
  ...
}: let
  publicV4Gateway = "172.31.1.1";
  publicV6Gateway = "fe80::1";

  podCIDRv4 = "10.42.0.0/16";
  podCIDRv6 = "fd42:42::/56";
  serviceCIDRv4 = "10.43.0.0/16";
  serviceCIDRv6 = "fd42:43::/112";

  mkWan = {
    publicIPv4,
    publicIPv6,
  }: {
    address = [
      "${publicIPv4}/32"
      "${publicIPv6}/64"
    ];

    routes = [
      {Destination = "${publicV4Gateway}/32";}
      {
        Gateway = publicV4Gateway;
        GatewayOnLink = true;
      }
      {
        Gateway = publicV6Gateway;
        GatewayOnLink = true;
      }
    ];

    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
    };
  };
in {
  flake = {
    nixosModules.legionConfiguration = {
      imports = [
        self.nixosModules.base
        self.nixosModules.sharedConfiguration
        self.nixosModules.sops
        self.nixosModules.legionHardware
        self.nixosModules.doas
        self.nixosModules.k3s
        self.diskoConfigurations.legion
      ];

      boot = {
        kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
          "net.bridge.bridge-nf-call-iptables" = 1;
          "net.bridge.bridge-nf-call-ip6tables" = 1;
        };

        kernelModules = [
          "br_netfilter"
          "overlay"
          "nf_conntrack"
          "vxlan"
        ];

        loader.grub.enable = true;
        tmp.cleanOnBoot = true;
        supportedFilesystems = ["nfs"];
      };

      systemd.network.networks."20-hcloud-private" = {
        matchConfig.Name = "enp7s0";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config.UseRoutes = false;
        routes = [
          {
            Destination = "172.16.0.0/12";
            Gateway = "172.16.0.1";
            GatewayOnLink = true;
          }
        ];
      };

      services.k3s = {
        role = "server";
        serverAddr = "https://172.17.0.1:6443";

        extraFlags = [
          "--flannel-iface=enp7s0"

          # Required before installing hcloud-cloud-controller-manager.
          "--disable-cloud-controller"
          "--kubelet-arg=cloud-provider=external"

          # Required when using MetalLB instead of K3s ServiceLB.
          "--disable=servicelb"

          # Avoid competing default storage classes when using Hetzner CSI.
          "--disable=local-storage"

          # Dual-stack must be set when the cluster is first created.
          "--cluster-cidr=${podCIDRv4},${podCIDRv6}"
          "--service-cidr=${serviceCIDRv4},${serviceCIDRv6}"
          "--flannel-ipv6-masq"

          "--tls-san=pinard.co.tt"
          "--tls-san=jeiang.dev"
          "--tls-san=aidanpinard.co"
        ];
      };

      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";
    };

    nixosConfigurations = let
      mkLegionSystem = name: node:
        inputs.nixpkgs.lib.nixosSystem {
          modules = [
            self.nixosModules.legionConfiguration
            {
              networking.hostName = name;

              systemd.network.networks."10-wan" = mkWan {
                inherit (node) publicIPv4 publicIPv6;
              };

              services.k3s.nodeIP = "${node.privateIPv4},${node.publicIPv6}";
            }

            (lib.mkIf (node.bootstrap or false) {
              services.k3s = {
                serverAddr = lib.mkForce "";
                clusterInit = true;
              };
            })
          ];
        };
    in
      builtins.mapAttrs mkLegionSystem {
        legion-node1 = {
          bootstrap = true;
          privateIPv4 = "172.17.0.1";
          publicIPv4 = "178.156.226.145";
          publicIPv6 = "2a01:4ff:f0:6b8e::1";
        };

        legion-node2 = {
          privateIPv4 = "172.17.0.2";
          publicIPv4 = "178.156.201.35";
          publicIPv6 = "2a01:4ff:f0:a1ff::1";
        };

        legion-node3 = {
          privateIPv4 = "172.17.0.3";
          publicIPv4 = "178.156.186.147";
          publicIPv6 = "2a01:4ff:f0:c52a::1";
        };

        legion-node4 = {
          privateIPv4 = "172.17.0.4";
          publicIPv4 = "178.156.191.180";
          publicIPv6 = "2a01:4ff:f0:ca96::1";
        };
      };
    deploy.nodes = let
      mkDeploy = name: {hostname}: {
        inherit hostname;
        sudo = "doas -u";
        profiles.system = {
          user = "root";
          path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.${name};
        };
      };
      nodes = builtins.listToAttrs (map (node: {
        name = "legion-${node}";
        value = {hostname = "${node}.jeiang.dev";};
      }) ["node1" "node2" "node3" "node4"]);
    in
      builtins.mapAttrs mkDeploy nodes;
  };
}
