{
  self,
  config,
  lib,
  ...
}: let
  lapiPort = 8080;
  metricsPort = 6060;
  appsecPort = 7422;

  legionServices = config.legion.services;
  crowdsecNode = legionServices.crowdsec.node;
  nodeNames = builtins.attrNames self.lib.legionNodes;

  # Every LAPI credential a node uses, readable by that node and by the
  # crowdsec node, which registers it.
  shard = node: ./. + "/secrets.${node}.yaml";
  bouncerSecret = name: "crowdsec/bouncer-${name}";
  machineSecret = node: "crowdsec/machine-${node}-password";

  nodesWhere = pred: lib.unique (map (s: s.node) (builtins.filter pred (builtins.attrValues legionServices)));
  agentNodes = nodesWhere (s: s.module == "crowdsec-agent");
  firewallNodes = nodesWhere (s: s.node != crowdsecNode && builtins.elem "crowdsec-firewall-bouncer" s.units);

  bouncers = config.crowdsec.bouncers // lib.genAttrs' firewallNodes (node: lib.nameValuePair "${node}-firewall" node);
  engineModule = config.nixos.modules.crowdsec-engine;
in {
  options.crowdsec.bouncers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.enum nodeNames);
    default = {};
    description = ''
      Application bouncers registered at the LAPI, each mapped to the node
      that holds its key. Every node running a crowdsec-firewall-bouncer unit
      other than the crowdsec node gets a `<node>-firewall` bouncer without
      an entry here.
    '';
  };

  config = {
    flake.lib = {
      crowdsecBouncerSecret = bouncerSecret;
      crowdsecMachineSecret = machineSecret;
      crowdsecLapiUrl = from: "http://${self.lib.serviceAddress from "crowdsec"}:${toString lapiPort}";
    };

    legion.services.crowdsec = {
      node = "alda";
      module = "crowdsec";
      units = ["crowdsec" "crowdsec-bouncers" "crowdsec-firewall-bouncer"];
      ports = {
        lapi = lapiPort;
        metrics = metricsPort;
        appsec = appsecPort;
      };
    };

    crowdsec.bouncers.edge-caddy = legionServices.caddy.node;

    nixos.modules = {
      legion = {config, ...}: let
        host = config.networking.hostName;
      in {
        sops.secrets =
          lib.mapAttrs' (name: _:
            lib.nameValuePair (bouncerSecret name) {
              sopsFile = shard host;
              restartUnits = lib.optional (name == "${host}-firewall") "crowdsec-firewall-bouncer.service";
            })
          (lib.filterAttrs (_: node: node == host) bouncers)
          // lib.optionalAttrs (builtins.elem host agentNodes) {
            ${machineSecret host}.sopsFile = shard host;
          };

        # Not registerBouncer.enable: that registers against a local crowdsec
        # service; registration lives on the crowdsec node.
        services.crowdsec-firewall-bouncer = lib.mkIf (builtins.elem host firewallNodes) {
          enable = true;
          settings = {
            mode = "nftables";
            api_url = self.lib.crowdsecLapiUrl host;
          };
          registerBouncer.enable = false;
          secrets.apiKeyPath = config.sops.secrets.${bouncerSecret "${host}-firewall"}.path;
        };
      };

      # The sshd log pipeline every crowdsec engine runs, LAPI or agent.
      crowdsec-engine = {
        config,
        lib,
        ...
      }: {
        services.crowdsec = {
          enable = true;
          hub = {
            collections = lib.mkAfter ["crowdsecurity/sshd"];
            parsers = [
              "crowdsecurity/syslog-logs"
              "crowdsecurity/geoip-enrich"
              "crowdsecurity/dateparse-enrich"
            ];
          };
          settings = {
            config.config_paths.data_dir = "/var/lib/crowdsec/state";
            acquisitions = lib.mkAfter [
              {
                source = "journalctl";
                journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
                labels.type = "syslog";
              }
            ];
          };
        };

        systemd.services.crowdsec = {
          path = lib.mkForce [config.systemd.package];
          serviceConfig.SupplementaryGroups = ["systemd-journal"];
        };
      };

      crowdsec = {
        config,
        lib,
        pkgs,
        ...
      }: let
        localAppsecConfigName = "jeiang/appsec-caddy";

        # Local AppSec config: inband vpatch only (out-of-band CRS false-positives
        # on NetBird traffic), with an allow-rule so NetBird's gRPC/WebSocket
        # routes are never blocked. Delivered via tmpfiles, not environment.etc:
        # an etc entry makes appsec-configs/ root-owned and blocks cscli's hub
        # symlink install with "permission denied".
        appsecConfigFile = pkgs.writeText "jeiang-appsec-caddy.yaml" ''
          name: ${localAppsecConfigName}
          default_remediation: ban
          inband_rules:
            - crowdsecurity/base-config
            - crowdsecurity/vpatch-*
          on_match:
            - filter: >-
                req.Host == "${self.lib.netbirdDomain}" &&
                (req.URL.Path startsWith "/signalexchange.SignalExchange/" ||
                req.URL.Path startsWith "/management.ManagementService/" ||
                req.URL.Path startsWith "/management.ProxyService/" ||
                req.URL.Path startsWith "/ws-proxy/")
              apply:
                - CancelEvent()
                - CancelAlert()
                - SetRemediation("allow")
        '';
      in {
        imports = [engineModule];

        services.crowdsec = {
          hub.collections = [
            "crowdsecurity/caddy"
            "crowdsecurity/appsec-virtual-patching" # base-config + vpatch-*, referenced by the local AppSec config
          ];

          settings = {
            config = {
              api.client.credentials_path = "/etc/crowdsec/local_api_credentials.yaml";

              api.server = {
                enable = true;
                # 0.0.0.0: edge Caddy (loopback) and other nodes' bouncers
                # both dial in; the firewall scopes it private.
                listen_uri = "0.0.0.0:${toString lapiPort}";
              };

              # The default loopback bind would be unreachable from zantark's
              # cross-node scraper.
              prometheus.listen_addr = "0.0.0.0";
            };

            acquisitions = [
              {
                # The exact file the edge module's Caddy logFormat writes.
                source = "file";
                filenames = ["${config.services.caddy.logDir}/access.log"];
                labels.type = "caddy";
              }
              {
                source = "appsec";
                listen_addr = "127.0.0.1:${toString appsecPort}";
                path = "/";
                appsec_config = localAppsecConfigName;
                labels.type = "appsec";
              }
            ];

            parsers.s02Enrich = [
              {
                name = "jeiang/mesh-whitelist";
                description = "Never generate bans against Hetzner private network or NetBird mesh traffic";
                whitelist = {
                  reason = "Hetzner private network / NetBird mesh, never bans";
                  cidr = [
                    self.lib.hetznerPrivateCidr
                    self.lib.netbirdMeshCidrv4
                    self.lib.netbirdMeshCidrv6
                  ];
                };
              }
            ];
          };
        };

        systemd.tmpfiles.rules = [
          "d /etc/crowdsec/appsec-configs 0750 ${config.services.crowdsec.user} ${config.services.crowdsec.group} -"
          "L+ /etc/crowdsec/appsec-configs/jeiang-appsec-caddy.yaml - - - - ${appsecConfigFile}"
        ];

        sops.secrets = let
          registration = node: {
            sopsFile = shard node;
            restartUnits = ["crowdsec-bouncers.service"];
          };
        in
          lib.mapAttrs' (name: node: lib.nameValuePair (bouncerSecret name) (registration node)) bouncers
          // lib.genAttrs' agentNodes (node: lib.nameValuePair (machineSecret node) (registration node));

        # Acts on this node's own decisions, sshd bans included; the edge's Caddy bouncer covers only HTTP.
        services.crowdsec-firewall-bouncer = {
          enable = true;
          settings.mode = "nftables";
          registerBouncer.enable = true;
        };

        systemd.services = {
          # No declarative bouncer option exists upstream, so every known key
          # is registered idempotently.
          crowdsec-bouncers = {
            description = "Register CrowdSec LAPI bouncer keys";
            after = ["crowdsec.service"];
            wants = ["crowdsec.service"];
            wantedBy = ["multi-user.target"];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = config.services.crowdsec.user;
              LoadCredential =
                map (name: "${name}:${config.sops.secrets.${bouncerSecret name}.path}") (builtins.attrNames bouncers)
                ++ map (node: "machine-${node}:${config.sops.secrets.${machineSecret node}.path}") agentNodes;
            };
            script = let
              cscli = lib.getExe' config.services.crowdsec.package "cscli";
              # Delete-then-add converges the LAPI on the key currently on disk.
              registerBouncer = name: ''
                ${cscli} bouncers delete ${lib.escapeShellArg name} || true
                ${cscli} bouncers add ${lib.escapeShellArg name} --key "$(cat "$CREDENTIALS_DIRECTORY"/${lib.escapeShellArg name})" > /dev/null
              '';
              # --file - keeps the dump off the local credentials file; --force replaces the machine's stored password.
              registerMachine = name: ''
                ${cscli} machines add ${lib.escapeShellArg name} --password "$(cat "$CREDENTIALS_DIRECTORY"/machine-${lib.escapeShellArg name})" --file - --force > /dev/null
              '';
            in
              lib.concatMapStrings registerBouncer (builtins.attrNames bouncers)
              + lib.concatMapStrings registerMachine agentNodes;
          };

          crowdsec.serviceConfig.MemoryMax = "512M";

          # wants+after, not requires: Caddy must still serve traffic with
          # crowdsec.service stopped or missing (fail-open).
          caddy = lib.mkIf config.services.caddy.enable {
            after = ["crowdsec.service"];
            wants = ["crowdsec.service"];
          };
        };
      };
    };
  };
}
