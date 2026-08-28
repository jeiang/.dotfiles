{
  inputs,
  self,
  lib,
  ...
}: let
  publicV4Gateway = "172.31.1.1";
  publicV6Gateway = "fe80::1";

  # Exposed as a flake output (flake.lib.legionNodes below) so other
  # modules (edge, monitoring, netbird-server/proxy) can read these IPs
  # instead of hardcoding their own copies.
  legionNodes = self.lib.legionNodes;

  nodeAddresses = lib.concatMap (node: [node.privateIPv4 node.publicIPv4 node.publicIPv6]) (builtins.attrValues legionNodes);

  legionServices = import ./_service-inventory.nix {inherit lib;};
  unknownServicePlacements = builtins.filter (name: !(legionNodes ? ${name})) (builtins.attrNames legionServices);

  # hermes-ops' per-node Fleet Operations Tiers (docs/adr/0012, CONTEXT.md
  # "Fleet Operations Tiers"/"hermes-ops"): NOT a
  # ./_service-inventory.nix entry -- hermes-ops is cross-cutting fleet
  # policy applied to every node regardless of which services it places
  # (modules/nixos/hermes-ops/default.nix is imported unconditionally
  # below, the same way self.nixosModules.netbird/backups are), not a
  # placed service with its own firewall/backup semantics. Kept as a
  # small table here rather than inside that module so the module itself
  # stays generic (options only) and every other piece of Legion
  # placement data continues to live in this directory. Unit names
  # verified against each owning module (modules/nixos/monitoring,
  # actual-budget.nix, hath.nix, edge/, netbird-server/,
  # pocket-id/, blocky.nix, backups/default.nix's
  # `restic-backups-<service-name>` convention), not guessed.
  hermesOpsTiers = {
    legion-node1 = {
      # exporters/log-shipping-adjacent low-blast-radius units, plus
      # CrowdSec (ban/unban is reversible and scoped, ADR 0012 tier 1).
      # No restic unit here: neither of node1's placed services declares
      # a backupSet (_service-inventory.nix, both stateful = false).
      tier1 = ["crowdsec.service" "prometheus-node-exporter.service"];
      # Caddy is the edge's public entrypoint -- load-bearing for every
      # public hostname this fleet serves (ADR 0012 tier 2). Anubis
      # joins it rather than sitting in tier 1 beside CrowdSec, despite
      # both being edge-security services, because the two fail in
      # opposite directions: CrowdSec is wired fail-open (Caddy keeps
      # serving if the engine is down, see modules/nixos/crowdsec), so a
      # restart costs some enforcement for a few seconds. Anubis is
      # Caddy's upstream for four public hostnames, so a restart 502s
      # them outright -- "load-bearing but recoverable", which is exactly
      # ADR 0012's tier 2 description. It is also the unit that decides
      # whether a visitor is served at all, and an agent should not get
      # to toggle that unprompted.
      tier2 = ["caddy.service" "anubis-content.service"];
    };
    legion-node2 = {
      tier1 = [
        "prometheus-node-exporter.service"
        # Backup trigger units belong in tier 1 (ADR 0012: "triggering
        # backup units" is a free/tier-1 read-adjacent action).
        "restic-backups-netbird-server.service"
        "restic-backups-pocket-id.service"
        # FreshRSS and changedetection.io are self-contained single-user
        # apps published through the reverse proxy: restarting any of
        # their units affects nothing but themselves, unlike the mesh/SSO
        # units in tier 2 below. nginx is here for the same reason -- on
        # this node it serves exactly one thing, FreshRSS's PHP frontend
        # (modules/nixos/freshrss.nix).
        "freshrss-config.service"
        "freshrss-updater.service"
        "phpfpm-freshrss.service"
        "nginx.service"
        "changedetection-io.service"
        "restic-backups-freshrss.service"
        "restic-backups-changedetection-io.service"
        # Color Hunt is the same shape: a self-contained single-operator
        # app whose restart affects nothing but itself.
        "color-hunt.service"
        "restic-backups-color-hunt.service"
      ];
      # Every one of these is load-bearing fleet infrastructure (mesh
      # control plane, SSO, DNS) -- ADR 0012 tier 2 names all five
      # explicitly.
      tier2 = [
        "netbird-server.service"
        "netbird-relay.service"
        "netbird-proxy.service"
        "pocket-id.service"
        "blocky.service"
      ];
    };
    legion-node3 = {
      # hermes-kb-sync: the agent's own durable-memory sync, explicitly
      # named tier 1 in ADR 0012. Both exporters here are node3-specific
      # or fleet-wide low-blast-radius reads.
      tier1 = [
        "hermes-kb-sync.service"
        # obscura: Hermes' own headless-browser sidecar
        # (modules/nixos/hermes/default.nix) -- nothing but Hermes
        # consumes it, so a restart's blast radius is one of Hermes' own
        # tool calls failing mid-flight.
        "obscura.service"
        "prometheus-node-exporter.service"
        "prometheus-blackbox-exporter.service"
      ];
      # The monitoring stack ADR 0012 tier 2 names explicitly.
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
        # Both are read-only presentation layers over data that lives
        # elsewhere -- a restart costs a dashboard reload and, for gatus,
        # its in-memory sample window. Nothing depends on either being
        # up (ADR 0012 tier 1).
        "glance.service"
        "gatus.service"
      ];
      # No node4 unit is load-bearing for anything outside itself --
      # every placed service here is already tier 1. Stop rules still
      # apply (hermes-ops/default.nix generates them for tier1Units too).
      tier2 = [];
    };
  };

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

    # Mount guard for a stateful service's systemd unit: refuse to start
    # unless `dataDir` is actually mounted, so a missing/late Volume never
    # silently initializes fresh state on the root disk instead of the
    # retained data. Used by every service module with a Hetzner Volume
    # (pocket-id, actual-budget, hath, netbird-server).
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
        # Every legion node becomes a NetBird peer, reusing artemis's
        # existing client module unmodified (it stays untouched -- only
        # this host layer adds the setup-key wiring below). Replaces the
        # dropped Kubernetes routing peer for peer-only services (Blocky
        # DNS, raw VictoriaMetrics/VictoriaLogs). legion-node1 (the edge)
        # and legion-node2 (the netbird-server host) become peers too --
        # harmless, and node2 enrolling as a peer of the server it also
        # hosts is exactly how NetBird is reached today.
        self.nixosModules.netbird
        # hermes-ops (docs/adr/0012, CONTEXT.md "hermes-ops"), same
        # unconditional fleet-wide pattern as netbird/backups above --
        # every Legion node gets the account and its sudo allowlist;
        # per-node tier lists come from hermesOpsTiers below, one node
        # (legion-node3) additionally sets `hermesOps.journalGrantees`.
        self.nixosModules.hermes-ops
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
      sops.secrets."netbird/setup-key".sopsFile = ./secrets.yaml;
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
          # (services.actual -> actual.service, monitoring's vmalert instance ->
          # vmalert-default.service, services.journald.upload ->
          # systemd-journal-upload.service, etc.). Flag name
          # `--collector.systemd.unit-include` (a full-match regexp)
          # confirmed against the pinned node_exporter 1.12.0 binary. The
          # trailing `\.service` restricts matches to service units.
          extraFlags = [
            # anubis-content: the Anubis instance name is "content"
            # (modules/nixos/anubis.nix), so the unit is
            # anubis-content.service. Included because it is fail-closed
            # in front of four public hostnames -- a failed unit here is
            # a user-visible 502, and SystemdUnitFailed is the fleet's
            # existing path from that to Alertmanager.
            "--collector.systemd.unit-include=(caddy|crowdsec|crowdsec-firewall-bouncer|anubis-content|garret-pusher|garret-puller|actual|blocky|pocket-id|hath|netbird-server|netbird-relay|netbird-proxy|grafana|victoriametrics|victorialogs|vmalert-default|alertmanager|systemd-journal-upload|hermes-agent|hermes-kb-sync|glance|gatus|freshrss-config|freshrss-updater|phpfpm-freshrss|changedetection-io|color-hunt)\\.service"
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

        # Cap the local journal's on-disk footprint. No explicit limit
        # existed before (systemd's own default is min(10% of the
        # filesystem, 4G) per journald.conf(5) SystemMaxUse), and the edge
        # node's Caddy now writes its per-site access logs to stderr (its
        # named `journald` logger, modules/nixos/edge/default.nix) in
        # addition to runtime logs, adding real volume to the journal on
        # legion-node1. Safe to cap tightly fleet-wide (all four Legion
        # nodes get this, not just the edge) because the local journal is
        # only a short debugging buffer now -- systemd-journal-upload above
        # already ships everything to legion-node3's VictoriaLogs, which
        # retains a month of history.
        journald.extraConfig = "SystemMaxUse=1G";
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
      mkLegionSystem = name: node: let
        # Reused below for both the optional hermes module import and
        # hermesOps.journalGrantees (docs/adr/0012: local journal reads on
        # the hermes-placed node, not sudo -- see that option's doc).
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

                # Per-node Fleet Operations Tiers data (hermesOpsTiers
                # above) plus, on the node hermes is actually placed on,
                # the extra systemd-journal grantee (local journal reads
                # only, no sudo -- see hermesOps.journalGrantees's option
                # doc) -- read lazily from `config` so this evaluates
                # cleanly even on nodes where the hermes module (and its
                # `user` option) was never imported (lib.optional never
                # forces the unused branch).
                hermesOps = {
                  tier1Units = hermesOpsTiers.${name}.tier1;
                  tier2Units = hermesOpsTiers.${name}.tier2;
                  journalGrantees = lib.optional hermesPlaced config.services.hermes-agent.user;
                };
              })
            ]
            # Caddy Edge Node module, only for the inventory's edge node.
            ++ lib.optional (node.edge or false) self.nixosModules.edge
            # CrowdSec engine, same edge-node condition as above. Both
            # modules share the edge.crowdsec.enable toggle.
            ++ lib.optional (node.edge or false) self.nixosModules.crowdsec
            # Anubis proof-of-work gate. Gated on the inventory entry
            # rather than on `node.edge` (the older crowdsec-style
            # condition above): it is a placed service with its own
            # inventory record, so the inventory stays the single source
            # of truth. Importing it is also what flips
            # `edge.anubis.enable`, which is what renders the Caddy side
            # -- see modules/nixos/anubis.nix.
            ++ lib.optional
            (lib.any (service: service.name == "anubis") node.services)
            self.nixosModules.anubis
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
            # garret, the Nix binary cache (docs/adr/0013), same
            # optional-import pattern, gated on the inventory node placing
            # `garret` (legion-node4 today).
            ++ lib.optional
            (lib.any (service: service.name == "garret") node.services)
            self.nixosModules.garret
            # Actual Budget, same optional-import pattern, gated on the
            # inventory node placing `actual-budget` (legion-node4
            # today).
            ++ lib.optional
            (lib.any (service: service.name == "actual-budget") node.services)
            self.nixosModules.actual-budget
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
            # Glance dashboard, same optional-import pattern, gated on the
            # inventory node placing `glance` (legion-node4 today).
            # Requires self.nixosModules.netbird (imported fleet-wide
            # above) for trustedInterfaces, same as blocky: it has no
            # public/private firewall opening at all.
            ++ lib.optional
            (lib.any (service: service.name == "glance") node.services)
            self.nixosModules.glance
            # Gatus status page, same optional-import pattern, gated on
            # the inventory node placing `gatus` (legion-node4 today).
            ++ lib.optional
            (lib.any (service: service.name == "gatus") node.services)
            self.nixosModules.gatus
            # Monitoring composition (VictoriaMetrics, VictoriaLogs,
            # Grafana, vmalert, Alertmanager), same optional-import
            # pattern, gated on the inventory node placing `monitoring`
            # (legion-node3 today).
            ++ lib.optional
            (lib.any (service: service.name == "monitoring") node.services)
            self.nixosModules.monitoring
            # Hermes, same optional-import pattern, gated on the inventory
            # node placing `hermes` (legion-node3 today).
            ++ lib.optional hermesPlaced self.nixosModules.hermes
            # Backup-tunnel responder, same optional-import pattern, gated
            # on the inventory node placing `backup-tunnel` (legion-node1
            # today).
            ++ lib.optional
            (lib.any (service: service.name == "backup-tunnel") node.services)
            self.nixosModules.backupTunnelResponder
            # Camera ingest (WireGuard responder + nginx DAV receiver for
            # the camera phone), same optional-import pattern, gated on
            # the inventory node placing `camera-ingest` (legion-node1
            # today).
            ++ lib.optional
            (lib.any (service: service.name == "camera-ingest") node.services)
            self.nixosModules.camera-ingest
            # FreshRSS, same optional-import pattern, gated on the
            # inventory node placing `freshrss` (legion-node2 today).
            # Published through the NetBird reverse proxy on this same
            # node rather than through the edge (docs/adr/0002).
            ++ lib.optional
            (lib.any (service: service.name == "freshrss") node.services)
            self.nixosModules.freshrss
            # changedetection.io, same optional-import pattern, gated on
            # the inventory node placing `changedetection-io`
            # (legion-node2 today, alongside freshrss above and published
            # the same way).
            ++ lib.optional
            (lib.any (service: service.name == "changedetection-io") node.services)
            self.nixosModules.changedetection-io
            # Color Hunt Validator server, same optional-import pattern,
            # gated on the inventory node placing `color-hunt`
            # (legion-node2 today). Published through the edge Caddy at
            # color-hunt.jeiang.dev, unlike its node2 neighbours above.
            ++ lib.optional
            (lib.any (service: service.name == "color-hunt") node.services)
            self.nixosModules.color-hunt;
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
