{
  inputs,
  self,
  lib,
  config,
  ...
}: let
  inherit (config.nixos) modules;

  publicV4Gateway = "172.31.1.1";
  publicV6Gateway = "fe80::1";

  legionNodes = self.lib.legionNodes;

  nodeAddresses = lib.concatMap (node: [node.privateIPv4 node.publicIPv4 node.publicIPv6]) (builtins.attrValues legionNodes);

  validatedLegionNodes = assert lib.assertMsg (builtins.length nodeAddresses == builtins.length (lib.unique nodeAddresses))
  "Legion inventory must not reuse an IP address"; legionNodes;

  legionServices = config.legion.services;
  servicesByNode = nodeName: builtins.filter (s: s.node == nodeName) (lib.mapAttrsToList (name: s: s // {inherit name;}) legionServices);

  # AGENTS.md hermes-ops tiers: every unit of these whole services is tier 1
  # (restart allowlist); prometheus-blackbox-exporter is tier 1 too, but
  # rides inside the otherwise tier-2 monitoring service, so it is picked
  # out by unit name instead.
  hermesOpsTier1Services = ["gatus" "glance" "garret" "hath" "crowdsec"];
  hermesOpsTier1Units = ["prometheus-blackbox-exporter"];
  hermesOpsNodeExporterUnit = "prometheus-node-exporter";

  hermesOpsTiers =
    lib.mapAttrs (
      name: _: let
        services = servicesByNode name;
        wholeServiceUnits = lib.concatMap (s: s.units) (builtins.filter (s: builtins.elem s.name hermesOpsTier1Services) services);
        pickedUnits = lib.concatMap (s: builtins.filter (u: builtins.elem u hermesOpsTier1Units) s.units) services;
        resticBackupUnits = map (s: "restic-backups-${s.name}") (builtins.filter (s: s.backupSet != [] && s.volume != null) services);
      in
        [hermesOpsNodeExporterUnit] ++ wholeServiceUnits ++ pickedUnits ++ resticBackupUnits
    )
    validatedLegionNodes;

  # Fixed import order keeps the built unit text stable; unlisted services sort last.
  legionModuleOrder = [
    "edge"
    "crowdsec"
    "anubis"
    "netbird-server"
    "netbird-proxy"
    "pocket-id"
    "garret"
    "actual-budget"
    "atuin"
    "hath"
    "blocky"
    "glance"
    "tinyauth"
    "gatus"
    "monitoring"
    "backup-tunnel-responder"
  ];

  moduleNamesFor = nodeName: let
    present = lib.unique (builtins.filter (m: m != null) (map (s: s.module) (servicesByNode nodeName)));
  in
    builtins.filter (m: builtins.elem m present) legionModuleOrder
    ++ builtins.filter (m: !(builtins.elem m legionModuleOrder)) present;

  firewallPortsFor = nodeName: proto: scope: let
    services = servicesByNode nodeName;
    exactOpenings = lib.concatMap (s: s.firewall) services;
    publishedOpenings = lib.concatMap (s: map (p: p // {scope = "public";}) s.publishedPorts) services;
  in
    lib.unique (map (o: o.port) (builtins.filter (o: o.proto == proto && o.scope == scope) (exactOpenings ++ publishedOpenings)));

  firewallPortRangesFor = nodeName: proto: scope: let
    openings = lib.concatMap (s: s.firewallPortRanges) (servicesByNode nodeName);
  in
    map (o: {inherit (o) from to;}) (builtins.filter (o: o.proto == proto && o.scope == scope) openings);

  fixedLegionUnits = ["netbird" "netbird-login" "systemd-journal-upload" "librespeed" "iperf3"];

  # The restic pattern matches timers too; the backup-freshness alert reads their last trigger.
  unitIncludeFor = nodeName: let
    units = lib.unique (fixedLegionUnits ++ lib.concatMap (s: s.units) (servicesByNode nodeName));
  in "(${lib.concatStringsSep "|" units})\\.service|(restic-backups|restic-maintenance)-.*\\.(service|timer)";

  nodeHostname = name: "${lib.removePrefix "legion-" name}.jeiang.dev";

  mkWan = {
    publicIPv4,
    publicIPv6,
  }: {
    matchConfig.Name = "enp1s0";

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

    # dns/dnsconfig.js reads this through require(); `just dns-nodes` rewrites the committed dns/nodes.json.
    lib.legionNodesJson = builtins.toJSON (lib.mapAttrs (_: node: {inherit (node) publicIPv4 publicIPv6;}) validatedLegionNodes) + "\n";

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

  nixos.modules.legion = {
    pkgs,
    config,
    lib,
    ...
  }: {
    imports = [
      self.diskoConfigurations.legion
    ];

    # documentation.man.enable stays on: the toolbox keeps man pages, only the rest of the headless-server bulk goes.
    documentation = {
      nixos.enable = false;
      doc.enable = false;
      info.enable = false;
    };
    xdg = {
      icons.enable = false;
      sounds.enable = false;
      mime.enable = false;
    };
    fonts.fontconfig.enable = false;

    # Host DNS must never use Blocky-over-NetBird as primary resolver: netbird.jeiang.dev has to resolve via public DNS before the tunnel is up.
    sops.secrets."netbird/setup-key".sopsFile = ./secrets.yaml;
    services = {
      prometheus.exporters.node = {
        enable = true;
        enabledCollectors = ["systemd"];
        # Explicit unit-include keeps node_systemd_unit_state cardinality bounded for the memory-constrained VictoriaMetrics; the default `.+` would emit hundreds of series.
        extraFlags = [
          "--collector.systemd.unit-include=${unitIncludeFor config.networking.hostName}"
        ];
      };

      # systemd-journal-upload appends `/upload` itself and VictoriaLogs' route is /insert/journald/upload, so this URL must end at /insert/journald.
      journald.upload = {
        enable = true;
        settings.Upload.URL = "http://${legionNodes.legion-node3.privateIPv4}:${toString legionServices.monitoring.ports.victoria-logs}/insert/journald";
      };

      journald.settings.Journal.SystemMaxUse = "1G";
    };

    backups.jobs = lib.listToAttrs (
      map (s:
        lib.nameValuePair s.name {
          paths = s.backupSet;
          volume =
            if s.volume == null
            then null
            else s.volume.mountpoint;
          pauseUnits = map (u: "${u}.service") s.units;
        })
      (builtins.filter (s: s.backupSet != [])
        (servicesByNode config.networking.hostName))
    );

    # The label is the service name, applied once by the operator; nofail keeps a missing Volume from blocking boot, and mountGuard keeps the service off the unmounted dir.
    fileSystems = lib.listToAttrs (
      map (s:
        lib.nameValuePair s.volume.mountpoint {
          device = "/dev/disk/by-label/${s.name}";
          fsType = "ext4";
          options = ["nofail" "x-systemd.device-timeout=10s"];
        })
      (builtins.filter (s: s.volume != null) (servicesByNode config.networking.hostName))
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
    };

    systemd.network.networks."20-hcloud-private" = {
      matchConfig.Name = "enp7s0";
      networkConfig.DHCP = "ipv4";
      dhcpV4Config.UseRoutes = false;
      routes = [
        {
          Destination = self.lib.hetznerPrivateCidr;
          Gateway = "172.16.0.1";
          GatewayOnLink = true;
        }
      ];
    };

    networking.firewall = {
      allowedTCPPorts = firewallPortsFor config.networking.hostName "tcp" "public";
      allowedUDPPorts = firewallPortsFor config.networking.hostName "udp" "public";
      allowedTCPPortRanges = firewallPortRangesFor config.networking.hostName "tcp" "public";
      allowedUDPPortRanges = firewallPortRangesFor config.networking.hostName "udp" "public";
      trustedInterfaces = ["enp7s0"];
    };

    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "25.05";
  };

  nixos.configurations = let
    mkLegionSystem = name: node: {
      module.imports =
        [
          modules.base
          modules.legion
          {
            networking.hostName = name;

            systemd.network.networks."10-wan" = mkWan {
              inherit (node) publicIPv4 publicIPv6;
            };

            hermesOps.tier1Units = hermesOpsTiers.${name};
          }
        ]
        ++ map (m: modules.${m}) (moduleNamesFor name);
    };
  in
    builtins.mapAttrs mkLegionSystem validatedLegionNodes;
}
