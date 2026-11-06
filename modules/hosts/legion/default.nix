{
  inputs,
  self,
  lib,
  config,
  ...
}: let
  inherit (config.nixos) modules;

  legionNodes = {
    alda = {
      provider = "hetzner";
      privateIPv4 = "172.17.0.1";
      publicIPv4 = "178.156.226.145";
      publicIPv6 = "2a01:4ff:f0:6b8e::1";
    };

    vida = {
      provider = "hetzner";
      privateIPv4 = "172.17.0.2";
      publicIPv4 = "178.156.201.35";
      publicIPv6 = "2a01:4ff:f0:a1ff::1";
    };

    zantark = {
      provider = "hetzner";
      privateIPv4 = "172.17.0.3";
      publicIPv4 = "178.156.186.147";
      publicIPv6 = "2a01:4ff:f0:c52a::1";
    };

    peria = {
      provider = "hetzner";
      privateIPv4 = "172.17.0.4";
      publicIPv4 = "178.156.191.180";
      publicIPv6 = "2a01:4ff:f0:ca96::1";
    };

    ricklent = {
      provider = "linode";
      privateIPv4 = null;
      publicIPv4 = "23.92.31.67";
      publicIPv6 = "2600:3c02::2000:f4ff:fe3d:6112";
    };
  };

  nodeAddresses = builtins.filter (a: a != null) (lib.concatMap (node: [node.privateIPv4 node.publicIPv4 node.publicIPv6]) (builtins.attrValues legionNodes));

  validatedLegionNodes = assert lib.assertMsg (builtins.length nodeAddresses == builtins.length (lib.unique nodeAddresses))
  "Legion inventory must not reuse an IP address"; legionNodes;

  isHetzner = node: node.provider == "hetzner";

  # Hetzner nodes reach each other over the private network; every other pair goes over the mesh. Null while a node is not yet in modules/netbird-peers.nix.
  legionAddress = from: to:
    if isHetzner legionNodes.${from} && isHetzner legionNodes.${to}
    then legionNodes.${to}.privateIPv4
    else self.lib.netbirdPeers.${to} or null;

  legionServices = config.legion.services;
  servicesByNode = nodeName: builtins.filter (s: s.node == nodeName) (lib.mapAttrsToList (name: s: s // {inherit name;}) legionServices);

  # Ordered by service name (attrset order), so the built unit text stays stable.
  moduleNamesFor = nodeName: lib.unique (builtins.filter (m: m != null) (map (s: s.module) (servicesByNode nodeName)));

  publicPortsFor = nodeName: proto:
    lib.unique (map (o: o.port) (builtins.filter (o: o.proto == proto) (lib.concatMap (s: s.publicPorts) (servicesByNode nodeName))));

  publicPortRangesFor = nodeName: proto:
    map (o: {inherit (o) from to;}) (builtins.filter (o: o.proto == proto) (lib.concatMap (s: s.publicPortRanges) (servicesByNode nodeName)));

  fixedLegionUnits = ["netbird" "netbird-login" "systemd-journal-upload"];

  # The restic pattern matches timers too; the backup-freshness alert reads their last trigger.
  unitIncludeFor = nodeName: let
    units = lib.unique (fixedLegionUnits ++ lib.concatMap (s: s.units) (servicesByNode nodeName));
  in "(${lib.concatStringsSep "|" units})\\.service|(restic-backups|restic-maintenance)-.*\\.(service|timer)";

  nodeHostname = name: "${name}.svr.jeiang.dev";

  serviceAddress = from: service: legionAddress from legionServices.${service}.node;
in {
  flake = {
    lib = {
      inherit legionNodes legionAddress serviceAddress nodeHostname;

      # dns/dnsconfig.js reads this through require(); `just dns-nodes` rewrites the committed dns/nodes.json.
      legionNodesJson = builtins.toJSON (lib.mapAttrs (_: node: {inherit (node) publicIPv4 publicIPv6;}) validatedLegionNodes) + "\n";
    };

    deploy.nodes =
      builtins.mapAttrs (name: _: {
        hostname = nodeHostname name;
        # Bootstrapping a node without the deploy user: deploy .#<name> --ssh-user aidanp --magic-rollback=false
        sshUser = "deploy";
        sudo = "sudo -u";
        profiles.system = {
          user = "root";
          path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.${name};
        };
      })
      validatedLegionNodes;
  };

  nixos = {
    modules.legion = {
      config,
      lib,
      ...
    }: {
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

      systemd.network.enable = true;
      networking = {
        useNetworkd = true;
        nftables.enable = true;
        tempAddresses = "disabled";
        firewall = {
          enable = true;
          allowedTCPPorts = publicPortsFor config.networking.hostName "tcp";
          allowedUDPPorts = publicPortsFor config.networking.hostName "udp";
          allowedTCPPortRanges = publicPortRangesFor config.networking.hostName "tcp";
          allowedUDPPortRanges = publicPortRangesFor config.networking.hostName "udp";
        };
      };

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
          settings.Upload.URL = "http://${serviceAddress config.networking.hostName "monitoring"}:${toString legionServices.monitoring.ports.victoria-logs}/insert/journald";
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
            pauseUnits = lib.mkDefault (map (u: "${u}.service") s.units);
          })
        (builtins.filter (s: s.backupSet != [])
          (servicesByNode config.networking.hostName))
      );

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

          "kernel.kptr_restrict" = 2;
          "kernel.dmesg_restrict" = 1;
          "kernel.unprivileged_bpf_disabled" = 1;
          "net.ipv4.conf.all.accept_redirects" = 0;
          "net.ipv4.conf.default.accept_redirects" = 0;
          "net.ipv6.conf.all.accept_redirects" = 0;
          "net.ipv6.conf.default.accept_redirects" = 0;
          "net.ipv4.conf.all.send_redirects" = 0;
          "net.ipv4.conf.default.send_redirects" = 0;
        };

        tmp.cleanOnBoot = true;
      };

      # A deploy's substitution garbage-collects instead of filling the small root disk.
      nix.settings = {
        min-free = 4 * 1024 * 1024 * 1024;
        max-free = 10 * 1024 * 1024 * 1024;
      };

      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";
    };

    configurations =
      builtins.mapAttrs (name: node: {
        module.imports =
          [
            modules.base
            modules.legion
            modules.${node.provider}
            {networking.hostName = name;}
          ]
          ++ map (m: modules.${m}) (moduleNamesFor name);
      })
      validatedLegionNodes;
  };
}
