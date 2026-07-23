{
  inputs,
  self,
  lib,
  ...
}: let
  publicV4Gateway = "172.31.1.1";
  publicV6Gateway = "fe80::1";

  legionNodes = {
    legion-node1 = {
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

  nodeAddresses = lib.concatMap (node: [node.privateIPv4 node.publicIPv4 node.publicIPv6]) (builtins.attrValues legionNodes);

  legionServices = import ./_service-inventory.nix {inherit lib;};
  unknownServicePlacements = builtins.filter (name: !(legionNodes ? ${name})) (builtins.attrNames legionServices);

  validatedLegionNodes = assert lib.assertMsg (builtins.length nodeAddresses == builtins.length (lib.unique nodeAddresses))
  "Legion inventory must not reuse an IP address";
  assert lib.assertMsg (unknownServicePlacements == [])
  "Legion service inventory places services on unknown nodes: ${builtins.concatStringsSep ", " unknownServicePlacements}";
    lib.mapAttrs (name: node: node // (legionServices.${name} or {})) legionNodes;

  # tcp/udp ports a node's placed services open, scoped to "public" or
  # "private" per their firewall.scope. `publishedPorts` entries
  # (docs/adr/0002-expose-the-netbird-reverse-proxy-directly.md) are
  # folded in here too, always "public" scope: same shape as `firewall`
  # (exact ports), just declared separately since they're the durable
  # published-ports hook rather than a fixed service backend port.
  firewallPortsFor = nodeName: proto: scope: let
    services = validatedLegionNodes.${nodeName}.services or [];
    exactOpenings = lib.concatMap (service: service.firewall or []) services;
    publishedOpenings = lib.concatMap (service: map (p: p // {scope = "public";}) (service.publishedPorts or [])) services;
  in
    lib.unique (map (o: o.port) (builtins.filter (o: o.proto == proto && o.scope == scope) (exactOpenings ++ publishedOpenings)));

  # tcp/udp port *ranges* a node's placed services open, scoped the same
  # way as firewallPortsFor -- separate derivation since
  # networking.firewall.allowedTCPPortRanges/allowedUDPPortRanges take
  # `{from; to;}` attrsets, not bare ports.
  firewallPortRangesFor = nodeName: proto: scope: let
    openings = lib.concatMap (service: service.firewallPortRanges or []) (validatedLegionNodes.${nodeName}.services or []);
  in
    map (o: {inherit (o) from to;}) (builtins.filter (o: o.proto == proto && o.scope == scope) openings);

  nodeHostname = name: "${lib.removePrefix "legion-" name}.jeiang.dev";

  # Observed snapshots exist only to feed the Hermes aggregator, so
  # collection follows the same inventory gate as Hermes itself: nothing
  # runs fleet-wide until the hermes entry flips to enabled.
  hermesFleetEnabled = lib.any (node: lib.any (service: service.name == "hermes" && (service.enabled or false)) (node.services or [])) (builtins.attrValues validatedLegionNodes);

  # The aggregator queries VictoriaMetrics wherever the inventory places
  # `monitoring` (legion-node3 today), so a placement change stays a
  # one-file inventory edit.
  monitoringNode = lib.findFirst (node: lib.any (service: service.name == "monitoring") (node.services or [])) (throw "Legion inventory places no monitoring service") (builtins.attrValues validatedLegionNodes);

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
      lib,
      ...
    }: {
      imports = [
        self.nixosModules.base
        self.nixosModules.sharedConfiguration
        self.nixosModules.sops
        self.nixosModules.legionHardware
        self.nixosModules.backups
        # Every legion node becomes a NetBird peer, reusing artemis's
        # existing client module unmodified (it stays untouched -- only
        # this host layer adds the setup-key wiring below). Replaces the
        # dropped Kubernetes routing peer for peer-only services (Blocky
        # DNS, raw VictoriaMetrics/VictoriaLogs). legion-node1 (the edge)
        # and legion-node2 (the netbird-server host) become peers too --
        # harmless, and node2 enrolling as a peer of the server it also
        # hosts is exactly how NetBird is reached today.
        self.nixosModules.netbird
        self.nixosModules.observedSnapshot
        self.diskoConfigurations.legion
      ];

      # Setup-key enrollment: declared here, not in
      # modules/nixos/netbird.nix, since it's specific to Legion's fleet
      # enrollment rather than the general client module artemis also
      # uses. `services.netbird.clients.default` itself comes from
      # self.nixosModules.netbird above; this only adds the login fields
      # nixpkgs' services.netbird module exposes for declarative setup-key
      # enrollment (nixos/modules/services/networking/netbird.nix
      # `clients.<name>.login.*`).
      #
      # Bootstrap circularity guard: this must never point host DNS at
      # the Blocky instance as the primary resolver. Legion nodes keep
      # systemd-networkd's normal DHCP/upstream resolvers
      # (modules/hosts/legion/hardware.nix `useNetworkd = true`; nothing
      # here or in self.nixosModules.netbird touches
      # networking.nameservers or services.resolved), so
      # `netbird.jeiang.dev` always resolves via public DNS before the
      # tunnel is up -- never via Blocky-over-NetBird. This must be
      # preserved if Blocky's placement ever changes.
      sops.secrets."netbird/setup-key" = {};
      services = {
        netbird.clients.default.login = {
          enable = true;
          setupKeyFile = config.sops.secrets."netbird/setup-key".path;
        };

        # Fleet-wide node_exporter, one per Legion node, scraped
        # by legion-node3's monitoring module
        # (modules/nixos/monitoring/default.nix `job_name = "node"`). Not
        # a "placed" service in the inventory sense
        # (modules/hosts/legion/_service-inventory.nix): every node runs
        # it unconditionally, so it lives here rather than as a per-node
        # inventory entry. Default bind (all interfaces) + no
        # `openFirewall`: same private-network-only reachability as every
        # other cross-node backend in this repo (trustedInterfaces, never
        # added to the public allowlist below).
        prometheus.exporters.node = {
          enable = true;
          # systemd collector: exposes node_systemd_unit_state per unit,
          # feeding the SystemdUnitFailed alert
          # (modules/nixos/monitoring/default.nix fleet-health group).
          # Option names verified against the pinned nixpkgs node exporter
          # module (nixos/modules/services/monitoring/prometheus/exporters/node.nix:
          # `enabledCollectors` renders `--collector.<name>`, `extraFlags`
          # is appended verbatim after `--web.listen-address`).
          enabledCollectors = ["systemd"];
          # Scope the systemd collector to an explicit include-list rather
          # than letting it enumerate every unit on the box. The default
          # (`--collector.systemd.unit-include=.+`) would emit a
          # node_systemd_unit_state series for every unit * every state on
          # all 4 nodes -- hundreds of series -- straight into
          # legion-node3's memory-constrained VictoriaMetrics (MemoryMax
          # 640M, modules/nixos/monitoring/default.nix). This anchored
          # allowlist keeps cardinality to the placed first-party service
          # units only (the union across the whole fleet -- some units
          # exist only on the node that places them, which is fine: the
          # collector simply matches whatever is present per node). Unit
          # names verified by grepping each module's `systemd.services.<n>`
          # (services.atticd -> atticd.service, services.actual ->
          # actual.service, monitoring's vmalert instance ->
          # vmalert-default.service, services.journald.upload ->
          # systemd-journal-upload.service, etc.). Flag name
          # `--collector.systemd.unit-include` (a full-match regexp)
          # confirmed against the pinned node_exporter 1.12.0 binary. The
          # trailing `\.service` restricts matches to service units.
          extraFlags = [
            "--collector.systemd.unit-include=(caddy|crowdsec|crowdsec-firewall-bouncer|atticd|actual|blocky|pocket-id|hath|netbird-server|netbird-relay|netbird-proxy|grafana|victoriametrics|victorialogs|vmalert-default|alertmanager|systemd-journal-upload)\\.service"
          ];
        };

        # Log shipping: journald from every Legion node to
        # legion-node3's VictoriaLogs, via systemd-journal-upload (nixpkgs
        # `services.journald.upload`) pointed at VictoriaLogs' journald
        # ingestion route. systemd-journal-upload always appends `/upload`
        # to the configured URL itself, and VictoriaLogs registers the
        # matching route at `/insert/journald/upload` (confirmed against
        # the pinned victorialogs 1.51.0 binary's embedded route strings)
        # -- so the URL below must end at `/insert/journald`, not
        # `/upload`. Chosen over vlagent/promtail-style shippers: fully
        # declarative, no extra service to configure per-node, and
        # VictoriaLogs supports this ingestion path natively.
        journald.upload = {
          enable = true;
          settings.Upload.URL = "http://${legionNodes.legion-node3.privateIPv4}:9428/insert/journald";
        };
      };

      # Restic backup jobs derived from this node's own inventory entry;
      # modules/nixos/backups.nix evaluates to zero services.restic.backups
      # jobs on a node with no stateful services in its inventory entry.
      backups.jobs = lib.listToAttrs (
        map (service:
          lib.nameValuePair service.name {
            paths = service.backupSet;
            pauseUnits = service.backupPauseUnits or [];
          })
        (builtins.filter (service: service ? backupSet && (service.volume or {}) ? hcloudVolumeId)
          (validatedLegionNodes.${config.networking.hostName}.services or []))
      );

      observedSnapshot = {
        enable = lib.mkDefault hermesFleetEnabled;
        bindAddress = legionNodes.${config.networking.hostName}.privateIPv4;
        services = map (service: "${service.name}.service") (validatedLegionNodes.${config.networking.hostName}.services or []);
        volumes =
          map (service: service.volume.mountpoint)
          (builtins.filter (service: service ? volume) (validatedLegionNodes.${config.networking.hostName}.services or []));
      };

      # Declarative Hetzner Volume mounts, derived from this node's own
      # inventory entries. A service contributes nothing here until its
      # `volume.hcloudVolumeId` is filled in by the operator after
      # creating the Volume -- same "empty until populated" pattern as
      # `backups.jobs` above. `nofail`
      # is required so a missing/late Volume never blocks boot (SSH and
      # deploy access must stay available); the service itself is kept
      # off an unmounted directory by its own mount guard
      # (`unitConfig.ConditionPathIsMountPoint`, see each service module).
      fileSystems = lib.listToAttrs (
        map (service:
          lib.nameValuePair service.volume.mountpoint {
            device = "/dev/disk/by-id/scsi-0HC_Volume_${service.volume.hcloudVolumeId}";
            fsType = "ext4";
            options = ["nofail" "x-systemd.device-timeout=10s"];
          })
        (builtins.filter (service: (service.volume or {}) ? hcloudVolumeId)
          (validatedLegionNodes.${config.networking.hostName}.services or []))
      );

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
            # Magic rollback: after activation succeeds, deploy-rs confirms
            # over a second SSH session with `sudo -u root rm
            # /tmp/deploy-rs-canary-<hash>` (src/deploy.rs confirm_profile).
            # Bare `rm` resolves to the system path for the deploy user, so
            # match it there; without this rule sudo prompts for a password,
            # the confirmation times out, and every deploy rolls back.
            {
              command = "/run/current-system/sw/bin/rm /tmp/deploy-rs-canary-*";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];

      boot = {
        # Required by services.netbird's useRoutingFeatures = "both"
        # (self.nixosModules.netbird, imported fleet-wide above).
        kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };

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

      # Re-enable the host firewall (hardware.nix flips
      # networking.firewall.enable) with openings derived from the Legion
      # service inventory above, plus:
      #  - STUN (UDP 3478) and H@H's hostPort (TCP 8888) are opened
      #    fleet-wide rather than pinned to their owning node
      #    (_service-inventory.nix: netbird-relay on legion-node2, hath on
      #    legion-node4).
      networking.firewall = {
        allowedTCPPorts = firewallPortsFor config.networking.hostName "tcp" "public" ++ [8888];
        allowedUDPPorts = firewallPortsFor config.networking.hostName "udp" "public" ++ [3478];
        allowedTCPPortRanges = firewallPortRangesFor config.networking.hostName "tcp" "public";
        allowedUDPPortRanges = firewallPortRangesFor config.networking.hostName "udp" "public";
        # Backend transport boundary (DESIGN.md): cross-node service
        # traffic arrives on the private interface already.
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
              }
            ]
            # Caddy Edge Node module, only for the inventory's edge node.
            ++ lib.optional (node.edge or false) self.nixosModules.edge
            # CrowdSec engine, same edge-node condition as above. Both
            # modules share the edge.crowdsec.enable toggle.
            ++ lib.optional (node.edge or false) self.nixosModules.crowdsec
            # NetBird server + relay, only for the inventory node that
            # places `netbird-server`
            # (modules/hosts/legion/_service-inventory.nix, legion-node2
            # today). Never imported on any other node.
            ++ lib.optional
            (lib.any (service: service.name == "netbird-server") node.services)
            self.nixosModules.netbird-server
            # NetBird reverse proxy, same optional-import pattern, gated
            # on the inventory node placing `netbird-proxy` (legion-node2
            # today, alongside netbird-server above).
            ++ lib.optional
            (lib.any (service: service.name == "netbird-proxy") node.services)
            self.nixosModules.netbird-proxy
            # Pocket ID, same optional-import pattern, gated on the
            # inventory node placing `pocket-id` (legion-node2 today,
            # alongside netbird-server/netbird-proxy above).
            ++ lib.optional
            (lib.any (service: service.name == "pocket-id") node.services)
            self.nixosModules.pocket-id
            # Attic, same optional-import pattern, gated on the inventory
            # node placing `attic` (legion-node4 today).
            ++ lib.optional
            (lib.any (service: service.name == "attic") node.services)
            self.nixosModules.attic
            # Actual Budget, same optional-import pattern, gated on the
            # inventory node placing `actual-budget` (legion-node4
            # today).
            ++ lib.optional
            (lib.any (service: service.name == "actual-budget") node.services)
            self.nixosModules.actual-budget
            # Stirling PDF, same optional-import pattern, gated on the
            # inventory node placing `stirling-pdf`. No node currently
            # places it (modules/hosts/legion/_service-inventory.nix) --
            # this stays as dead-but-harmless gating rather than being
            # removed, so the module (kept in the tree, deferred) needs
            # no code change here to be revived: place it in the
            # inventory again and this import wakes up automatically.
            ++ lib.optional
            (lib.any (service: service.name == "stirling-pdf") node.services)
            self.nixosModules.stirling-pdf
            # H@H, same optional-import pattern, gated on the inventory
            # node placing `hath` (legion-node4 today).
            ++ lib.optional
            (lib.any (service: service.name == "hath") node.services)
            self.nixosModules.hath
            # Blocky, same optional-import pattern, gated on the
            # inventory node placing `blocky` (legion-node2 today).
            # Requires self.nixosModules.netbird (imported fleet-wide
            # above) for both trustedInterfaces and the client service
            # name modules/nixos/blocky.nix orders after.
            ++ lib.optional
            (lib.any (service: service.name == "blocky") node.services)
            self.nixosModules.blocky
            # Monitoring composition (VictoriaMetrics, VictoriaLogs,
            # Grafana, vmalert, Alertmanager), same optional-import
            # pattern, gated on the inventory node placing `monitoring`
            # (legion-node3 today).
            ++ lib.optional
            (lib.any (service: service.name == "monitoring") node.services)
            self.nixosModules.monitoring
            # Hermes, same optional-import pattern, gated on the inventory
            # node placing `hermes`. Fleet facts (peer addresses, the
            # monitoring endpoint) are filled from the inventory here so
            # the module itself hardcodes nothing about this deployment;
            # they are set whenever the module is imported so the staged
            # (disabled) configuration stays evaluable.
            ++ lib.optional
            (lib.any (service: service.name == "hermes") node.services)
            {
              imports = [self.nixosModules.hermes];
              hermes = {
                peerAddresses = map (n: n.privateIPv4) (builtins.attrValues legionNodes);
                metricsUrl = "http://${monitoringNode.privateIPv4}:8428";
              };
            }
            ++ lib.optional
            (lib.any (service: service.name == "hermes" && (service.enabled or false)) node.services)
            {
              hermes.enable = true;
            };
        };
    in
      builtins.mapAttrs mkLegionSystem validatedLegionNodes;
    deploy.nodes =
      builtins.mapAttrs (name: _: {
        hostname = nodeHostname name;
        # Bootstrap: on a node that predates this config the `deploy` user
        # doesn't exist yet, so the first deploy runs as an existing admin
        # over the node's current doas, with magic-rollback off because the
        # first activation removes the doas-based rollback waiter:
        # deploy .#legion-nodeN --ssh-user aidanp --sudo='doas -u' --magic-rollback=false
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
