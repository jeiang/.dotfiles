{
  inputs,
  self,
  lib,
  ...
}: let
  publicV4Gateway = "172.31.1.1";
  publicV6Gateway = "fe80::1";

  legionNodes = self.lib.legionNodes;

  nodeAddresses = lib.concatMap (node: [node.privateIPv4 node.publicIPv4 node.publicIPv6]) (builtins.attrValues legionNodes);

  legionServices = import ./_service-inventory.nix {
    inherit lib;
    ports = self.lib.ports;
  };
  unknownServicePlacements = builtins.filter (name: !(legionNodes ? ${name})) (builtins.attrNames legionServices);

  hermesOpsTiers = {
    legion-node1 = {
      tier1 = ["crowdsec.service" "prometheus-node-exporter.service"];
      tier2 = ["caddy.service" "anubis-content.service"];
    };
    legion-node2 = {
      tier1 = [
        "prometheus-node-exporter.service"
        "restic-backups-netbird-server.service"
        "restic-backups-pocket-id.service"
        "freshrss-config.service"
        "freshrss-updater.service"
        "phpfpm-freshrss.service"
        "nginx.service"
        "changedetection-io.service"
        "restic-backups-freshrss.service"
        "restic-backups-changedetection-io.service"
        "color-hunt.service"
        "restic-backups-color-hunt.service"
      ];
      tier2 = [
        "netbird-server.service"
        "netbird-relay.service"
        "netbird-proxy.service"
        "pocket-id.service"
        "blocky.service"
      ];
    };
    legion-node3 = {
      tier1 = [
        "prometheus-node-exporter.service"
        "prometheus-blackbox-exporter.service"
      ];
      tier2 = [
        "victoriametrics.service"
        "victorialogs.service"
        "grafana.service"
        "vmalert-default.service"
        "alertmanager.service"
      ];
    };
    legion-node4 = {
      tier1 = [
        "actual.service"
        "hath.service"
        "garret-pusher.service"
        "garret-puller.service"
        "restic-backups-actual-budget.service"
        "restic-backups-garret.service"
        "restic-backups-hath.service"
        "prometheus-node-exporter.service"
        "glance.service"
        "gatus.service"
      ];
      tier2 = [];
    };
  };

  validatedLegionNodes = assert lib.assertMsg (builtins.length nodeAddresses == builtins.length (lib.unique nodeAddresses))
  "Legion inventory must not reuse an IP address";
  assert lib.assertMsg (unknownServicePlacements == [])
  "Legion service inventory places services on unknown nodes: ${builtins.concatStringsSep ", " unknownServicePlacements}";
    lib.mapAttrs (name: node: node // (legionServices.${name} or {})) legionNodes;

  firewallPortsFor = nodeName: proto: scope: let
    services = validatedLegionNodes.${nodeName}.services or [];
    exactOpenings = lib.concatMap (service: service.firewall or []) services;
    publishedOpenings = lib.concatMap (service: map (p: p // {scope = "public";}) (service.publishedPorts or [])) services;
  in
    lib.unique (map (o: o.port) (builtins.filter (o: o.proto == proto && o.scope == scope) (exactOpenings ++ publishedOpenings)));

  firewallPortRangesFor = nodeName: proto: scope: let
    openings = lib.concatMap (service: service.firewallPortRanges or []) (validatedLegionNodes.${nodeName}.services or []);
  in
    map (o: {inherit (o) from to;}) (builtins.filter (o: o.proto == proto && o.scope == scope) openings);

  nodeHostname = name: "${lib.removePrefix "legion-" name}.jeiang.dev";

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
    lib.legionNodes = {
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

    # Refuses to start a stateful unit unless dataDir is mounted, so a missing Volume never initializes fresh state on the root disk.
    lib.mountGuard = dataDir: {
      unitConfig = {
        RequiresMountsFor = [dataDir];
        ConditionPathIsMountPoint = dataDir;
      };
    };

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
        self.nixosModules.netbird
        self.nixosModules.hermes-ops
        self.diskoConfigurations.legion
      ];

      # Host DNS must never use Blocky-over-NetBird as primary resolver: netbird.jeiang.dev has to resolve via public DNS before the tunnel is up.
      sops.secrets."netbird/setup-key".sopsFile = ./secrets.yaml;
      services = {
        netbird.clients.default.login = {
          enable = true;
          setupKeyFile = config.sops.secrets."netbird/setup-key".path;
        };

        prometheus.exporters.node = {
          enable = true;
          enabledCollectors = ["systemd"];
          # Explicit unit-include keeps node_systemd_unit_state cardinality bounded for the memory-constrained VictoriaMetrics; the default `.+` would emit hundreds of series.
          extraFlags = [
            "--collector.systemd.unit-include=(caddy|crowdsec|crowdsec-firewall-bouncer|anubis-content|garret-pusher|garret-puller|actual|blocky|pocket-id|hath|netbird-server|netbird-relay|netbird-proxy|grafana|victoriametrics|victorialogs|vmalert-default|alertmanager|systemd-journal-upload|glance|gatus|freshrss-config|freshrss-updater|phpfpm-freshrss|changedetection-io|color-hunt)\\.service"
          ];
        };

        # systemd-journal-upload appends `/upload` itself and VictoriaLogs' route is /insert/journald/upload, so this URL must end at /insert/journald.
        journald.upload = {
          enable = true;
          settings.Upload.URL = "http://${legionNodes.legion-node3.privateIPv4}:${toString self.lib.ports.legion-node3.victoria-logs}/insert/journald";
        };

        journald.extraConfig = "SystemMaxUse=1G";
      };

      backups.jobs = lib.listToAttrs (
        map (service:
          lib.nameValuePair service.name {
            paths = service.backupSet;
            pauseUnits = service.backupPauseUnits or [];
          })
        (builtins.filter (service: service ? backupSet && (service.volume or {}) ? hcloudVolumeId)
          (validatedLegionNodes.${config.networking.hostName}.services or []))
      );

      # A service contributes no mount until the operator fills in volume.hcloudVolumeId; nofail keeps a missing Volume from blocking boot (mountGuard keeps the service off the unmounted dir).
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
            # deploy-rs magic rollback confirms via `sudo rm /tmp/deploy-rs-canary-<hash>`; without NOPASSWD the confirmation times out and every deploy rolls back.
            {
              command = "/run/current-system/sw/bin/rm /tmp/deploy-rs-canary-*";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];

      boot = {
        # Required by services.netbird's useRoutingFeatures = "both".
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

      # STUN (UDP 3478) and H@H (TCP 8888) are opened fleet-wide rather than pinned to their owning node.
      networking.firewall = {
        allowedTCPPorts = firewallPortsFor config.networking.hostName "tcp" "public" ++ [8888];
        allowedUDPPorts = firewallPortsFor config.networking.hostName "udp" "public" ++ [3478];
        allowedTCPPortRanges = firewallPortRangesFor config.networking.hostName "tcp" "public";
        allowedUDPPortRanges = firewallPortRangesFor config.networking.hostName "udp" "public";
        trustedInterfaces = ["enp7s0"];
      };

      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";
    };

    nixosConfigurations = let
      mkLegionSystem = name: node: let
        hermesPlaced = lib.any (service: service.name == "hermes") node.services;
      in
        inputs.nixpkgs.lib.nixosSystem {
          modules =
            [
              self.nixosModules.legionConfiguration
              ({
                config,
                lib,
                ...
              }: {
                networking.hostName = name;

                systemd.network.networks."10-wan" = mkWan {
                  inherit (node) publicIPv4 publicIPv6;
                };

                # journalGrantees reads config lazily: lib.optional never forces the branch on nodes where the hermes module (and its `user` option) is not imported.
                hermesOps = {
                  tier1Units = hermesOpsTiers.${name}.tier1;
                  tier2Units = hermesOpsTiers.${name}.tier2;
                  journalGrantees = lib.optional hermesPlaced config.services.hermes-agent.user;
                };
              })
            ]
            ++ lib.optional (node.edge or false) self.nixosModules.edge
            ++ lib.optional (node.edge or false) self.nixosModules.crowdsec
            ++ lib.optional
            (lib.any (service: service.name == "anubis") node.services)
            self.nixosModules.anubis
            ++ lib.optional
            (lib.any (service: service.name == "netbird-server") node.services)
            self.nixosModules.netbird-server
            ++ lib.optional
            (lib.any (service: service.name == "netbird-proxy") node.services)
            self.nixosModules.netbird-proxy
            ++ lib.optional
            (lib.any (service: service.name == "pocket-id") node.services)
            self.nixosModules.pocket-id
            ++ lib.optional
            (lib.any (service: service.name == "garret") node.services)
            self.nixosModules.garret
            ++ lib.optional
            (lib.any (service: service.name == "actual-budget") node.services)
            self.nixosModules.actual-budget
            ++ lib.optional
            (lib.any (service: service.name == "hath") node.services)
            self.nixosModules.hath
            ++ lib.optional
            (lib.any (service: service.name == "blocky") node.services)
            self.nixosModules.blocky
            ++ lib.optional
            (lib.any (service: service.name == "glance") node.services)
            self.nixosModules.glance
            ++ lib.optional
            (lib.any (service: service.name == "gatus") node.services)
            self.nixosModules.gatus
            ++ lib.optional
            (lib.any (service: service.name == "monitoring") node.services)
            self.nixosModules.monitoring
            ++ lib.optional hermesPlaced self.nixosModules.hermes
            ++ lib.optional
            (lib.any (service: service.name == "backup-tunnel") node.services)
            self.nixosModules.backupTunnelResponder
            ++ lib.optional
            (lib.any (service: service.name == "camera-ingest") node.services)
            self.nixosModules.camera-ingest
            ++ lib.optional
            (lib.any (service: service.name == "freshrss") node.services)
            self.nixosModules.freshrss
            ++ lib.optional
            (lib.any (service: service.name == "changedetection-io") node.services)
            self.nixosModules.changedetection-io
            ++ lib.optional
            (lib.any (service: service.name == "color-hunt") node.services)
            self.nixosModules.color-hunt;
        };
    in
      builtins.mapAttrs mkLegionSystem validatedLegionNodes;
    deploy.nodes =
      builtins.mapAttrs (name: _: {
        hostname = nodeHostname name;
        # Bootstrapping a node without the deploy user: deploy .#legion-nodeN --ssh-user aidanp --sudo='doas -u' --magic-rollback=false
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
