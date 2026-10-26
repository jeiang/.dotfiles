{
  self,
  inputs,
  config,
  lib,
  ...
}: let
  peers = self.lib.netbirdPeers;
  services = config.legion.services;
  nodeExporterPort = host: self.nixosConfigurations.${host}.config.services.prometheus.exporters.node.port;

  # Blocky binds its DNS port on vida and on ricklent's mesh IP; the
  # nameserver order (vida first) is the resolver preference.
  blockyNodes = map (s: services.${s}.node) ["blocky" "blocky-ricklent"];
  blockyDnsPort = self.nixosConfigurations.vida.config.services.blocky.settings.ports.dns;

  # Every connection between Legion machines that crosses the mesh: Hetzner
  # nodes reach each other on the private network, so these all involve
  # ricklent or artemis. The policies allow their ports between any Legion
  # machines, so a re-enrolled peer needs no policy edit.
  meshFlows = [
    {
      from = "ricklent";
      to = "alda";
      proto = "tcp";
      port = services.crowdsec.ports.lapi;
      why = "CrowdSec agent and Atlanta proxy bouncer to the LAPI";
    }
    {
      from = "ricklent";
      to = "zantark";
      proto = "tcp";
      port = services.monitoring.ports.victoria-logs;
      why = "journald upload";
    }
    {
      from = "zantark";
      to = "ricklent";
      proto = "tcp";
      port = nodeExporterPort "ricklent";
      why = "node exporter scrape";
    }
    {
      from = "zantark";
      to = "ricklent";
      proto = "tcp";
      port = services.blocky-ricklent.ports.http;
      why = "Blocky metrics";
    }
    {
      from = "zantark";
      to = "ricklent";
      proto = "tcp";
      port = services.netbird-proxy-atl.ports.health;
      why = "Atlanta proxy health and metrics";
    }
    {
      from = "zantark";
      to = "artemis";
      proto = "tcp";
      port = nodeExporterPort "artemis";
      why = "node exporter scrape";
    }
    {
      from = "alda";
      to = "artemis";
      proto = "tcp";
      port = self.lib.atriumWebPort;
      why = "Caddy to atrium";
    }
    {
      from = "artemis";
      to = "zantark";
      proto = "tcp";
      port = services.monitoring.ports.grafana;
      why = "atrium and the MCP Grafana server";
    }
    {
      from = "artemis";
      to = "zantark";
      proto = "tcp";
      port = services.atuin.ports.app;
      why = "atuin sync";
    }
    {
      from = "ricklent";
      to = "artemis";
      proto = "tcp";
      port = self.lib.minecraftJavaPort;
      why = "game ingress";
    }
    {
      from = "ricklent";
      to = "artemis";
      proto = "tcp";
      port = self.lib.minecraftBedrockPort;
      why = "game ingress";
    }
    {
      from = "ricklent";
      to = "artemis";
      proto = "udp";
      port = self.lib.minecraftBedrockPort;
      why = "game ingress";
    }
    {
      from = "ricklent";
      to = "artemis";
      proto = "udp";
      port = self.lib.factorioPort;
      why = "game ingress";
    }
  ];
  meshPorts = proto: lib.unique (map (f: toString f.port) (builtins.filter (f: f.proto == proto) meshFlows));

  rule = name: r:
    {
      inherit name;
      enabled = true;
      action = "accept";
      bidirectional = false;
      protocol = "all";
    }
    // r;
  policy = name: r: {
    inherit name;
    description = "";
    enabled = true;
    rules = [(rule name r)];
    source_posture_checks = [];
  };
  resource = name: {
    id = name;
    type = "subnet";
  };

  # Location tags. Each zone's group routes its own exit, "VPN via <zone>".
  # A group, not a peer, is the router, so a router can be deleted and
  # re-enrolled (a peer used as a router cannot be).
  nodesOn = provider: builtins.attrNames (lib.filterAttrs (_: n: n.provider == provider) self.lib.legionNodes);
  zones = {
    hetzner-us-east = {
      name = "Hetzner (us-east)";
      peers = nodesOn "hetzner";
      users = "vpn";
    };
    linode-atl = {
      name = "Linode (Atlanta)";
      peers = nodesOn "linode";
      users = "vpn";
    };
    trinidad = {
      name = "Trinidad";
      peers = ["artemis"];
      users = "infra_admin";
    };
  };

  netbird = {
    netbird = {
      server = "https://netbird.jeiang.dev";
      prune = lib.genAttrs ["posture_checks" "groups" "networks" "network_resources" "network_routers" "nameserver_groups" "policies" "setup_keys" "services" "service_users" "tokens"] (_: true);

      account.settings = {
        network_range = self.lib.netbirdMeshCidrv4;
        network_range_v6 = self.lib.netbirdMeshCidrv6;
        dns_domain = "jeiang.vpn";
        ipv6_enabled_groups = ["All"];
        # Groups are NetBird's own; Pocket ID only decides who may sign in
        # (its NetBird OIDC client is limited to the `netbird` group).
        jwt_groups_enabled = false;
        jwt_groups_claim_name = "groups";
        jwt_allow_groups = [];
        groups_propagation_enabled = true;
        regular_users_view_blocked = true;
        peer_login_expiration_enabled = true;
        peer_login_expiration = 86400;
        peer_inactivity_expiration_enabled = false;
        peer_inactivity_expiration = 600;
        peer_hostname_collision_rejected = false;
        peer_expose_enabled = false;
        peer_expose_groups = [];
        routing_peer_dns_resolution_enabled = true;
        lazy_connection_enabled = false;
        agent_network_only = false;
        metrics_push_enabled = true;
        auto_update_version = "disabled";
        auto_update_always = false;
        local_mfa_enabled = false;
        extra = {
          peer_approval_enabled = false;
          user_approval_required = false;
          network_traffic_logs_enabled = false;
          network_traffic_packet_counter_enabled = false;
        };
      };
      dns_settings.disabled_management_groups = [];

      groups =
        {
          # Every machine in modules/netbird-peers.nix. The Legion setup key
          # also adds new enrollments here.
          Legion.peers = builtins.attrNames peers;
          blocky.peers = blockyNodes;
          # Assigned through users' auto_groups; members are not declared.
          infra_admin = {};
          vpn = {};
          members = {};
        }
        // lib.mapAttrs (_: z: {inherit (z) peers;}) zones;

      peers =
        lib.mapAttrs (_: ip: {
          inherit ip;
          ssh_enabled = false;
          login_expiration_enabled = false;
          inactivity_expiration_enabled = false;
          approval_required = false;
        })
        peers;

      users = {
        aidan = {
          id = "CiRkNjc3ZmNlYS1jZTgxLTRmYjUtYmQyNC03OWMzZmIyOTkwZjISHXBvY2tldGlkLWQ4dDljY21qa202MDAwOGJhaW4w";
          auto_groups = ["infra_admin" "vpn" "members"];
        };
        archange = {
          id = "CiRlMWM3MzY4OS04MWRhLTRjZGEtOGRjOS00ZDY0NWVkMDU4ZmESHXBvY2tldGlkLWQ4dDljY21qa202MDAwOGJhaW4w";
          role = "user";
          auto_groups = ["vpn" "members"];
        };
        justin = {
          id = "CiQ2YjVjZWNmMS00NDZjLTQxYjUtOGU3My0yZmZhZjYzZTg4ZmQSHXBvY2tldGlkLWQ4dDljY21qa202MDAwOGJhaW4w";
          role = "user";
          auto_groups = ["vpn" "members"];
        };
      };

      service_users = {
        nb-nix = {
          role = "admin";
          auto_groups = [];
          tokens.deploy = {
            expires_in = 365;
            renew_before_days = 30;
            sink.command = ["sops" "set" "--value-stdin" "modules/sops/secrets.admin.yaml" ''["netbird"]["nb-nix-token"]''];
          };
        };
        ci = {
          name = "cornn-flaek CI checks";
          role = "auditor";
          auto_groups = [];
          tokens.ci = {
            name = "CI Token";
            expires_in = 365;
            renew_before_days = 30;
            sink = {
              command = ["gh" "secret" "set" "NETBIRD_READ_TOKEN" "--repo" "jeiang/.dotfiles"];
              format = "raw";
            };
          };
        };
      };

      setup_keys.legion = {
        name = "Legion";
        type = "reusable";
        usage_limit = 0;
        ephemeral = false;
        revoked = false;
        allow_extra_dns_labels = true;
        auto_groups = ["Legion"];
        sink.command = ["sops" "set" "--value-stdin" "modules/hosts/legion/secrets.yaml" ''["netbird"]["setup-key"]''];
      };

      networks =
        {
          home-lan = {
            name = "Home LAN";
            description = "";
            resources.home-network = {
              name = "Home Network";
              address = "192.168.100.0/24";
              description = "";
              enabled = true;
            };
            routers.artemis = {
              peer_groups = ["trinidad"];
              masquerade = true;
              metric = 9999;
              enabled = true;
            };
          };
        }
        // lib.mapAttrs' (group: z:
          lib.nameValuePair "vpn-${group}" {
            name = "VPN via ${z.name}";
            description = "";
            resources.public-internet = {
              name = "VPN via ${z.name}";
              address = "0.0.0.0/0";
              description = "";
              enabled = true;
            };
            routers.exit = {
              peer_groups = [group];
              masquerade = true;
              metric = 9999;
              enabled = true;
            };
          })
        zones;

      nameserver_groups = {
        blocky = {
          name = "Blocky";
          description = "";
          primary = true;
          domains = [];
          search_domains_enabled = false;
          enabled = true;
          groups = ["members"];
          nameservers =
            map (node: {
              ip = peers.${node};
              ns_type = "udp";
              port = blockyDnsPort;
            })
            blockyNodes
            ++ [
              {
                ip = "9.9.9.9";
                ns_type = "udp";
                port = 53;
              }
            ];
        };
        # Never a search domain: clients would append jeiang.dev to every
        # single-label name, and the jeiang.dev wildcard record answers them all.
        quad9 = {
          name = "Quad9 DNS (jeiang.dev overrides)";
          description = "Quad9 DNS Servers";
          primary = false;
          domains = ["jeiang.dev"];
          search_domains_enabled = false;
          enabled = true;
          groups = ["All"];
          nameservers = [
            {
              ip = "9.9.9.9";
              ns_type = "udp";
              port = 53;
            }
            {
              ip = "149.112.112.112";
              ns_type = "udp";
              port = 53;
            }
          ];
        };
      };

      policies =
        {
          blocky-tcp = policy "Blocky DNS Access (TCP)" {
            sources = ["All"];
            destinations = ["blocky"];
            protocol = "tcp";
            ports = [(toString blockyDnsPort)];
          };
          blocky-udp = policy "Blocky DNS Access (UDP)" {
            sources = ["All"];
            destinations = ["blocky"];
            protocol = "udp";
            ports = [(toString blockyDnsPort)];
          };
          admin-devices = policy "Admin Devices" {
            sources = ["infra_admin"];
            destinations = ["infra_admin"];
            bidirectional = true;
          };
          admin-to-legion = policy "Admin to Legion" {
            sources = ["infra_admin"];
            destinations = ["Legion"];
          };
          legion-mesh-tcp = policy "Legion Mesh (TCP)" {
            sources = ["Legion"];
            destinations = ["Legion"];
            protocol = "tcp";
            ports = meshPorts "tcp";
          };
          legion-mesh-udp = policy "Legion Mesh (UDP)" {
            sources = ["Legion"];
            destinations = ["Legion"];
            protocol = "udp";
            ports = meshPorts "udp";
          };
          home-network = policy "Home Network Access" {
            sources = ["infra_admin"];
            destinationResource = resource "Home Network";
          };
        }
        // lib.mapAttrs' (group: z:
          lib.nameValuePair "vpn-${group}" (policy "VPN via ${z.name} Access" {
            sources = [z.users];
            destinationResource = resource "VPN via ${z.name}";
          }))
        zones;
    };
  };
in {
  perSystem = {pkgs, ...}: let
    desired =
      (inputs.nb-nix.lib.evalConfig {
        inherit pkgs;
        modules = [netbird];
      })
      .config
      .netbird
      .desiredFile;
  in {
    # Input to `just netbird-plan` and the NetBird drift check.
    packages.netbird-desired = desired;
    checks.netbird-desired = desired;
  };
}
