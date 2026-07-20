{
  inputs,
  self,
  lib,
  ...
}: let
  publicV4Gateway = "172.31.1.1";
  publicV6Gateway = "fe80::1";

  podCIDRv4 = "10.42.0.0/16";
  serviceCIDRv4 = "10.43.0.0/16";

  legionNodes = {
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
      agent = true;
    };

    legion-node3 = {
      privateIPv4 = "172.17.0.3";
      publicIPv4 = "178.156.186.147";
      publicIPv6 = "2a01:4ff:f0:c52a::1";
      agent = true;
    };

    legion-node4 = {
      privateIPv4 = "172.17.0.4";
      publicIPv4 = "178.156.191.180";
      publicIPv6 = "2a01:4ff:f0:ca96::1";
      agent = true;
    };

    legion-node5 = {
      # Keep the gap at .5: this is the node's existing address, and changing
      # cluster networking requires confirming the live host state first.
      privateIPv4 = "172.17.0.6";
      publicIPv4 = "178.156.253.100";
      publicIPv6 = "2a01:4ff:f4:13f7::1";
      agent = true;
    };
  };

  bootstrapNodes = lib.filterAttrs (_: node: node.bootstrap or false) legionNodes;
  nodeAddresses = lib.concatMap (node: [node.privateIPv4 node.publicIPv4 node.publicIPv6]) (builtins.attrValues legionNodes);

  legionServices = import ./_service-inventory.nix {inherit lib;};
  unknownServicePlacements = builtins.filter (name: !(legionNodes ? ${name})) (builtins.attrNames legionServices);

  validatedLegionNodes = assert lib.assertMsg (builtins.length (builtins.attrNames bootstrapNodes) == 1)
  "Legion inventory must define exactly one bootstrap node";
  assert lib.assertMsg (builtins.length nodeAddresses == builtins.length (lib.unique nodeAddresses))
  "Legion inventory must not reuse an IP address";
  assert lib.assertMsg (unknownServicePlacements == [])
  "Legion service inventory places services on unknown nodes: ${builtins.concatStringsSep ", " unknownServicePlacements}";
    lib.mapAttrs (name: node: node // (legionServices.${name} or {})) legionNodes;

  # tcp/udp ports a node's placed services open, scoped to "public" or
  # "private" per their firewall.scope (docs/MIGRATION.md piece 0.1/0.2).
  firewallPortsFor = nodeName: proto: scope: let
    openings = lib.concatMap (service: service.firewall or []) (validatedLegionNodes.${nodeName}.services or []);
  in
    lib.unique (map (o: o.port) (builtins.filter (o: o.proto == proto && o.scope == scope) openings));

  bootstrapNode = builtins.head (builtins.attrValues (lib.filterAttrs (_: node: node.bootstrap or false) validatedLegionNodes));
  nodeHostname = name: "${lib.removePrefix "legion-" name}.jeiang.dev";
  apiTlsSans =
    [
      "pinard.co.tt"
      "aidanpinard.co"
      "jeiang.dev"
    ]
    ++ map nodeHostname (builtins.attrNames validatedLegionNodes);

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
      pkgs,
      config,
      ...
    }: {
      imports = [
        self.nixosModules.base
        self.nixosModules.sharedConfiguration
        self.nixosModules.sops
        self.nixosModules.legionHardware
        self.nixosModules.k3s
        self.diskoConfigurations.legion
      ];

      users = {
        groups.deploy = {};
        users.deploy = {
          isSystemUser = true;
          group = "deploy";
          home = "/var/empty";
          createHome = false;
          hashedPassword = "!";
          shell = pkgs.bashInteractive;
          openssh.authorizedKeys.keys = [
            "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGEDR/RgCI/ULKL6ywYbmeqvU5BfjpmMnOieuQ66XlX+ legion-deploy"
          ];
        };
      };

      nix.settings.trusted-users = ["deploy"];

      security.sudo.extraRules = [
        {
          users = ["deploy"];
          runAs = "root";
          commands = [
            {
              command = "/nix/store/*/activate-rs";
              options = ["NOPASSWD"];
            }
          ];
        }
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
          "nf_nat"
          "ip_tables"
          "iptable_nat"
          "iptable_filter"
          "ip6_tables"
          "ip6table_nat"
          "ip6table_filter"
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
        serverAddr = "https://${bootstrapNode.privateIPv4}:6443";

        extraFlags = [
          "--flannel-iface=enp7s0"
          "--kubelet-arg=cloud-provider=external"
        ];
      };

      # Piece 0.2: re-enable the host firewall (hardware.nix flips
      # networking.firewall.enable) with openings derived from the Legion
      # service inventory above, plus the live K3s-era data path that isn't
      # yet represented in the inventory:
      #  - K3s control (6443/10250 tcp, 8472 udp) is opened by
      #    modules/nixos/k3s.nix already.
      #  - Traefik NodePorts targeted by the Hetzner LB (legion-lb1, TCP
      #    web/websecure) and its health checks arrive over the private
      #    network: the LB is annotated `use-private-ip: true` (confirmed
      #    live: NodePorts 30693/tcp, 30297/tcp on the `traefik` Service),
      #    so they're covered by the enp7s0 trust below rather than pinned
      #    here, since NodePort numbers are not stable across Service
      #    recreation.
      #  - STUN (UDP 3478) and H@H's hostPort (TCP 8888) are opened
      #    fleet-wide "for now": the live K3s scheduler can place those
      #    pods on any node today (the NetBird relay has moved nodes
      #    before), and the target placement (netbird-relay on
      #    legion-node2, hath on legion-node4; see _service-inventory.nix)
      #    only takes effect once pieces 3.1/5.4 land. Narrow this during
      #    their cutover runbooks.
      networking.firewall = {
        allowedTCPPorts = firewallPortsFor config.networking.hostName "tcp" "public" ++ [8888];
        allowedUDPPorts = firewallPortsFor config.networking.hostName "udp" "public" ++ [3478];
        # Backend transport boundary (DESIGN.md): K3s/kubelet, flannel
        # VXLAN, and Hetzner LB->NodePort traffic all arrive on the
        # private interface already.
        trustedInterfaces = ["enp7s0"];
      };

      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";
    };

    nixosConfigurations = let
      mkLegionSystem = name: node:
        inputs.nixpkgs.lib.nixosSystem {
          modules =
            [
              self.nixosModules.legionConfiguration
              {
                networking.hostName = name;

                systemd.network.networks."10-wan" = mkWan {
                  inherit (node) publicIPv4 publicIPv6;
                };

                services.k3s = {
                  nodeIP = "${node.privateIPv4}";
                  role =
                    if (node.agent or false)
                    then "agent"
                    else "server";
                  extraFlags = lib.mkIf (!node.agent or false) (
                    [
                      # Required before installing hcloud-cloud-controller-manager.
                      "--disable-cloud-controller"

                      # Required when using MetalLB instead of K3s ServiceLB.
                      "--disable=servicelb"

                      # Avoid competing default storage classes when using Hetzner CSI.
                      "--disable=local-storage"

                      # Dual-stack must be set when the cluster is first created.
                      "--cluster-cidr=${podCIDRv4}"
                      "--service-cidr=${serviceCIDRv4}"
                    ]
                    ++ map (san: "--tls-san=${san}") apiTlsSans
                    ++ [
                      "--kube-apiserver-arg=oidc-issuer-url=https://auth.jeiang.dev"
                      "--kube-apiserver-arg=oidc-client-id=44213aa3-11eb-401d-922c-c7f81c3a9e37"
                      "--kube-apiserver-arg=oidc-username-claim=preferred_username"
                      "--kube-apiserver-arg=oidc-username-prefix=-"
                      "--kube-apiserver-arg=oidc-groups-claim=groups"
                      "--kube-apiserver-arg=oidc-groups-prefix="
                    ]
                  );
                };
              }

              (lib.mkIf (node.bootstrap or false) {
                services.k3s = {
                  serverAddr = lib.mkForce "";
                  clusterInit = true;
                };
              })
            ]
            # Piece 1.1: Caddy Edge Node module, only for the inventory's
            # edge node. Runs alongside K3s until the runbook (piece 1.5)
            # cuts DNS over.
            ++ lib.optional (node.edge or false) self.nixosModules.edge
            # Piece 1.3: CrowdSec engine, same edge-node condition as
            # above. Both modules share the edge.crowdsec.enable toggle.
            ++ lib.optional (node.edge or false) self.nixosModules.crowdsec;
        };
    in
      builtins.mapAttrs mkLegionSystem validatedLegionNodes;
    deploy.nodes =
      builtins.mapAttrs (name: _: {
        hostname = nodeHostname name;
        # The first activation removes doas, so disable its doas-based waiter:
        # deploy .#legion-nodeN --ssh-user aidanp --sudo='doas -u' --magic-rollback=false -- --impure
        sshUser = "deploy";
        sudo = "sudo -u";
        profiles.system = {
          user = "root";
          path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.${name};
        };
      })
      validatedLegionNodes;
  };
}
